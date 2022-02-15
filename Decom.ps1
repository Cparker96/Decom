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
    Connect-AzAccount -Environment AzureCloud -WarningAction Ignore > $null
    Set-AzContext -Subscription Enterprise > $null

    $TenableaccessKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableAccessKey' -AsPlainText
    $TenablesecretKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableSecretKey' -AsPlainText
    $pass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
    $sqlinstance = 'txadbsazu001.database.windows.net'
    $sqlDatabase = 'TIS_CMDB'
    $SqlCredential = New-Object System.Management.Automation.PSCredential ('ORRCheckSql', ((Get-AzKeyVaultSecret -vaultName "kv-308" -name 'ORRChecks-Sql').SecretValue))

    Write-Host "Logging into the cloud specified in the JSON file"
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
#$pass = "sn.datacenter.integration.user"

# Build auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass)))

# Set proper headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')
$headers.Add('Content-Type','application/json')


# Get change request info
$CRmeta = "https://textrontest2.servicenowservices.com/api/now/table/change_request?sysparm_query=number%3D$($VmRF.Change_Number)"

# Send HTTP request
$getCRticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $CRmeta

# Get RITM number
$ritminfo = $getCRticket.result.justification
$ritmarray = $ritminfo.split(' ')
$ritmnumber = $ritmarray[3]

# Get RITM info
$ritmmeta = "https://textrontest2.servicenowservices.com/api/now/table/sc_req_item?sysparm_query=number%3D$($ritmnumber)"

# Send HTTP request
$getritmticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $ritmmeta

# do RITM math to get user sys id
$getusersysid = ($getritmticket.result).'requested_for'
$sysidmath = $getusersysid.link.Split('/')
$usersysid = $sysidmath[7]

# Get requestor info
$usermeta = "https://textrontest2.servicenowservices.com/api/now/table/sys_user?sysparm_query=sys_id%3D$($usersysid)"

# Send HTTP request
$getuserinfo = Invoke-RestMethod -Headers $headers -Method Get -Uri $usermeta

# Get person who opened the request
$username = $getuserinfo.result.name

<#==============================
Any other miscellaneous info 
================================#>
$cred = Get-Credential -Message "Please enter your administrator credentials (username _a@txt.textron.com) and your ERPM password:"
$usersearch = Get-AdUser -Identity $cred.UserName
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
@{n='Instance'; e={$VM.Tags.Instance}},
@{n='Requestor'; e={$username}})

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
@{n='Decommissioned By'; e={$fullname}},
@{n='Date Decommissioned'; e={$todaydate}})

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
    Write-host "Starting scream test for $($VM.Name)"
    $Screamtest = Scream-Test -VM $VM
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
        Status = "$($Validation | convertto-json -WarningAction SilentlyContinue)";
        Output_Screamtest = "$($Screamtest[0,1,3] | convertto-json -WarningAction SilentlyContinue)"
        Screamtest_Datetime = [Datetime]::ParseExact($((get-date $screamtestdate -format 'YYYY-MM-dd hh:mm:ss')), 'YYYY-MM-dd hh:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)}

    $DataTablescreamtest = $sqloutputscreamtest | ConvertTo-DbaDataTable 

    $DataTablescreamtest | Write-DbaDbTableData -SqlInstance $sqlinstance `
    -Database $sqlDatabase `
    -Table dbo.Decom `
    -SqlCredential $SqlCredential 

    if (($Validation[0].Status -eq 'Passed') -and ($Validation[1].Status -eq 'Passed') -and ($Validation[2].Status -eq 'Passed'))
    {
        $screamtest_pass_yes = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
            -Query "UPDATE dbo.Decom `
            SET Screamtest_Pass = 'Y'`
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    } else {
        $screamtest_pass_no = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE dbo.Decom `
        SET Screamtest_Pass = 'N'`
        WHERE Screamtest_Datetime IS NOT NULL `
        AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    }

    Exit
}

<#==================================
Decom the machine
====================================#>

Write-Host "Deleting the VM and its associated resources"

$DeleteVMObject = Delete-VM -VM $VM
$DeleteVMObject

# this will search the properties of each obj in $DeleteVMObject array
# if status eq passed or skipped, then add a work note

if (($DeleteVMObject[0].Status -eq 'Passed') -and ($DeleteVMObject[1].Status -eq 'Passed') -and ($DeleteVMObject[2].Status -eq 'Passed') -and ($DeleteVMObject[3].Status -eq 'Passed'))
{
    # post comment to ticket for VM resources update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect resource changes" -ForegroundColor Yellow
    $delete_vm_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.'sys_id')"
    $delete_vm_worknote = "{`"work_notes`":`"VM and associated resources have been deleted.`"}"
    $delete_vm_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_vm_url -Body $delete_vm_worknote
} else {
    Write-Host "Something failed when deleting the VM or its resources. A work note update will not be applied to the change" -ForegroundColor Yellow
}


<#==================================
Take the object out of AD
====================================#>

Write-host "Removing the object from AD"

$DeleteADObject = Remove-ActiveDirectoryObject -VM $VM -cred $cred
$DeleteADObject

# this will search the properties of each obj in $DeleteADObject array
# if status eq passed or skipped, then add a work note

if (($DeleteADObject[1].Status[0] -eq 'Passed') -and ($DeleteADObject[1].Status[1] -eq 'Passed') -and ($DeleteADObject[1].Status[2] -eq 'Passed'))
{
    # post comment to ticket for AD object update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect AD object changes" -ForegroundColor Yellow
    $delete_ADObject_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.'sys_id')"
    $delete_ADObject_worknote = "{`"work_notes`":`"AD Object has been taken out.`"}"
    $delete_ADObject_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_ADObject_url -Body $delete_ADObject_worknote
} else {
    Write-Host "Something failed when deleting the AD object. A work note update will not be applied to the change" -ForegroundColor Yellow
}

<#==================================
Unlink the object from Tenable
====================================#>

Write-Host "Unlinking the Tenable agent"

$UnlinkVMObject = UnlinkVM-Tenable -VM $VM -TenableAccessKey $TenableaccessKey -TenableSecretKey $TenableSecretKey 
$UnlinkVMObject

# this will search the properties of each obj in $UnlinkVMObject array
# if status eq passed or skipped, then add a work note
if (($UnlinkVMObject[0].Status[0] -eq 'Passed') -and ($UnlinkVMObject[0].Status[1] -eq 'Passed'))
{
    # post comment to ticket for unlinking tenable
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect Tenable object changes" -ForegroundColor Yellow
    $tenable_object_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.'sys_id')"
    $tenable_object_worknote = "{`"work_notes`":`"Tenable object has been unlinked`"}"
    $tenable_object_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $tenable_object_url -Body $tenable_object_worknote
} else {
    Write-Host "Something failed when unlinking the Tenable object. A work note update will not be applied to the change" -ForegroundColor Yellow
}


<#=================================
Formulate Output
===================================#>

$Validation += $DeleteVMObject
$Validation += $DeleteADObject[1]
$Validation += $UnlinkVMObject[0]

# only input Errors section if there are error objects
[System.Collections.ArrayList]$Errors  = @()
if($null -ne ($validation | where PsError -ne '' | select step, PsError | fl)){
    $Errors += "Errors :"
    $Errors += "============================"
    $Errors += $validation | where PsError -ne '' | select step, PsError | fl
}

# get the raw data as proof
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
#Remove AD object
$rawdata += "`r`n______Remove AD Object______"
$rawData += $DeleteADObject[0]
#Unlink Tenable object
$rawdata += "`r`n______Unlink Tenable Object______"
$rawData += $UnlinkVMObject[1]


# format output for textfile
[System.Collections.ArrayList]$output = @()
$output += "Host Information :"
$output += "============================"
$output += $HostInformation
$output += "Environment Specific Information :"
$output += "============================"
$output += $EnvironmentInformation
$output += "SNOW Information :"
$output += "============================"
$output += $SnowInformation
$output += "Validation Steps and Status :"
$output += "============================"
$output += $Validation | Select System, Step, Status, FriendlyError
$output += $Errors
$output += "Validation Step Output :"
$output += "============================"
$output += $rawData

# format output for SQL
$Output_DeleteVMObject = $DeleteVMObject | ConvertTo-Json
$update_sql_delete_VM = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE Decom SET Output_DeleteVMObject = @output_deletevmobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber
            AND Screamtest_Pass = 'Y'" -SqlParameters @{output_deletevmobject = $Output_DeleteVMObject; vmchangenumber = $VmRF.Change_Number}

$Output_DeleteADObject = $DeleteADObject | ConvertTo-Json
$update_sql_AD = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE Decom SET Output_DeleteADObject = @output_deleteadobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL" -SqlParameters @{output_deleteadobject = $Output_DeleteADObject; vmchangenumber = $VmRF.Change_Number}

$Output_UnlinkVMObject = $UnlinkVMObject | ConvertTo-Json
$update_sql_tenable = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE Decom SET Output_UnlinkVMObject = @output_unlinkvmobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL `
            AND Output_DeleteADObject IS NOT NULL" -SqlParameters @{output_unlinkvmobject = $Output_UnlinkVMObject; vmchangenumber = $VmRF.Change_Number}

$decomdate = get-date        
$Decom_Datetime = [Datetime]::ParseExact($((get-date $decomdate -format 'YYYY-MM-dd hh:mm:ss')), 'YYYY-MM-dd hh:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
$update_decom_datetime = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE Decom SET Decom_Datetime = @decom_datetime `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL `
            AND Output_DeleteADObject IS NOT NULL `
            AND Output_UnlinkVMObject IS NOT NULL" -SqlParameters @{decom_datetime = $Decom_Datetime; vmchangenumber = $VmRF.Change_Number}


# $date = get-date
# $sqloutput = @{}
# $sqloutput = [PSCustomObject]@{
#     Output_DeleteVMObject = "$($DeleteVMObject | convertto-json -WarningAction SilentlyContinue)";
#     Output_DeleteADObject = "$($DeleteADObject | convertto-json -WarningAction SilentlyContinue)";
#     Output_UnlinkVMObject = "$($UnlinkVMObject | convertto-json -WarningAction SilentlyContinue)";
#     Decom_Datetime = [Datetime]::ParseExact($((get-date $date -format 'YYYY-MM-dd hh:mm:ss')), 'YYYY-MM-dd hh:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)}

<#============================================
Write Output to Text file 
#============================================#>	

$filename = "$($VmRF.Hostname)_$($Decom_Datetime.ToString('yyyy-MM-dd.hh.mm'))" 
$output | Out-File "C:\Temp\$($filename).txt"

<#============================================
Write Output to database
#============================================#>

# $DataTable = $sqloutput | ConvertTo-DbaDataTable 

# $DataTable | Write-DbaDbTableData -SqlInstance $sqlinstance `
# -Database $sqlDatabase `
# -Table dbo.Decom `
# -SqlCredential $SqlCredential