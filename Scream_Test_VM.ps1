##########################################################################################
# This file will be used as the control script for all of the steps in the decom process #
##########################################################################################

# Get server variables from the JSON
try {
    $VmRF = Get-Content .\VM_Request_Fields.json | ConvertFrom-Json -AsHashtable
} catch {
    Write-Error "Could not load VM_Request_Fields.json `r`n $($_.Exception)" -ErrorAction Stop
}

<#=========================
Get Credentials & VM
===========================#>

try {
    $appsecretsecure = ConvertTo-SecureString $VmRF.Commercial_Client_Secret -AsPlainText -Force
    $logincredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $VmRF.Commercial_Client_App_ID, $appsecretsecure
    Connect-AzAccount -ServicePrincipal -Tenant $VmRF.Commercial_Tenant_ID -Credential $logincredential -WarningAction Ignore > $null
   # Connect-AzAccount -Environment AzureCloud -WarningAction Ignore > $null
    Set-AzContext -Subscription Enterprise > $null

    $snowprodpass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
    $sqlinstance = 'txadbsazu001.database.windows.net'
    $sqlDatabase = 'TIS_CMDB'
    $SqlCredential = New-Object System.Management.Automation.PSCredential ('ORRCheckSql', ((Get-AzKeyVaultSecret -vaultName "kv-308" -name 'ORRChecks-Sql').SecretValue))

    Write-Host "Logging into the cloud specified in the JSON file" -ForegroundColor Yellow
    if ($VmRF.Environment -eq 'AzureCloud') 
    {
        Set-AzContext -Subscription $VmRF.Subscription
        $VM = Get-AzVM -Name $VmRF.Hostname  
    } else {
        Disconnect-AzAccount > $null
        Disconnect-AzAccount > $null
        Disconnect-AzAccount > $null
        
        Connect-AzAccount -Environment $VmRF.Environment -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription

        $VM = Get-AzVM -Name $VmRF.Hostname  
    }
}
catch {
    Write-Error "Could get keys from the vault" -ErrorAction Stop
}

<#==================================
Pull ticket info from SNOW
====================================#>

$user = "sn.datacenter.integration.user"
$pass = "sn.datacenter.integration.user"

# Build auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass)))

# Set proper headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')
$headers.Add('Content-Type','application/json')


# Get change request info
$CRmeta = "https://textrontest2.servicenowservices.com/api/now/table/change_request?sysparm_query=number%3D$($VmRF.Change_Number)"
$getCRticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $CRmeta

# Get RITM number
$ritminfo = $getCRticket.result.justification
$ritmarray = $ritminfo.split(' ')
$ritmnumber = $ritmarray[3]

# Get RITM info
$ritmmeta = "https://textrontest2.servicenowservices.com/api/now/table/sc_req_item?sysparm_query=number%3D$($ritmnumber)"
$getritmticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $ritmmeta

# do RITM math to get user sys id
$getusersysid = ($getritmticket.result).'requested_for'
$sysidmath = $getusersysid.link.Split('/')
$usersysid = $sysidmath[7]

# Get requestor info
$usermeta = "https://textrontest2.servicenowservices.com/api/now/table/sys_user?sysparm_query=sys_id%3D$($usersysid)"
$getuserinfo = Invoke-RestMethod -Headers $headers -Method Get -Uri $usermeta

# Get person who opened the request
$username = $getuserinfo.result.name

# closing change request that was opened upon RITM request
$sctaskritmendpoint = "https://textrontest2.servicenowservices.com/api/now/table/sc_task?sysparm_query=request_item%3D$($getritmticket.result.sys_id)"
$getsctaskno = Invoke-RestMethod -Headers $headers -Method Get -Uri $sctaskritmendpoint

# using staging table to make changes to SCTASK that's opened in PROD
$sctaskchangeendpoint = "https://textrontest2.servicenowservices.com/api/now/import/u_imp_sc_task_update"
$sctaskchangebody = "{`"u_sys_id`":`"$($getsctaskno.result.sys_id)`",`"u_work_notes`":`"`",`"u_state`":`"3`"}"
$closesctaskchange = Invoke-RestMethod -Headers $headers -Method Post -Uri $sctaskchangeendpoint -Body $sctaskchangebody

<#==============================
Any other miscellaneous info 
================================#>

$decommisionedby = whoami
$splituser = $decommisionedby.Split('\')
$ADuser = $splituser[1]

$usersearch = Get-AdUser -Identity $ADuser
$fullname = $usersearch.GivenName + ' ' + $usersearch.Surname

# Get today's date
$todaydate = Get-Date -Format 'MM/dd/yyyy'

<#=========================================
Formulate output for scream test results
===========================================#>

# Server specific information
$HostInformation = @()
$HostInformation = ($VmRF | select Hostname,
@{n='Business Unit'; e={$VM.Tags.BU}},
@{n='Owner'; e={$VM.Tags.Owner}},
@{n='Instance'; e={$VM.Tags.Instance}})

# Environment specific information
$EnvironmentInformation = @()
$EnvironmentInformation = ($VmRF | select Subscription, 
Resource_Group,
@{n='Region'; e={$VM.Location}})

# SNOW information
$SnowInformation = @()
$SnowInformation = ($VmRF | select 'Change_Number',
@{n='Ticket Number'; e={$ritmnumber}},
@{n='Requestor'; e={$username}},
@{n='Scream Tested By'; e={$fullname}},
@{n='Scream Test Date'; e={$todaydate}})

<#==================================
Perform the Scream Test if necessary
====================================#>

$provisioningstate = $VM | Get-AzVM -Status
$checktags = Get-azTag -ResourceId $VM.Id
$lock = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $VM.Name -ResourceGroupName $VM.ResourceGroupName

# checking to see if the VM has gone through a scream test
if (($null -ne $lock) -and ($checktags.Properties.TagsProperty.Keys.Contains('Decom')) -and ($provisioningstate.Statuses[1].DisplayStatus -eq 'VM deallocated'))
{
    Write-Host "The VM $($VM.Name) has already gone through a scream test. Proceeding to other steps" -ForegroundColor Yellow -ErrorAction Stop
} else {
    Write-host "Starting scream test for $($VM.Name)" -ForegroundColor Yellow
    $Screamtest = Scream_Test -VM $VM
    $Screamtest

    # this will search the properties of each obj in $screamtest[2..4] array
    # if status eq passed, then add a work note
    if (($Screamtest[2].Status[0] -eq 'Passed') -and ($Screamtest[2].Status[1] -eq 'Passed') -and ($Screamtest[2].Status[2] -eq 'Passed'))
    {
        # post comment to ticket for scream test update
        Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect scream test changes" -ForegroundColor Yellow
        $screamtest_worknote_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.'sys_id')"
        $screamtest_worknote = "{`"work_notes`":`"Scream test has been completed.`"}"
        $screamtest_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $screamtest_worknote_url -Body $screamtest_worknote
    } else {
        Write-Host "Something failed in the scream test. A work note update will not be applied to the change" -ForegroundColor Yellow
    } 

    # update dbo.Decom table with Scream test results - can't do this at the end of the script because script exits due to 2 week wait period
    # Validation steps and status
    [System.Collections.ArrayList]$Validation  = @()
    $Validation += $Screamtest[2]

    $screamtestdate = get-date
    $sqloutputscreamtest = @{}
    $sqloutputscreamtest = [PSCustomObject]@{HostInformation = "$($HostInformation | convertto-json)";
        EnvironmentInformation = "$($EnvironmentInformation | convertto-json -WarningAction SilentlyContinue)";
        SNOWInformation = "$($SnowInformation | convertto-json -WarningAction SilentlyContinue)";
        Screamtest_Status = "$($Validation[0,1,2] | convertto-json -WarningAction SilentlyContinue)";
        Output_Screamtest = "$($Screamtest[0,1,3] | convertto-json -WarningAction SilentlyContinue)"
        Screamtest_Datetime = [Datetime]::ParseExact($((get-date $screamtestdate -format 'YYYY-MM-dd hh:mm:ss')), 'YYYY-MM-dd hh:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)}

    $DataTablescreamtest = $sqloutputscreamtest | ConvertTo-DbaDataTable 

    $DataTablescreamtest | Write-DbaDbTableData -SqlInstance $sqlinstance `
    -Database $sqlDatabase `
    -Table dbo.AzureDecom `
    -SqlCredential $SqlCredential 

    if (($Validation[0].Status -eq 'Passed') -and ($Validation[1].Status -eq 'Passed') -and ($Validation[2].Status -eq 'Passed'))
    {
        $screamtest_pass_yes = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE dbo.AzureDecom `
            SET Screamtest_Pass = 'Y' `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    } else {
        $screamtest_pass_no = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE dbo.AzureDecom `
            SET Screamtest_Pass = 'N' `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    }

    # only input Errors section if there are error objects
    [System.Collections.ArrayList]$Errors  = @()
    if ($null -ne ($Validation | where PsError -ne '' | select step, PsError | fl)){
        $Errors += "Errors :"
        $Errors += "============================"
        $Errors += $Validation | where PsError -ne '' | select step, PsError | fl
    }

    [System.Collections.ArrayList]$rawData  = @()
    #Scream test - Stop VM
    $rawData += "`r`n______Scream Test - Stop VM______"
    $rawData += $Screamtest[1]
    #Scream test - Tag VM
    $rawData += "`r`n______Scream Test - Tag VM______"
    $rawData += $Screamtest[0] 
    #Scream test - Lock VM
    $rawData += "`r`n______Scream Test - Lock VM______"
    $rawData += $Screamtest[3] 

    # format output for textfile
    [System.Collections.ArrayList]$output = @()
    $output += "Host Information :"
    $output += "============================"
    $output += $HostInformation | fl
    $output += "Azure Information :"
    $output += "============================"
    $output += $EnvironmentInformation | fl
    $output += "SNOW Information :"
    $output += "============================"
    $output += $SNOWInformation | fl
    $output += "Validation Steps and Status :"
    $output += "============================"
    $output += $Validation | Select System, Step, Status, FriendlyError | ft
    $output += $Errors
    $output += "Validation Step Output :"
    $output += "============================"
    $output += $rawData

    $filename = "$($VmRF.Hostname)_$($screamtestdate.ToString('yyyy-MM-dd.hh.mm'))_Scream-Test" 

    # have to change outputrendering variable because of encoding issues - it will change back to default
    $prevRendering = $PSStyle.OutputRendering
    $PSStyle.OutputRendering = 'PlainText'

    try {
        $output | Out-File "C:\Temp\$($filename).txt"
    }
    catch {
        $PSItem.Exception
    } 

    $PSStyle.OutputRendering = $prevRendering
}
