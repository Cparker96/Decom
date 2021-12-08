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
Get Credentials
===========================#>
try {
    Connect-AzAccount -Environment AzureCloud -WarningAction Ignore > $null
    Set-AzContext -Subscription Enterprise > $null

    $TenableaccessKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableAccessKey' -AsPlainText
    $TenablesecretKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableSecretKey' -AsPlainText
    $pass = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'SNOW-API-Password' -AsPlainText 
}
catch {
    Write-Error "Could get keys from the vault" -ErrorAction Stop
}

<#==================================
Pull ticket info from SNOW
====================================#>
$user = "sn.datacenter.integration.user"

# Build auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass)))

# Set proper headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')

# Specify endpoint uri
$uri = "https://textronprod.servicenowservices.com/api/now/table/change_task?sysparm_query=change_request.number%3DCHG0031476"

# Send HTTP request
$response = Invoke-RestMethod -Headers $headers -Method Get -Uri $uri 

# Print response
$response.result

<#===================
Get VM Object
=====================#>
if ($VmRF.Hostname -like "*AZU*")
{
    Set-AzContext -Subscription $VmRF.Subscription
    $VM = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.'Resource Group'
} elseif ($VmRF.Hostname -like "*GOV*") {
    # log out of commercial multiple times, occasionally it won't work for some reason
    Disconnect-AzAccount > $null
    Disconnect-AzAccount > $null
    Disconnect-AzAccount > $null

    try {
        Connect-AzAccount -Environment AzureUSGovernment -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription

        $VM = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.'Resource Group'
    }
    catch {
        Write-Error "Could not login to Azure Gov Cloud" -ErrorAction Stop
    }
} else {
    Write-Host "This VM does not match naming standards. Logging into the cloud specified in the JSON file"

    Disconnect-AzAccount > $null
    Disconnect-AzAccount > $null
    Disconnect-AzAccount > $null

    if ($VmRF.Environment -eq 'AzureCloud')
    {
        Connect-AzAccount -Environment AzureCloud -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription
        $VM = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.'Resource Group'
    } else {
        Connect-AzAccount -Environment AzureUSGovernment -WarningAction Ignore > $null
        Set-AzContext -Subscription $VmRF.Subscription
        $VM = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.'Resource Group'
    }
}

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
    exit
}

<#==================================
Decom the machine
====================================#>
Write-Host "Deleting the VM and its associated resources"

$DeleteVMObject = Delete-VM -VM $VM
$DeleteVMObject
<#==================================
Take the object out of AD
====================================#>
Write-host "Removing the object from AD"
$cred = Get-Credential -Message "Please enter your administrator credentials (username _a@txt.textron.com) and your ERPM password:"

$DeleteADObject = Remove-ActiveDirectoryObject -VM $VM -cred $cred
$DeleteADObject
<#==================================
Unlink the object from Tenable
====================================#>
Write-Host "Unlinking the Tenable agent"

$UnlinkVMObject = UnlinkVM-Tenable -VM $VM -TenableAccessKey $TenableaccessKey -TenableSecretKey $TenableSecretKey 
$UnlinkVMObject
<#=================================
Formulate Output
===================================#>

# $HostInformation = @()
# $HostInformation = ($VmRF | select Hostname,
# @{n='Business Unit'; e={$VM.Tags.BU}},
# @{n='Operating System'; e={$VM.StorageProfile.OsDisk.OsType}},
# @{n='Owner'; e={$VM.Tags.Owner}},
# @{n='Ticket Number'; e={$VmRF.'Ticket Number'}})

# # environment specific information
# $EnvironmentSpecificInformation = @()
# $EnvironmentSpecificInformation = ($VmRF | select Subscription, 'Resource Group',
# @{n='Location'; e={$VM.Location}},
# @{n='Instance'; e={$VM.Tags.Instance}})

# #Validation steps and status
# [System.Collections.ArrayList]$Validation  = @()
# $Validation += ($Screamtest | where {$_.gettype().name -eq 'ArrayList'})
# $Validation += ($DeleteVMObject | where {$_.gettype().name -eq 'ArrayList'})
# $Validation += ($DeleteADObject | where )









