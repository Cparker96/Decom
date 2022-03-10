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
    $prodpass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
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
$getusersysid = ($getritmticket.result).requested_for
$sysidmath = $getusersysid.link.Split('/')
$usersysid = $sysidmath[7]

# Get requestor info
$usermeta = "https://textrontest2.servicenowservices.com/api/now/table/sys_user?sysparm_query=sys_id%3D$($usersysid)"
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
Decom the machine
====================================#>

Write-Host "Deleting the VM and its associated resources" -ForegroundColor Yellow

$DeleteVMObject = Delete-VM -VM $VM
$DeleteVMObject

# this will search the properties of each obj in $DeleteVMObject array
# if status eq passed or skipped, then add a work note
if (($DeleteVMObject[0].Status[0] -eq 'Passed') -and ($DeleteVMObject[0].Status[1] -eq 'Passed') -and ($DeleteVMObject[0].Status[2] -eq 'Passed') -and ($DeleteVMObject[0].Status[3] -eq 'Passed') -and `
    ($DeleteVMObject[0].Status[4] -eq 'Passed') -or ($DeleteVMObject[0].Status[4] -eq 'Skipped'))
{
    # post comment to ticket for VM resources update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect resource changes" -ForegroundColor Yellow
    $delete_vm_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $delete_vm_worknote = "{`"work_notes`":`"VM and associated resources have been deleted.`"}"
    $delete_vm_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_vm_url -Body $delete_vm_worknote
} else {
    Write-Host "Something failed when deleting the VM or its resources. A work note update will not be applied to the change" -ForegroundColor Yellow
}

<#==================================
Take the object out of AD
====================================#>

Write-host "Removing the object from AD" -ForegroundColor Yellow

$DeleteADObject = Remove-ActiveDirectoryObject -VM $VM -cred $cred
$DeleteADObject

# this will search the properties of each obj in $DeleteADObject array
# if status eq passed or skipped, then add a work note
if (($DeleteADObject[1].Status[0] -eq 'Passed') -and ($DeleteADObject[1].Status[1] -eq 'Passed') -and ($DeleteADObject[1].Status[2] -eq 'Passed'))
{
    # post comment to ticket for AD object update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect AD object changes" -ForegroundColor Yellow
    $delete_ADObject_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $delete_ADObject_worknote = "{`"work_notes`":`"AD Object has been taken out.`"}"
    $delete_ADObject_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_ADObject_url -Body $delete_ADObject_worknote
} else {
    Write-Host "Something failed when deleting the AD object. A work note update will not be applied to the change" -ForegroundColor Yellow
}

<#==================================
Unlink the object from Tenable
====================================#>

Write-Host "Unlinking the Tenable agent" -ForegroundColor Yellow

$UnlinkVMObject = UnlinkVM-Tenable -VM $VM -TenableAccessKey $TenableaccessKey -TenableSecretKey $TenableSecretKey 
$UnlinkVMObject

# this will search the properties of each obj in $UnlinkVMObject array
# if status eq passed or skipped, then add a work note
if (($UnlinkVMObject[0].Status[0] -eq 'Passed') -or ($UnlinkVMObject[0].Status[0] -eq 'Skipped') -and ($UnlinkVMObject[0].Status[1] -eq 'Passed'))
{
    # post comment to ticket for unlinking tenable
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect Tenable object changes" -ForegroundColor Yellow
    $tenable_object_url = "https://textrontest2.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $tenable_object_worknote = "{`"work_notes`":`"Tenable object has been unlinked`"}"
    $tenable_object_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $tenable_object_url -Body $tenable_object_worknote
} else {
    Write-Host "Something failed when unlinking the Tenable object. A work note update will not be applied to the change" -ForegroundColor Yellow
}

<#=================================
Formulate Output
===================================#>

$Validation += $DeleteVMObject[0] 
$Validation += $DeleteVMObject[1]
$Validation += $DeleteADObject[1]
$Validation += $UnlinkVMObject[0]

# only input Errors section if there are error objects
[System.Collections.ArrayList]$Errors  = @()
if($null -ne ($Validation | where PsError -ne '' | select step, PsError | fl)){
    $Errors += "Errors :"
    $Errors += "============================"
    $Errors += $validation | where PsError -ne '' | select step, PsError | fl
}

# get the raw data as proof
[System.Collections.ArrayList]$rawData  = @()
#Delete VM
$rawData += "`r`n______Delete VM______"
$rawData += $DeleteVMObject[0] 
#Resources Deleted
$rawData += "`r`n______Resources Deleted______"
$rawData += $DeleteVMObject[1] 
#Check for outstanding resources
$rawData += "`r`n______Outstanding Resources______"
$rawData += $DeleteVMObject[2] 
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

# format output for SQL
$Output_DeleteVMObject = $DeleteVMObject[0] | ConvertTo-Json
$update_sql_delete_VM = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE AzureDecom SET Output_DeleteVMObject = @output_deletevmobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber
            AND Screamtest_Pass = 'Y'" -SqlParameters @{output_deletevmobject = $Output_DeleteVMObject; vmchangenumber = $VmRF.Change_Number}

Start-Sleep -Seconds 15

$Resources_Deleted = $DeleteVMObject[1] | ConvertTo-Json
$update_sql_resources_deleted = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
-Query "UPDATE AzureDecom SET Resources_Deleted = @resources_deleted `
        WHERE Screamtest_Datetime IS NOT NULL `
        AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
        AND Screamtest_Pass = 'Y' `
        AND Output_DeleteVMObject IS NOT NULL" -SqlParameters @{resources_deleted = $Resources_Deleted; vmchangenumber = $VmRF.Change_Number}

Start-Sleep -Seconds 15

if ($null -ne $DeleteVMObject[2])
{
    $Outstanding_Resources = $DeleteVMObject[2] | ConvertTo-Json
    $update_sql_outstanding_resources = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE AzureDecom SET Outstanding_Resources = @outstanding_resources `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Ouput_DeleteVMObject IS NOT NULL `
            AND Resources_Deleted IS NOT NULL" -SqlParameters @{outstanding_resources = $Outstanding_Resources; vmchangenumber = $VmRF.Change_Number}
}
Start-Sleep -Seconds 15

$Output_DeleteADObject = $DeleteADObject | ConvertTo-Json
$update_sql_AD = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE AzureDecom SET Output_DeleteADObject = @output_deleteadobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL `
            AND Resources_Deleted IS NOT NULL" -SqlParameters @{output_deleteadobject = $Output_DeleteADObject; vmchangenumber = $VmRF.Change_Number}

Start-Sleep -Seconds 15

$Output_UnlinkVMObject = $UnlinkVMObject | ConvertTo-Json
$update_sql_tenable = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE AzureDecom SET Output_UnlinkVMObject = @output_unlinkvmobject `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL `
            AND Resources_Deleted IS NOT NULL `
            AND Output_DeleteADObject IS NOT NULL" -SqlParameters @{output_unlinkvmobject = $Output_UnlinkVMObject; vmchangenumber = $VmRF.Change_Number}
            
Start-Sleep -Seconds 15

$decomdate = get-date        
$Decom_Datetime = [Datetime]::ParseExact($((get-date $decomdate -format 'YYYY-MM-dd hh:mm:ss')), 'YYYY-MM-dd hh:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
$update_decom_datetime = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "UPDATE AzureDecom SET Decom_Datetime = @decom_datetime `
            WHERE Screamtest_Datetime IS NOT NULL `
            AND JSON_VALUE(SNOWInformation, '$.Change_Number') = @vmchangenumber `
            AND Screamtest_Pass = 'Y' `
            AND Output_DeleteVMObject IS NOT NULL `
            AND Resources_Deleted IS NOT NULL `
            AND Output_DeleteADObject IS NOT NULL `
            AND Output_UnlinkVMObject IS NOT NULL" -SqlParameters @{decom_datetime = $Decom_Datetime; vmchangenumber = $VmRF.Change_Number}

<#============================================
Write Output to Text file 
#============================================#>	

$filename = "$($VmRF.Hostname)_$($decomdate.ToString('yyyy-MM-dd.hh.mm'))_Decom" 

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

<#============================================
Updating/Closing SNOW Change Request
#============================================#>	

# moving change request to Implement state
Write-Host "Moving $($VmRF.Change_Number) to Implement state"
$changeimplement = "https://textrontest2.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$changeimplementbody = "{`"state`":`"-1`"}"
$movechangetoimplement = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changeimplement -Body $changeimplementbody
Start-Sleep -Seconds 15

# fetching and closing all change tasks
Write-Host "Closing all change tasks"
$changetasks ="https://textrontest2.servicenowservices.com/api/now/table/change_task?sysparm_query=change_request.number%3D$($getCRticket.result.number)^state=1"
$getchangetasks = Invoke-RestMethod -Headers $headers -Method Get -Uri $changetasks

foreach ($changetask in $getchangetasks.result.sys_id)
{
    $changetaskendpoint ="https://textrontest2.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)/task/$($changetask)"
    $changetaskbody = "{`"state`":`"3`"}"
    $closechangestasks = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changetaskendpoint -Body $changetaskbody
}
Start-Sleep -Seconds 15

# Moving change request to Review
Write-Host "Moving $($VmRF.Change_Number) to Review state"
$changereview = "https://textrontest2.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$changereviewbody = "{`"state`":`"0`"}"
$movechangetoreview = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changereview -Body $changereviewbody
Start-Sleep -Seconds 15

# Closing change request
Write-Host "Moving $($VmRF.Change_Number) to Closed state"
$changeclosed = "https://textrontest2.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$changeclosedbody ="{`"close_code`":`"successful`",`"close_notes`":`"Closed Complete.`",`"state`":`"3`"}"
$movechangetoclosed = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changeclosed -Body $changeclosedbody

