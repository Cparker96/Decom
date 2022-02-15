<#
    .SYNOPSIS
        Deletes the VM out of Azure and any resources associated with it
    .DESCRIPTION
        This function deletes the VM out of Azure and any resources associated with it
    .PARAMETER Environment
        The $VmObj variable which pulls in metadata from the server 
    .EXAMPLE

    .NOTES
        FunctionName    : Delete-VM
        Created by      : Cody Parker
        Date Coded      : 11/9/2021
        Modified by     : 
        Date Modified   : 

#>
Function Delete-VM
{
    Param
    (
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM
    )

    # setting variables
    [System.Collections.ArrayList]$Validation = @()
    [System.Collections.ArrayList]$resourcesdeleted = @()
    $outstandingresources = $null


    try 
    {
        # removing the lock
        Remove-AzResourceLock -LockName 'SCREAM TEST' -Scope $VM.Id -Force > $null
        start-sleep -Seconds 60

        $retrievelock = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $VM.Name -ResourceGroupName $VM.ResourceGroupName

        if ($null -eq $retrievelock)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Delete Lock'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Delete Lock'
            Status = 'Failed'
            FriendlyError = "The lock on $($VM.Name) could not be taken off"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Delete Lock'
        Status = 'Failed'
        FriendlyError = "Could not find associated lock for $($VM.Name)"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }

    Start-Sleep -Seconds 200

    try 
    {
        $getvm = Get-AzVM -Name $VM.Name
        # delete the VM only
        Remove-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force > $null
        start-sleep -Seconds 60

        $retrievevm = get-azvm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -ErrorAction SilentlyContinue

        if ($null -eq $retrievevm)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Delete VM'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null

            $resourcesdeleted += $getvm
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Delete VM'
            Status = 'Failed'
            FriendlyError = "The VM $($VM.Name) could not be deleted"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Delete Lock'
        Status = 'Failed'
        FriendlyError = "Could not delete VM $($VM.Name). Please check"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted
    }
    
    Start-Sleep -Seconds 200

    try 
    {
        $getdisk = Get-AzDisk -DiskName $VM.StorageProfile.OsDisk.Name
        # remove the OS disk
        $removeosdisk = Remove-AzDisk -ResourceGroupName $VM.ResourceGroupName -DiskName $VM.StorageProfile.OsDisk.Name -Force > $null
        start-sleep -Seconds 60

        $retrievedisk = Get-AzDisk -DiskName $VM.StorageProfile.OsDisk.Name

        if ($null -eq $retrievedisk)
        {   
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Remove OS Disk'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null

            $resourcesdeleted += $getdisk
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Remove OS Disk'
            Status = 'Failed'
            FriendlyError = "The OS disk was not deleted. Please check"
            PsError = $PSItem.Exception}) > $null
        }
    } catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Remove OS Disk'
        Status = 'Failed'
        FriendlyError = "Could not find associated OS disk in Azure"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted
    }

    start-sleep -Seconds 200

    try 
    {
        #$tempname = $VM.Name
        #Deleting associated resources
        $resources = Get-AzResource | where {($_.Name -match $VM.Name) -and (($_.ResourceType -eq 'Microsoft.Compute/disks') -or ($_.ResourceType -eq 'Microsoft.Compute/snapshots') -or ($_.ResourceType -eq 'Microsoft.Network/networkInterfaces'))}
        start-sleep -Seconds 30
        
        if ($resources.Count -gt 0)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Get Resources'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null

            foreach ($resource in $resources)
            {
                if ($resource.ResourceType -eq 'Microsoft.Compute/disks')
                {
                    Write-host "Deleting any data disks"
                    Remove-AzDisk -DiskName $resource.Name -ResourceGroupName $resource.ResourceGroupName -Force > $null
                    Start-sleep -Seconds 100
                    $resourcesdeleted += $resource
                } elseif ($resource.ResourceType -eq 'Microsoft.Compute/snapshots') 
                {
                    Write-Host "Deleting any snapshots"
                    Remove-AzSnapshot -ResourceGroupName $resource.ResourceGroupName -SnapshotName $resource.Name -Force > $null
                    Start-Sleep -Seconds 100
                    $resourcesdeleted += $resource
                } else {
                    Write-Host "Deleting the NIC"
                    Remove-AzNetworkInterface -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name -Force > $null
                    Start-sleep -Seconds 100
                    $resourcesdeleted += $resource
                }
            }
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Get Resources'
            Status = 'Failed'
            FriendlyError = "Could not retrieve resources for $($VM.Name)"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Get Resources'
        Status = 'Failed'
        FriendlyError = "Could not get the resources for Decom"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted
    }

    Start-Sleep -Seconds 200

    try 
    {
        # check to make sure VM was deleted
        $checkvm = Get-AzVM -Name $VmRF.Hostname -ResourceGroupName $VmRF.'Resource Group' -ErrorAction SilentlyContinue

        if ($null -eq $checkvm)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Check VM Status'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Check VM Status'
            Status = 'Failed'
            FriendlyError = "The VM $($VM.Name) was not deleted. Please check"
            PsError = $PSItem.Exception}) > $null
        }
    } catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Check VM Status'
        Status = 'Passed'
        FriendlyError = ""
        PsError = ''}) > $null

        return $Validation, $resourcesdeleted
    }

    try 
    {
        # first check to see if there are any rogue objects associated to the VM
        $rogueobj = Get-AzResource | where-object {$_.Name -match $VM.Name}

        if ($null -eq $rogueobj)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Rogue Objects'
            Status = 'Skipped'
            FriendlyError = "There are no outstanding resources to be deleted"
            PsError = ''}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Rogue Objects'
            Status = 'Passed'
            FriendlyError = "Found resources associated to the VM. Evaluating them now"
            PsError = ''}) > $null

            # if not null, evaulate resource type of each, perform logic based on type
            foreach ($obj in $rogueobj)
            {
                if ($obj.ResourceType -eq 'Microsoft.Network/networkSecurityGroups')
                {
                    $nsg = Get-AzNetworkSecurityGroup -Name $obj.Name
                    # The "!" executes the same is $null, except $null is mainly used to check vars, not properties
                    if ((!$nsg.SecurityRules) -and (!$nsg.NetworkInterfaces) -and (!$nsg.Subnets))
                    {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate NSG'
                        Status = 'Skipped'
                        FriendlyError = "This NSG isn't associated to any NICs, Vnets, etc. Deleting now..."
                        PsError = ''}) > $null
    
                        try 
                        {
                            Remove-AzResource -ResourceId $nsg.Id -Force
                            $checknsg = Get-AzNetworkSecurityGroup -Name $obj.Name
    
                            if ($null -eq $checknsg)
                            {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete NSG'
                                Status = 'Passed'
                                FriendlyError = ""
                                PsError = ''}) > $null
                            } else {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete NSG'
                                Status = 'Failed'
                                FriendlyError = "Failed to delete NSG. Please check"
                                PsError = $PSItem.Exception}) > $null
                            }
                        }
                        catch {
                            $Validation.Add([PSCustomObject]@{System = 'Server' 
                            Step = 'Delete NSG'
                            Status = 'Failed'
                            FriendlyError = "Couldn't locate and delete NSG. Please check"
                            PsError = $PSItem.Exception}) > $null
    
                            return $Validation, $resourcesdeleted
                        }
                    }
                    else {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate NSG'
                        Status = 'Passed'
                        FriendlyError = "Adding this to a list of outstanding resources for now..."
                        PsError = ''}) > $null
    
                        $outstandingresources += $nsg.Name
                        return $Validation, $resourcesdeleted
                    }
                }
                elseif ($obj.ResourceType -eq 'Microsoft.Automation/automationAccounts/runbooks') {
    
                    $runbook = Get-AzAutomationRunbook -Name $obj.Name -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
                    $webhooks = Get-AzAutomationWebhook -RunbookName $obj.RunbookName -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
    
                    # check to see if there are no jobs or webhooks assoc. to the runbook
                    if (($runbook.JobCount -eq 0) -and ($null -eq $webhooks))
                    {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate Automation Acct'
                        Status = 'Skipped'
                        FriendlyError = "This runbook has no jobs or webhooks associated with it. Deleting now..."
                        PsError = ''}) > $null
                        
                        try 
                        {
                            Remove-AzAutomationRunbook -Name $obj.Name -Force
                            $checkrunbook = Get-AzAutomationRunbook -Name $obj.Name -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
    
                            if ($null -eq $checkrunbook)
                            {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete Runbook'
                                Status = 'Passed'
                                FriendlyError = ""
                                PsError = ''}) > $null
                            } else {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete Runbook'
                                Status = 'Failed'
                                FriendlyError = "Failed to delete runbook. Please check"
                                PsError = $PSItem.Exception}) > $null
                            }
                        }
                        catch {
                            $Validation.Add([PSCustomObject]@{System = 'Server' 
                            Step = 'Delete Runbook'
                            Status = 'Failed'
                            FriendlyError = "Couldn't locate and delete runbook. Please check"
                            PsError = $PSItem.Exception}) > $null
    
                            return $Validation, $resourcesdeleted
                        }
                    }
                    else {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate Runbook'
                        Status = 'Passed'
                        FriendlyError = "Adding this to a list of outstanding resources for now..."
                        PsError = ''}) > $null
    
                        $outstandingresources += $runbook.Name
                        return $Validation, $resourcesdeleted
                    }
                } elseif ($obj.ResourceType -eq 'Microsoft.Storage/storageAccounts') {
                    # checking to see if there are any containers, queues, etc. assoc. with the storage account
                    $storageAcc = Get-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name
                    $ctx = $storageAcc.Context
                    $containers = Get-AzStorageContainer -Context $ctx | where {$_.Name -notlike "*vhds*"}
                    $fileshares = Get-AzStorageShare -Context $ctx
    
                    if (($null -eq $containers) -and ($null -eq $fileshares))
                    {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate Storage Acct'
                        Status = 'Skipped'
                        FriendlyError = "This storage account is empty. Deleting now..."
                        PsError = ''}) > $null
    
                        try 
                        {
                            Remove-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name -Force
                            $checkstorageacct = Get-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name
    
                            if ($null -eq $checkstorageacct)
                            {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete Storage Acct'
                                Status = 'Passed'
                                FriendlyError = ""
                                PsError = ''}) > $null
                            } else {
                                $Validation.Add([PSCustomObject]@{System = 'Server' 
                                Step = 'Delete Storage Acct'
                                Status = 'Failed'
                                FriendlyError = "Failed to delete storage account. Please check"
                                PsError = $PSItem.Exception}) > $null
                            }
                        }
                        catch {
                            $Validation.Add([PSCustomObject]@{System = 'Server' 
                            Step = 'Delete Storage Acct'
                            Status = 'Failed'
                            FriendlyError = "Couldn't locate and delete storage account. Please check"
                            PsError = $PSItem.Exception}) > $null
    
                            return $Validation, $resourcesdeleted
                        }
                    }
                    else {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'Locate Storage Acct'
                        Status = 'Passed'
                        FriendlyError = "Adding this to a list of outstanding resources for now..."
                        PsError = ''}) > $null
    
                        $outstandingresources += $storageAcc.StorageAccountName
                        return $Validation, $resourcesdeleted
                    }
                } else {
                    $Validation.Add([PSCustomObject]@{System = 'Server' 
                    Step = 'Locate Storage Acct'
                    Status = 'Passed'
                    FriendlyError = "This resource does not match any of the rogue resource types and should be reviewed by the requestor to ensure safe deletion"
                    PsError = ''}) > $null
    
                    $outstandingresources += $obj.Name
                    return $Validation, $resourcesdeleted
                }
            }
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Rogue Objects'
        Status = 'Failed'
        FriendlyError = "Could not pull any objects associated to the VM. Please check"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted, $outstandingresources
    }
    # return the resources that were deleted and need a second look
    return $Validation, $resourcesdeleted, $outstandingresources
}


# $Body = "Hello 'server_owner',`n`nAs we decommissioned your azure resource(s) detailed in 'ticket_number', `
# there were a few that came up as possibly still in use. Can you provide a 'yes' or 'no' regarding if these resources can be deleted? They look to be `
# housing a few security rules regarding the NSG, data still being stored in a runbook, etc.`n`n$($outstandingresources.Name)"

# Send-MailMessage -From 'cparker01@Textron.com' -To 'CloudOperations@Textron.com' -Subject 'Decom Outstanding Resources' -SmtpServer 'mrbbdc100.textron.com' `
#     -Body $Body