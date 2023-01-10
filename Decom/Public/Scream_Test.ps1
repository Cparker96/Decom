<#
    .SYNOPSIS
        Perform a scream test of a VM
    .DESCRIPTION
        This function performs a scream test of a VM
    .PARAMETER Environment
        The $VmObj variable which pulls in metadata from the server 
    .EXAMPLE

    .NOTES
        FunctionName    : Scream-Test
        Created by      : Cody Parker
        Date Coded      : 11/9/2021
        Modified by     : ...
        Date Modified   : ...

#>
Function Scream_Test
{
    Param
    (
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        [parameter(Position = 0, Mandatory=$true)] $VmRF
    )

    [System.Collections.ArrayList]$Validation = @() 
    $tag = @{Decom="Scream Test - $($VmRF.Change_Number)"}

    # check to see if the VM is a domain controller first
    if ($VmRF.Hostname -like "*IDC*") 
    {
        Write-Error "Removing lock because its a domain controller"
        # remove the lock on the IDC
        Remove-AzResourceLock -ResourceName $VM.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Force > $null
        start-sleep -Seconds 30
    }

    try 
    {
        Write-host "Updating the tags"
        # update the tags 
        Update-AzTag -ResourceId $VM.Id -Tag $tag -Operation Merge
        start-sleep -Seconds 30

        $checktags = Get-azTag -ResourceId $VM.Id
        start-sleep -Seconds 30

        if ($checktags.Properties.TagsProperty.Keys.Contains('Decom'))
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Tag Server'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Tag Server'
            Status = 'Failed'
            FriendlyError = "The VM $($VM.Name) did not get tagged with a decom tag"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Tag Server'
        Status = 'Failed'
        FriendlyError = "The VM $($VM.Name) was could not be tagged for decom"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }

    try
    {
        Write-Host "Stopping the VM"
        # stop the machine and get the status
        Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
        $provisioningstate = $VM | Get-AzVM -Status

        Start-sleep -Seconds 30

        if ($provisioningstate.Statuses[1].DisplayStatus -ne 'VM deallocated')
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Stop Server'
            Status = 'Failed'
            FriendlyError = "The VM $($VM.Name) did not stop correctly. Please try again"
            PsError = $PSItem.Exception}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Stop Server'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Stop Server'
        Status = 'Failed'
        FriendlyError = "The VM $($VM.Name) was could not be stopped"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }

    Start-sleep -Seconds 30

    try 
    {
        Write-Host "Putting a decom lock on the VM"
        # put a resource lock on the VM
        $newlock = New-AzResourceLock `
        -LockName 'SCREAM TEST' `
        -LockLevel ReadOnly `
        -Scope $VM.Id `
        -Force `
        -LockNotes "This VM is under scream test from change $($VmRF.Change_Number). Contact 'your_email' for status"
    
        start-sleep -Seconds 30
    
        $lock = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $VM.Name -ResourceGroupName $VM.ResourceGroupName
    
        if ($null -eq $lock)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Lock Server'
            Status = 'Failed'
            FriendlyError = "The lock could not be applied for $($VM.Name)"
            PsError = $PSItem.Exception}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Lock Server'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        }
    } catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Lock Server'
        Status = 'Failed'
        FriendlyError = "The lock could not be applied for $($VM.Name). Please try again"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }
    return $Validation, $lock
}