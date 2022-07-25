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

    $commercialappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Commercial-App-ID' -AsPlainText
    $commercialappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Commercial-Secret' -AsPlainText
    $commercialtenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Azure-Tenant-ID' -AsPlainText
    $govappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Gov-App-ID' -AsPlainText
    $govappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-Gov-Client-Secret' -AsPlainText
    $govtenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Gov-Tenant-ID' -AsPlainText
    $gccappid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-GCC-App-ID' -AsPlainText
    $gccappsecret = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'Decom-GCC-Client-Secret' -AsPlainText
    $gcctenantid = Get-AzKeyVaultSecret -VaultName 'kv-308' -Name 'GCC-Tenant-ID' -AsPlainText
    $TenableaccessKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableAccessKey' -AsPlainText
    $TenablesecretKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableSecretKey' -AsPlainText
    $snowapiuser = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-User' -AsPlainText 
    $snowapipass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
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
        Connect-AzAccount -ServicePrincipal -Tenant $govtenantid -Environment 'AzureUSGovernment' -Credential $govappregcredential -WarningAction Ignore > $null
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
    Write-Host "Could not find $($VmRF.Hostname) in the subscription/RG mentioned" -ForegroundColor Red
    Exit
}

if ($VM.Count -gt 1)
{
    Write-Host "There are duplicate VMs with the same name. Please stop and troubleshoot which one to deallocate" -ForegroundColor Yellow
    Exit
} else {
    Write-Host "VM found. Proceeding with other steps..." -ForegroundColor Yellow
}

<#==================================
Pull ticket info from SNOW
====================================#>

# Build auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $snowapiuser, $snowapipass)))

# Set proper headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')
$headers.Add('Content-Type','application/json')

# Get change request info
$CRmeta = "https://textronprod.servicenowservices.com/api/now/table/change_request?sysparm_query=number%3D$($VmRF.Change_Number)"
$getCRticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $CRmeta

if ($getCRticket.result.number -eq $VmRF.Change_Number)
{
    Write-Host "Change request numbers match for $($VmRF.Change_Number) - proceeding to other steps..." -ForegroundColor Yellow
} else {
    Write-Host "Change request specified in the JSON file does not match what was pulled. Please troubleshoot" -ForegroundColor Yellow
    Exit
}

$findservernameinchange = $getCRticket.result.short_description.split(': ')

if ($findservernameinchange[1] -eq $VM.Name)
{
    Write-Host "VM name matches for $($VmRF.Hostname) - proceeding to other steps..." -ForegroundColor Yellow
} else {
    Write-Host "VM name specified in the change does not match what is specified in the CR. Please troubleshoot" -ForegroundColor Yellow
    Exit
}

# check to see if change request is in scheduled state
$crticketendpoint = "https://textronprod.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$checkstate = Invoke-RestMethod -Headers $headers -Method Get -Uri $crticketendpoint

if ($checkstate.result.state.display_value -ne 'Scheduled')
{
    Write-Host "Scream test cannot be ran because the change request is not in a scheduled state. Please troubleshoot." -ForegroundColor Yellow
    Exit
}

# Get scream test duration
$screamtestinfo = $getCRticket.result.description.Split(' ')
$screamtestduration = $screamtestinfo[6]

# check to see if its time to decom the stuff
$retrievescreamtestdate = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
-Query "SELECT TOP 1 * FROM dbo.AzureDecom `
        WHERE Change_Number = @vmchangenumber `
        AND Screamtest_Datetime IS NOT NULL `
        AND Screamtest_Pass = 'Y'" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}

# this date needs to be today's date ($todaydate) - this is assumed to be ran when scream test is over
$todaydate = get-date
$targetdate = $retrievescreamtestdate.Screamtest_Datetime.AddDays($screamtestduration)
$deltadays = $targetdate - $todaydate

if ($null -eq $targetdate)
{
    Write-Host "This VM hasn't ran through a proper scream test. Please run 'Scream_Test_VM.ps1' first" -ForegroundColor Yellow -ErrorAction Stop
    Exit
}

if ($deltadays.Days -le 0)
{
    Write-Host "VM can be decommissioned. Proceeding to other steps" -ForegroundColor Yellow
} else {
    Write-Host "VM hasn't been scream tested for the alloted time. Please wait" -ForegroundColor Yellow
    Exit
}

# Get RITM number
$ritminfo = $getCRticket.result.justification
$ritmarray = $ritminfo.split(' ')
$ritmnumber = $ritmarray[3]

# Get RITM info
$ritmmeta = "https://textronprod.servicenowservices.com/api/now/table/sc_req_item?sysparm_query=number%3D$($ritmnumber)"
$getritmticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $ritmmeta

# do RITM math to get user sys id
$getusersysid = ($getritmticket.result).requested_for
$sysidmath = $getusersysid.link.Split('/')
$usersysid = $sysidmath[7]

# Get requestor info
$usermeta = "https://textronprod.servicenowservices.com/api/now/table/sys_user?sysparm_query=sys_id%3D$($usersysid)"
$getuserinfo = Invoke-RestMethod -Headers $headers -Method Get -Uri $usermeta

# Get person who opened the request
$username = $getuserinfo.result.name

<#==============================
Any other miscellaneous info 
================================#>

$cred = Get-Credential -Message "Please enter your administrator credentials (Ex: user_a) and your ERPM password:"
$usersearch = Get-AdUser -Identity $cred.UserName
$fullname = $usersearch.GivenName + ' ' + $usersearch.Surname

<#=========================================
Formulate output for scream test results
===========================================#>

# Server information
$HostInformation = @()
$HostInformation = ($VmRF | select Hostname,
@{n='Business_Unit'; e={$VM.Tags.BU}},
@{n='Owner'; e={$VM.Tags.Owner}},
@{n='Instance'; e={$VM.Tags.Instance}},
@{n='Requestor'; e={$username}})

# Azure information
$AzureInformation = @()
$AzureInformation = ($VmRF | select Subscription, 
Resource_Group,
@{n='Region'; e={$VM.Location}})

# SNOW information
$SnowInformation = @()
$SnowInformation = ($VmRF | select 'Change_Number',
@{n='Ticket_Number'; e={$ritmnumber}},
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
if (($DeleteVMObject[0].Status[0] -eq 'Passed') -and ($DeleteVMObject[0].Status[1] -eq 'Passed') -and ($DeleteVMObject[0].Status[2] -eq 'Passed' -or $DeleteVMObject[0].Status[2] -eq 'Skipped') -and ($DeleteVMObject[0].Status[3] -eq 'Passed') -and `
    ($DeleteVMObject[0].Status[4] -eq 'Passed') -or ($DeleteVMObject[0].Status[4] -eq 'Skipped'))
{
    # post comment to ticket for VM resources update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect resource changes" -ForegroundColor Yellow
    $delete_vm_url = "https://textronprod.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
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
if (($DeleteADObject[0].Status -eq 'Passed') -and ($DeleteADObject[1].Status -eq 'Skipped'))
{
    # post comment to ticket for AD object update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect AD object changes" -ForegroundColor Yellow
    $delete_ADObject_url = "https://textronprod.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $delete_ADObject_worknote = "{`"work_notes`":`"No AD object was found. It either didn't exist or someone prior to this operation deleteed it.`"}"
    $delete_ADObject_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_ADObject_url -Body $delete_ADObject_worknote
} elseif (($DeleteADObject[0].Status -eq 'Passed') -and ($DeleteADObject[1].Status -eq 'Passed') -and ($DeleteADObject[2].Status -eq 'Passed')) {
    # post comment to ticket for AD object update
    Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect AD object changes" -ForegroundColor Yellow
    $delete_ADObject_url = "https://textronprod.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $delete_ADObject_worknote = "{`"work_notes`":`"AD Object has been taken out.`"}"
    $delete_ADObject_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $delete_ADObject_url -Body $delete_ADObject_worknote
} 
else {
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
if (($UnlinkVMObject[0][0].Status -eq 'Passed') -and ($UnlinkVMObject[0][1].Status -eq 'Skipped'))
{
    # post comment to ticket for unlinking tenable
    Write-Host "Updating Change Request $($VmRF.Change_Number) to reflect Tenable object changes" -ForegroundColor Yellow
    $tenable_object_url = "https://textronprod.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $tenable_object_worknote = "{`"work_notes`":`"Connection established, but no Tenable object found. Someone else has already deleted it.`"}"
    $tenable_object_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $tenable_object_url -Body $tenable_object_worknote
} elseif (($UnlinkVMObject[0][0].Status -eq 'Passed') -and ($UnlinkVMObject[0][1].Status -eq 'Passed') -and ($UnlinkVMObject[0][2].Status -eq 'Passed')) {
    # post comment to ticket for unlinking tenable
    Write-Host "Updating Change Request $($VmRF.Change_Number) to reflect Tenable object changes" -ForegroundColor Yellow
    $tenable_object_url = "https://textronprod.servicenowservices.com/api/now/table/change_request/$($getCRticket.result.sys_id)"
    $tenable_object_worknote = "{`"work_notes`":`"Tenable object successfully deleted.`"}"
    $tenable_object_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $tenable_object_url -Body $tenable_object_worknote
}
else {
    Write-Host "Something failed when unlinking the Tenable object. A work note update will not be applied to the change" -ForegroundColor Yellow
}

<#=================================
Formulate Output
===================================#>

[System.Collections.ArrayList]$Validation = @()
$Validation += $DeleteVMObject[0] 
$Validation += $DeleteVMObject[1]
$Validation += $DeleteADObject[1]
$Validation += $UnlinkVMObject[0]

# only input Errors section if there are error objects
[System.Collections.ArrayList]$Errors  = @()
if ($null -ne ($Validation | where PsError -ne '' | select step, PsError | fl))
{
    $Errors += "Errors :"
    $Errors += "============================"
    $Errors += $validation | where PsError -ne '' | select step, PsError | fl
}

# get the raw data as proof
[System.Collections.ArrayList]$rawData = @()
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
$rawData += $DeleteADObject[1-2] 
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
$output += $AzureInformation | fl
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
$quickscreamtestdateformat = $retrievescreamtestdate.Screamtest_Datetime
$decomdate = get-date -Format 'yyyy-MM-dd'
$sqloutputdecom = @{}
$sqloutputdecom = [PSCustomObject]@{Change_Number = "$($SnowInformation.Change_Number)";
    RITM_Number = "$($SnowInformation.Ticket_Number)";
    Host_Information = "$($HostInformation | convertto-json)";
    Azure_Information = "$($AzureInformation | convertto-json -WarningAction SilentlyContinue)";
    SNOW_Information = "$($SnowInformation | convertto-json -WarningAction SilentlyContinue)";
    Screamtest_Duration_Days = "$($screamtestduration)";
    Screamtest_Status = "$($retrievescreamtestdate.Screamtest_Status | convertto-json -WarningAction SilentlyContinue)";
    Output_Screamtest = "$($retrievescreamtestdate.Output_Screamtest | convertto-json -WarningAction SilentlyContinue)";
    Screamtest_Datetime = [Datetime]::ParseExact($((get-date $quickscreamtestdateformat -format 'yyyy-MM-dd')), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture);
    Screamtest_Pass = "$($retrievescreamtestdate.Screamtest_Pass)";
    Output_DeleteVMObject = "$($DeleteVMObject[0] | convertto-json -WarningAction SilentlyContinue)";
    Resources_Deleted = "$($DeleteVMObject[1] | convertto-json -WarningAction SilentlyContinue)";
    Outstanding_Resources = "$($DeleteVMObject[2]| convertto-json -WarningAction SilentlyContinue)";
    Output_DeleteADObject = "$($DeleteADObject | convertto-json -WarningAction SilentlyContinue)";
    Output_UnlinkVMObject = "$($UnlinkVMObject | convertto-json -WarningAction SilentlyContinue)";
    Decom_Datetime = [Datetime]::ParseExact($((get-date $decomdate -format 'yyyy-MM-dd')), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)}

$DataTabledecom = $sqloutputdecom | ConvertTo-DbaDataTable 

$DataTabledecom | Write-DbaDbTableData -SqlInstance $sqlinstance `
-Database $sqlDatabase `
-Table dbo.AzureDecom `
-SqlCredential $SqlCredential

# check to make sure the sql record was written
$checksqlrecord = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "SELECT * from dbo.AzureDecom `
            WHERE Change_Number = @vmchangenumber `
            AND Decom_Datetime IS NOT NULL" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}

if ($null -eq $checksqlrecord)
{
    Write-Host "There was an internal issue with writing a scream test record to SQL. This can happen because the server name variable in the change request was inputted incorrectly. `
    Some unaccepted formats would be 'servername.txt.textron.com' or servername / 'IP Address'. The correct format should ONLY consist of 'servername'. Please add a comment on the change mentioning `
    that a SQL record was not written but that the outputted Scream Test .txt file will still be attached to the change for visibility." -ForegroundColor Yellow
} else {
    Write-Host "SQL record successfully written to DB" -ForegroundColor Green
}

<#============================================
Write Output to Text file 
#============================================#>	

$filename = "$($VmRF.Hostname)_$($decomdate.ToString())_Decom" 

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
$changeimplement = "https://textronprod.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
$changeimplementbody = "{`"state`":`"-1`"}"
$movechangetoimplement = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changeimplement -Body $changeimplementbody
Start-Sleep -Seconds 15

# fetching and closing all change tasks
Write-Host "Closing all change tasks related to $($VmRF.Change_Number)"
$changetasks ="https://textronprod.servicenowservices.com/api/now/table/change_task?sysparm_query=change_request.number%3D$($getCRticket.result.number)^state=1"
$getchangetasks = Invoke-RestMethod -Headers $headers -Method Get -Uri $changetasks

foreach ($changetask in $getchangetasks.result.sys_id)
{
    $changetaskendpoint ="https://textronprod.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)/task/$($changetask)"
    $changetaskbody = "{`"state`":`"3`"}"
    $closechangestasks = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changetaskendpoint -Body $changetaskbody
}
Start-Sleep -Seconds 15

if ($delta.days -lt 0) 
{ 
    # Closing change request with issues
    Write-Host "Moving $($VmRF.Change_Number) to Closed state"
    $changeclosed = "https://textronprod.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
    $changeclosedbody ="{`"close_code`":`"successful_issues`",`"close_notes`":`"Resources were deleted outside of change window.`",`"state`":`"3`"}"
    $movechangetoclosed = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changeclosed -Body $changeclosedbody
} else {
    # Closing change request
    Write-Host "Moving $($VmRF.Change_Number) to Closed state"
    $changeclosed = "https://textronprod.servicenowservices.com/api/sn_chg_rest/change/$($getCRticket.result.sys_id)"
    $changeclosedbody ="{`"close_code`":`"successful`",`"close_notes`":`"Closed complete.`",`"state`":`"3`"}"
    $movechangetoclosed = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changeclosed -Body $changeclosedbody
}