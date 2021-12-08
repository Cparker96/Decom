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
        Modified by     : 
        Date Modified   : 

#>
Function Scream-Test
{
    Param
    (
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM
    )

    [System.Collections.ArrayList]$Validation = @()
    $tag = @{Decom="Scream Test"}

    try
    {
        # first try and stop the machine and get the status
        Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
        $provisioningstate = $VM | Get-AzVM -Status

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
    
    try 
    {
        # then update the tags 
        Update-AzTag -ResourceId $VM.Id -Tag $tag -Operation Merge
        start-sleep -Seconds 5

        $checktags = Get-azTag -ResourceId $VM.Id
        start-sleep -Seconds 5

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
        # put a resource lock on the VM
        $newlock = New-AzResourceLock `
        -LockName 'SCREAM TEST' `
        -LockLevel ReadOnly `
        -Scope $VM.Id `
        -Force `
        -LockNotes 'This VM is under scream test. Contact CloudOperations@Textron.com for status'

        start-sleep -Seconds 5

        $lock = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $VM.Name -ResourceGroupName $VM.ResourceGroupName

        if ($null -ne $lock)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Lock Server'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Lock Server'
            Status = 'Failed'
            FriendlyError = "The VM $($VM.Name) could not be locked. Please check"
            PsError = ''}) > $null
        }      
    }
    catch 
    {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Lock Server'
        Status = 'Failed'
        FriendlyError = "The VM $($VM.Name) was could not be locked. Pleaser try again"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }
    return $Validation
}


