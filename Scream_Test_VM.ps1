################################################################################################
# This file will be used as the control script for all of the steps in the scream test process #
################################################################################################

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
    Connect-AzAccount -Environment AzureCloud -WarningAction Ignore > $null
    Set-AzContext -Subscription Enterprise > $null

    $commercialappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Commercial-App-ID' -AsPlainText
    $commercialappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Commercial-Secret' -AsPlainText
    $commercialtenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Azure-Tenant-ID' -AsPlainText
    $govappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Gov-App-ID' -AsPlainText
    $govappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Gov-Client-Secret' -AsPlainText
    $govtenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Gov-Tenant-ID' -AsPlainText
    $gccappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-GCC-App-ID' -AsPlainText
    $gccappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-GCC-Client-Secret' -AsPlainText
    $gcctenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'GCC-Tenant-ID' -AsPlainText
    $prodpass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
    $sqlinstance = 'txadbsazu001.database.windows.net'
    $sqlDatabase = 'TIS_CMDB'
    $SqlCredential = New-Object System.Management.Automation.PSCredential ('ORRCheckSql', ((Get-AzKeyVaultSecret -vaultName "kv-308" -name 'ORRChecks-Sql').SecretValue))
}
catch {
    Write-Error "Could not get keys from the vault" -ErrorAction Stop
}

# Log scream test user
$decommisionedby = whoami
$splituser = $decommisionedby.Split('\')
$ADuser = $splituser[1]

start-sleep -Seconds 5

# logging in via app registration
Disconnect-AzAccount > $null
Disconnect-AzAccount > $null
Disconnect-AzAccount > $null

# for some reason, I have to put -Environment flag when using app registrations to login - MSFT docs say you don't have to,
# but MSFT has a "set" order of clouds you log into sequentially if you don't specify -Environment,
# EVEN IF YOU PROVIDE THE -TENANT FLAG IT DOESN'T WORK PROPERLY....rant over
if ($VmRF.Environment -eq 'AzureCloud')
{
    $appsecretsecure = ConvertTo-SecureString $commercialappsecret -AsPlainText -Force
    $commercialappregcredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $commercialappid, $appsecretsecure

    try {
        Write-Host "Logging into Commercial Cloud" -ForegroundColor Yellow
        Connect-AzAccount -ServicePrincipal -Tenant $commercialtenantid -Environment $VmRF.Environment -Credential $commercialappregcredential -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription
    } catch {
        $PSItem.Exception
    }
} elseif ($VmRF.Environment -eq 'AzureUSGovernment') {

    $gccappsecretsecure = ConvertTo-SecureString $gccappsecret -AsPlainText -Force
    $gccappregcredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $gccappid, $gccappsecretsecure

    try 
    { 
        Write-Host "Logging into GCC-H" -ForegroundColor Yellow
        Connect-AzAccount -ServicePrincipal -Tenant $gcctenantid -Environment 'AzureUSGovernment' -Credential $gccappregcredential -WarningAction Ignore > $null 
        Set-AzContext -Subscription $VmRF.Subscription   
    }
    catch {
        $PSItem.Exception
    }
} elseif ($VmRF.Environment -eq 'AzureUSGovernment_Old') {

    # log into old gov
    $govappsecretsecure = ConvertTo-SecureString $govappsecret -AsPlainText -Force
    $govappregcredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $govappid, $govappsecretsecure

    try 
    {
        Write-Host "Logging into Old Gov Cloud" -ForegroundColor Yellow
        Connect-AzAccount -ServicePrincipal -Tenant $govtenantid -Environment $VmRF.Environment -Credential $govappregcredential -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription  
    }
    catch {
        $PSItem.Exception
    }
} else {
    Write-Host "Invalid cloud specified in the JSON file. Please input and try again" -ForegroundColor Yellow
    Exit
}

# need Get-AzVM for this step - the JSON is different and won't work with Get-AzResource
try {
    Write-Host "Retrieving the VM"
    $VM = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.Resource_Group -ErrorAction Stop
} catch {
    $PSItem.Exception
}

if ($VM.Count -gt 1)
{
    Write-Host "There are duplicate VMs with the same name. Please stop and troubleshoot which one to deallocate"
    Exit
} else {
    Write-Host "VM found. Proceeding with other steps..."
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

$findservernameinchange = $getCRticket.result.short_description.split(': ')

if (($getCRticket.result.number -eq $VmRF.Change_Number) -and ($findservernameinchange[1] -eq $VM.Name))
{
    Write-Host "Change request numbers match - proceeding to other steps..." -ForegroundColor Yellow
} else {
    Write-Host "Change request specified in the JSON file does not match what was pulled. Please troubleshoot" -ForegroundColor Yellow
}

# check to see if change request is in scheduled state
$crticketendpoint = "https://textrontest2.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$checkstate = Invoke-RestMethod -Headers $headers -Method Get -Uri $crticketendpoint

if ($checkstate.result.state.display_value -ne 'Scheduled')
{
    Write-Host "Scream test cannot be ran because the change request is not in a scheduled state. Please troubleshoot."
    Exit
}

# Get scream test duration
$screamtestinfo = $getCRticket.result.description.Split(' ')
$screamtestduration = $screamtestinfo[6]

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
# $sctaskchangeendpoint = "https://textrontest2.servicenowservices.com/api/now/import/u_imp_sc_task_update"
# $sctaskchangebody = "{`"u_sys_id`":`"$($getsctaskno.result.sys_id)`",`"u_work_notes`":`"`",`"u_state`":`"3`"}"
# $closesctaskchange = Invoke-RestMethod -Headers $headers -Method Post -Uri $sctaskchangeendpoint -Body $sctaskchangebody

<#==============================
Any other miscellaneous info 
================================#>

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
@{n='Business_Unit'; e={$VM.Tags.BU}},
@{n='Owner'; e={$VM.Tags.Owner}},
@{n='Instance'; e={$VM.Tags.Instance}})

# Environment specific information
$AzureInformation = @()
$AzureInformation = ($VmRF | select Subscription, 
Resource_Group,
@{n='Region'; e={$VM.Location}})

# SNOW information
$SnowInformation = @()
$SnowInformation = ($VmRF | select 'Change_Number',
@{n='Ticket_Number'; e={$ritmnumber}},
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
    Write-Host "The VM $($VM.Name) has already gone through a scream test." -ForegroundColor Yellow -ErrorAction Stop
    Exit
} else {
    Write-host "Starting scream test for $($VM.Name)" -ForegroundColor Yellow
    $Screamtest = Scream_Test -VM $VM
    $Screamtest

    # this will search the properties of each obj in $screamtest[2..4] array
    # if status eq passed, then add a work note
    if (($Screamtest[2].Status[0] -eq 'Passed') -and ($Screamtest[2].Status[1] -eq 'Passed') -and ($Screamtest[2].Status[2]-eq 'Passed'))
    {
        # post comment to ticket for scream test update
        Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect scream test changes" -ForegroundColor Yellow
        $screamtest_worknote_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.'sys_id')"
        $screamtest_worknote = "{`"work_notes`":`"Scream test has been completed.`"}"
        $screamtest_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $screamtest_worknote_url -Body $screamtest_worknote
    } else {
        Write-Host "Something failed in the scream test. A work note update will not be applied to the change" -ForegroundColor Yellow
    } 

    # update dbo.AzureDecom table with Scream test results - can't do this at the end of the script because script exits due to 2 week wait period
    # Validation steps and status
    [System.Collections.ArrayList]$Validation  = @()
    $Validation += $Screamtest[2]

    $screamtestdate = get-date -Format 'yyyy-MM-dd'
    $sqloutputscreamtest = @{}
    $sqloutputscreamtest = [PSCustomObject]@{Change_Number = "$($SnowInformation.Change_Number)";
        RITM_number = "$($SnowInformation.Ticket_Number)";
        Host_Information = "$($HostInformation | convertto-json)";
        Azure_Information = "$($AzureInformation | convertto-json -WarningAction SilentlyContinue)";
        SNOW_Information = "$($SnowInformation | convertto-json -WarningAction SilentlyContinue)";
        Screamtest_Duration_Days = "$($screamtestduration)";
        Screamtest_Status = "$($Validation | convertto-json -WarningAction SilentlyContinue)";
        Output_Screamtest = "$($Screamtest[0,1,3] | convertto-json -WarningAction SilentlyContinue)";
        Screamtest_Datetime = [Datetime]::ParseExact($((get-date $screamtestdate -format 'yyyy-MM-dd')), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)}

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
                AND JSON_VALUE(SNOW_Information, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    } else {
        $screamtest_pass_no = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE dbo.AzureDecom `
                SET Screamtest_Pass = 'N' `
                WHERE Screamtest_Datetime IS NOT NULL `
                AND JSON_VALUE(SNOW_Information, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
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

    $filename = "$($VmRF.Hostname)_$($screamtestdate.ToString())_Scream-Test" 

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