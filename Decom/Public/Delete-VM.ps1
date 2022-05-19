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
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        [parameter(Position = 0, Mandatory=$true)] $VmRF
    )

    # setting variables
    [System.Collections.ArrayList]$Validation = @()
    [System.Collections.ArrayList]$resourcesdeleted = @()

    try 
    {
        Write-Host "Removing the scream test resource lock"
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

    Start-Sleep -Seconds 100

    try 
    {
        $getvm = (Get-AzVM -Name $VM.Name | select Name).Name
        # delete the VM only
        Write-Host "Deleting VM - $($getvm)"
        Remove-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force > $null
        start-sleep -Seconds 100

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
    
    Start-Sleep -Seconds 100

    try 
    {
        $getdisk = (Get-AzDisk -DiskName $VM.StorageProfile.OsDisk.Name | select Name).Name
        $getosdeleteoption = $VM.StorageProfile.OsDisk.DeleteOption

        if ($getosdeleteoption -eq 'Detach' -or ($null -eq $getosdeleteoption))
        {
            # remove the OS disk
            Write-Host "Deleting OS Disk - $($getdisk)"
            $removeosdisk = Remove-AzDisk -ResourceGroupName $VM.ResourceGroupName -DiskName $VM.StorageProfile.OsDisk.Name -Force > $null
            start-sleep -Seconds 100

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
        } else {
            Write-Host "Due to the JSON property of 'Delete' on the VM, the OS disk was deleted when the VM was deleted" -ForegroundColor Yellow

            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Remove OS Disk'
            Status = 'Skipped'
            FriendlyError = ""
            PsError = ''}) > $null
        }

    } catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Remove OS Disk'
        Status = 'Failed'
        FriendlyError = "Could not find associated OS disk in Azure"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted
    }

    start-sleep -Seconds 100

    try 
    {
       # I know there is probably a better way to find this - but this is how im currently getting the nic
       # VM JSON properties don't have any NIC names in it
       $nicId = $VM.NetworkProfile.NetworkInterfaces.Id
       $nicarray = $nicId.Split('/')
       $getnic = (Get-AzNetworkInterface -ResourceGroupName $VM.ResourceGroupName -Name $nicarray[8] | select Name).Name
       Write-Host "Deleting NIC - $($getnic)"
       $removenic = Remove-AzNetworkInterface -Name $nicarray[8] -ResourceGroupName $VM.ResourceGroupName -Force
       start-sleep -Seconds 100
       $retrievenic = Get-AzNetworkInterface -Name $nicarray[8]

       if ($null -eq $retrievenic)
       {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Remove NIC'
        Status = 'Passed'
        FriendlyError = ""
        PsError = ''}) > $null

        $resourcesdeleted += $getnic
       } else {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Remove NIC'
        Status = 'Failed'
        FriendlyError = "The NIC was not deleted. Please check"
        PsError = $PSItem.Exception}) > $null
       }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Remove NIC'
        Status = 'Failed'
        FriendlyError = "Could not find associated NIC in Azure"
        PsError = $PSItem.Exception}) > $null

        return $Validation, $resourcesdeleted
    }

    start-sleep -Seconds 100

    try 
    {
        #Deleting associated resources
        $resources = Get-AzResource | where {($_.Name -match $VM.Name) -and (($_.ResourceType -eq 'Microsoft.Compute/disks') -or ($_.ResourceType -eq 'Microsoft.Compute/snapshots'))}
        start-sleep -Seconds 30

        if ($resources.count -gt 0)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Get Resources'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null

            foreach ($resource in $resources)
            {
                # evaluate the resource type then delete it
                if ($resource.ResourceType -eq 'Microsoft.Compute/disks')
                {
                    $getdatadisk = (Get-AzDisk -ResourceGroupName $VM.ResourceGroupName -DiskName $resource.Name | select Name).Name
                    Write-Host "Deleting Data Disk - $($getdatadisk)"
                    Remove-AzDisk -DiskName $resource.Name -ResourceGroupName $resource.ResourceGroupName -Force > $null
                    Start-sleep -Seconds 100
                    $resourcesdeleted += $getdatadisk
                } elseif ($resource.ResourceType -eq 'Microsoft.Compute/snapshots') {
                    $getsnapshot = (Get-AzSnapshot -ResourceGroupName $VM.ResourceGroupName -SnapshotName $resource.Name | select Name).Name
                    Write-Host "Deleting Snapshot - $($getsnapshot)"
                    Remove-AzSnapshot -ResourceGroupName $resource.ResourceGroupName -SnapshotName $resource.Name -Force > $null
                    Start-Sleep -Seconds 100
                    $resourcesdeleted += $getsnapshot
                }
            }
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Get Resources'
            Status = 'Skipped'
            FriendlyError = "There are no extra resources to delete at this time"
            PsError = ''}) > $null
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

    Start-Sleep -Seconds 100

    # pull remaining associated resources
    try 
    {
        if ($VmRF.Hostname -like "*DBS*")
        {
            $tempname = $VM.Name
            $remainingresources = Get-AzResource -Name $tempname* | where {$_.ResourceType -ne 'Microsoft.Automation/AutomationAccounts/Runbooks'} | select Name, ResourceType
        } else {
            $tempname = $VM.Name
            $remainingresources = Get-AzResource -Name $tempname* | select Name, ResourceType
        }
    }
    catch {
        $PSItem.Exception
    }

    # check to see if RG is null - if it is then delete it
    $checkrgresources = Get-AzResource -ResourceGroupName $VmRF.ResourceGroupName

    if ($checkrgresources.Count -eq 0)
    {
        try {
            Write-Host "Deleting RG $($VmRF.ResourceGroupName) since nothing is in it"
            $deleterg = Remove-AzResourceGroup -Name $VM.ResourceGroupName -Force > $null
            start-sleep -Seconds 60
        }
        catch {
            $PSItem.Exception
        }  
    }

    # try 
    # {
    #     # first check to see if there are any rogue objects associated to the VM
    #     $rogueobj = Get-AzResource | where-object {$_.Name -match $VM.Name}

    #     if ($null -eq $rogueobj)
    #     {
    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'Rogue Objects'
    #         Status = 'Skipped'
    #         FriendlyError = "There are no outstanding resources to be deleted"
    #         PsError = ''}) > $null
    #     } else {
    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'Rogue Objects'
    #         Status = 'Passed'
    #         FriendlyError = "Found resources associated to the VM. Evaluating them now"
    #         PsError = ''}) > $null

    #         # if not null, evaulate resource type of each, perform logic based on type
    #         foreach ($obj in $rogueobj)
    #         {
    #             if ($obj.ResourceType -eq 'Microsoft.Network/networkSecurityGroups')
    #             {
    #                 $nsg = Get-AzNetworkSecurityGroup -Name $obj.Name
    #                 # The "!" executes the same is $null, except $null is mainly used to check vars, not properties
    #                 if ((!$nsg.SecurityRules) -and (!$nsg.NetworkInterfaces) -and (!$nsg.Subnets))
    #                 {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate NSG'
    #                     Status = 'Skipped'
    #                     FriendlyError = "This NSG isn't associated to any NICs, Vnets, etc. Deleting now..."
    #                     PsError = ''}) > $null
    
    #                     try 
    #                     {
    #                         Remove-AzResource -ResourceId $nsg.Id -Force
    #                         $checknsg = Get-AzNetworkSecurityGroup -Name $obj.Name
    
    #                         if ($null -eq $checknsg)
    #                         {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete NSG'
    #                             Status = 'Passed'
    #                             FriendlyError = ""
    #                             PsError = ''}) > $null
    #                         } else {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete NSG'
    #                             Status = 'Failed'
    #                             FriendlyError = "Failed to delete NSG. Please check"
    #                             PsError = $PSItem.Exception}) > $null
    #                         }
    #                     }
    #                     catch {
    #                         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                         Step = 'Delete NSG'
    #                         Status = 'Failed'
    #                         FriendlyError = "Couldn't locate and delete NSG. Please check"
    #                         PsError = $PSItem.Exception}) > $null
    
    #                         return $Validation, $resourcesdeleted
    #                     }
    #                 }
    #                 else {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate NSG'
    #                     Status = 'Passed'
    #                     FriendlyError = "Adding this to a list of outstanding resources for now..."
    #                     PsError = ''}) > $null
    
    #                     $outstandingresources += $nsg.Name
    #                     return $Validation, $resourcesdeleted
    #                 }
    #             }
    #             elseif ($obj.ResourceType -eq 'Microsoft.Automation/automationAccounts/runbooks') {
    
    #                 $runbook = Get-AzAutomationRunbook -Name $obj.Name -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
    #                 $webhooks = Get-AzAutomationWebhook -RunbookName $obj.RunbookName -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
    
    #                 # check to see if there are no jobs or webhooks assoc. to the runbook
    #                 if (($runbook.JobCount -eq 0) -and ($null -eq $webhooks))
    #                 {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate Automation Acct'
    #                     Status = 'Skipped'
    #                     FriendlyError = "This runbook has no jobs or webhooks associated with it. Deleting now..."
    #                     PsError = ''}) > $null
                        
    #                     try 
    #                     {
    #                         Remove-AzAutomationRunbook -Name $obj.Name -Force
    #                         $checkrunbook = Get-AzAutomationRunbook -Name $obj.Name -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName
    
    #                         if ($null -eq $checkrunbook)
    #                         {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete Runbook'
    #                             Status = 'Passed'
    #                             FriendlyError = ""
    #                             PsError = ''}) > $null
    #                         } else {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete Runbook'
    #                             Status = 'Failed'
    #                             FriendlyError = "Failed to delete runbook. Please check"
    #                             PsError = $PSItem.Exception}) > $null
    #                         }
    #                     }
    #                     catch {
    #                         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                         Step = 'Delete Runbook'
    #                         Status = 'Failed'
    #                         FriendlyError = "Couldn't locate and delete runbook. Please check"
    #                         PsError = $PSItem.Exception}) > $null
    
    #                         return $Validation, $resourcesdeleted
    #                     }
    #                 }
    #                 else {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate Runbook'
    #                     Status = 'Passed'
    #                     FriendlyError = "Adding this to a list of outstanding resources for now..."
    #                     PsError = ''}) > $null
    
    #                     $outstandingresources += $runbook.Name
    #                     return $Validation, $resourcesdeleted
    #                 }
    #             } elseif ($obj.ResourceType -eq 'Microsoft.Storage/storageAccounts') {
    #                 # checking to see if there are any containers, queues, etc. assoc. with the storage account
    #                 $storageAcc = Get-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name
    #                 $ctx = $storageAcc.Context
    #                 $containers = Get-AzStorageContainer -Context $ctx | where {$_.Name -notlike "*vhds*"}
    #                 $fileshares = Get-AzStorageShare -Context $ctx
    
    #                 if (($null -eq $containers) -and ($null -eq $fileshares))
    #                 {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate Storage Acct'
    #                     Status = 'Skipped'
    #                     FriendlyError = "This storage account is empty. Deleting now..."
    #                     PsError = ''}) > $null
    
    #                     try 
    #                     {
    #                         Remove-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name -Force
    #                         $checkstorageacct = Get-AzStorageAccount -ResourceGroupName $obj.ResourceGroupName -Name $obj.Name
    
    #                         if ($null -eq $checkstorageacct)
    #                         {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete Storage Acct'
    #                             Status = 'Passed'
    #                             FriendlyError = ""
    #                             PsError = ''}) > $null
    #                         } else {
    #                             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                             Step = 'Delete Storage Acct'
    #                             Status = 'Failed'
    #                             FriendlyError = "Failed to delete storage account. Please check"
    #                             PsError = $PSItem.Exception}) > $null
    #                         }
    #                     }
    #                     catch {
    #                         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                         Step = 'Delete Storage Acct'
    #                         Status = 'Failed'
    #                         FriendlyError = "Couldn't locate and delete storage account. Please check"
    #                         PsError = $PSItem.Exception}) > $null
    
    #                         return $Validation, $resourcesdeleted
    #                     }
    #                 }
    #                 else {
    #                     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                     Step = 'Locate Storage Acct'
    #                     Status = 'Passed'
    #                     FriendlyError = "Adding this to a list of outstanding resources for now..."
    #                     PsError = ''}) > $null
    
    #                     $outstandingresources += $storageAcc.StorageAccountName
    #                     return $Validation, $resourcesdeleted
    #                 }
    #             } else {
    #                 $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                 Step = 'Locate Storage Acct'
    #                 Status = 'Passed'
    #                 FriendlyError = "This resource does not match any of the rogue resource types and should be reviewed by the requestor to ensure safe deletion"
    #                 PsError = ''}) > $null
    
    #                 $outstandingresources += $obj.Name
    #                 return $Validation, $resourcesdeleted
    #             }
    #         }
    #     }
    # }
    # catch {
    #     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #     Step = 'Rogue Objects'
    #     Status = 'Failed'
    #     FriendlyError = "Could not pull any objects associated to the VM. Please check"
    #     PsError = $PSItem.Exception}) > $null

    #     return $Validation, $resourcesdeleted, $outstandingresources
    # }

    # try 
    # {
    #     Write-Host "Checking to see if RG still has resources in it"
    #     # check to see if RG is null - if it is, delete it
    #     $getRGresources = Get-AzResource -ResourceGroupName $VM.ResourceGroupName  

    #     if ($null -eq $getRGresources)
    #     {
    #         Remove-AzResourceGroup -Name $VM.ResourceGroupName -Force
    #         start-sleep -seconds 30

    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'Remove RG'
    #         Status = 'Passed'
    #         FriendlyError = ""
    #         PsError = ''}) > $null
    #     } else {
    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'Remove RG'
    #         Status = 'Skipped'
    #         FriendlyError = "Resource group $($VM.ResourceGroupName) still has resources, it won't be deleted"
    #         PsError = $PSItem.Exception}) > $null
    #     }
    # }
    # catch {
    #     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #     Step = 'Remove RG'
    #     Status = 'Failed'
    #     FriendlyError = "Failed to fetch resources in resource group $($VM.ResourceGroupName)"
    #     PsError = $PSItem.Exception}) > $null

    #     return $Validation
    # }
    # return the resources that were deleted and need a second look
    return $Validation, $resourcesdeleted, $remainingresources #$outstandingresources
}


# $Body = "Hello 'server_owner',`n`nAs we decommissioned your azure resource(s) detailed in 'ticket_number', `
# there were a few that came up as possibly still in use. Can you provide a 'yes' or 'no' regarding if these resources can be deleted? They look to be `
# housing a few security rules regarding the NSG, data still being stored in a runbook, etc.`n`n$($outstandingresources.Name)"

# Send-MailMessage -From 'cparker01@Textron.com' -To 'CloudOperations@Textron.com' -Subject 'Decom Outstanding Resources' -SmtpServer 'mrbbdc100.textron.com' `
#     -Body $Body