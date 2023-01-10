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
    Connect-AzAccount -Environment 'your_tenant' -WarningAction Ignore > $null
    Set-AzContext -Subscription 'your_subscription' > $null

    $commercialappid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $commercialappsecret = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $commercialtenantid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $govappid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $govappsecret = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $govtenantid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $gccappid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $gccappsecret = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $gcctenantid = Get-AzKeyVaultSecret -VaultName 'your_vault_name' -Name 'your_secret_name' -AsPlainText
    $snowapiuser = Get-AzKeyVaultSecret -vaultName 'your_vault_name' -name 'your_secret_name' -AsPlainText 
    $snowapipass = Get-AzKeyVaultSecret -vaultName 'your_vault_name' -name 'your_secret_name' -AsPlainText 
    $sqlinstance = 'your_sql_instance'
    $sqlDatabase = 'your_sql_database'
    $SqlCredential = New-Object System.Management.Automation.PSCredential ('your_secret_name', ((Get-AzKeyVaultSecret -vaultName "your_vault_name" -name 'your_secret_name').SecretValue))
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

# retrieve VM from the portal
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

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')
$headers.Add('Content-Type','application/json')

# Get change request info
$CRmeta = "your_SNOW_endpoint"
$getCRticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $CRmeta

$findservernameinchange = $getCRticket.result.short_description.split(': ')

if ($getCRticket.result.number -eq $VmRF.Change_Number)
{
    Write-Host "Change request numbers match for $($VmRF.Change_Number) - proceeding to other steps..." -ForegroundColor Yellow
} else {
    Write-Host "Change request specified in the JSON file does not match what was pulled. Please troubleshoot" -ForegroundColor Yellow
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
$crticketendpoint = "your_SNOW_endpoint"
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
$ritmmeta = "your_SNOW_endpoint"
$getritmticket = Invoke-RestMethod -Headers $headers -Method Get -Uri $ritmmeta

# do RITM math to get user sys id
$getusersysid = ($getritmticket.result).'requested_for'
$sysidmath = $getusersysid.link.Split('/')
$usersysid = $sysidmath[7]

# Get requestor info
$usermeta = "your_SNOW_endpoint"
$getuserinfo = Invoke-RestMethod -Headers $headers -Method Get -Uri $usermeta

# Get person who opened the request
$username = $getuserinfo.result.name

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
    $Screamtest = Scream_Test -VM $VM -VmRF $VmRF
    $Screamtest

    # if status eq passed, then add a work note
    if (($Screamtest[2].Status[0] -eq 'Passed') -and ($Screamtest[2].Status[1] -eq 'Passed') -and ($Screamtest[2].Status[2]-eq 'Passed'))
    {
        # post comment to ticket for scream test update
        Write-Host "Updating Change Request $($VmRF.'Change_Number') to reflect scream test changes" -ForegroundColor Yellow
        $screamtest_worknote_url = "your_SNOW_endpoint"
        $screamtest_worknote = "{`"work_notes`":`"Scream test has been completed.`"}"
        $screamtest_update = Invoke-RestMethod -Headers $headers -Method Patch -Uri $screamtest_worknote_url -Body $screamtest_worknote
    } else {
        Write-Host "Something failed in the scream test. A work note update will not be applied to the change" -ForegroundColor Yellow
    } 
}

# update SQL table with Scream test results - can't do this at the end of the script because script exits due to 2 week wait period
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
-Table 'your_sql_table' `
-SqlCredential $SqlCredential 

# check to make sure that the sql record was created
$checksqlrecord = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
    -Query "SELECT * FROM 'your_sql_table' `
            WHERE Change_Number = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}

if ($null -eq $checksqlrecord)
{
    Write-Host "There was an internal issue with writing a scream test record to SQL. This can happen because the server name variable in the change request was inputted incorrectly. `
    Some unaccepted formats would be 'servername.domain.com' or servername / 'IP Address'. The correct format should ONLY consist of 'servername'. Please add a comment on the change mentioning `
    that a SQL record was not written but that the outputted Scream Test .txt file will still be attached to the change for visibility." -ForegroundColor Yellow
} else {
    if (($Validation[0].Status -eq 'Passed') -and ($Validation[1].Status -eq 'Passed') -and ($Validation[2].Status -eq 'Passed'))
    {
        $screamtest_pass_yes = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE 'your_sql_table' `
                SET Screamtest_Pass = 'Y' `
                WHERE Screamtest_Datetime IS NOT NULL `
                AND JSON_VALUE(SNOW_Information, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
    } else {
        $screamtest_pass_no = Invoke-DbaQuery -SqlInstance $sqlinstance -Database $sqlDatabase -SqlCredential $SqlCredential `
        -Query "UPDATE dbo.AzureDecom `
                SET Screamtest_Pass = 'N' `
                WHERE Screamtest_Datetime IS NOT NULL `
                AND JSON_VALUE(SNOW_Information, '$.Change_Number') = @vmchangenumber" -SqlParameters @{vmchangenumber = $VmRF.Change_Number}
        
        Write-Host "Something failed in the scream test when evaluating all sections passed. Please troubleshoot" -ForegroundColor Yellow
    }
    Write-Host "SQL record successfully written to DB" -ForegroundColor Green
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

# fetching and closing the 'scream test vm' change task
Write-Host "Closing the 'scream test vm' task related to $($VmRF.Change_Number)"
$changetasks ="your_SNOW_endpoint"
$getchangetasks = Invoke-RestMethod -Headers $headers -Method Get -Uri $changetasks

foreach ($changetask in $getchangetasks.result.sys_id)
{
    $changetaskendpoint ="your_SNOW_endpoint"
    $changetaskbody = "{`"state`":`"3`"}"
    $closechangestasks = Invoke-RestMethod -Headers $headers -Method Patch -Uri $changetaskendpoint -Body $changetaskbody
}

Start-Sleep -Seconds 10