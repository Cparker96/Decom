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
        Modified by     : ...
        Date Modified   : ...

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

    try 
    {
        Write-Host "Removing all resource locks"
        $locks = Get-AzResourceLock -ResourceName $VM.Name -ResourceType 'Microsoft.Compute/virtualMachines' -ResourceGroupName $VM.ResourceGroupName

        foreach ($lock in $locks)
        {
            # removing the locks
            Remove-AzResourceLock -LockName $lock.Name -Scope $VM.Id -Force > $null
            start-sleep -Seconds 60
        }

        $retrievelocks = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $VM.Name -ResourceGroupName $VM.ResourceGroupName

        if ($retrievelocks.count -eq 0)
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
            FriendlyError = "There seem to be resource locks still outstanding on $($VM.Name)"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Delete Lock'
        Status = 'Failed'
        FriendlyError = "Could not retrieve and delete resource locks for $($VM.Name)"
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
        # Deleting associated resources
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
        if ($VM.Name -like "*DBS*")
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
    $checkrgresources = Get-AzResource -ResourceGroupName $VM.ResourceGroupName

    if ($checkrgresources.Count -eq 0)
    {
        try {
            Write-Host "Deleting RG $($VM.ResourceGroupName) since nothing is in it"
            $deleterg = Remove-AzResourceGroup -Name $VM.ResourceGroupName -Force > $null
            start-sleep -Seconds 60
        }
        catch {
            $PSItem.Exception
        }  
    }

    return $Validation, $resourcesdeleted, $remainingresources
}