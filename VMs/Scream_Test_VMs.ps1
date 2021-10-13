Connect-AzAccount -Environment AzureUSGovernment

# setting variables
$subs = Get-AzSubscription 
$vmlist = "TXSAPPBLT053V", "TXSAPPBLT057V"
$targetvms = @()
$tag = @{Decom="Scream Test"}

foreach ($sub in $subs)
{
    Set-AzContext -Subscription $sub

    foreach ($vm in $vmlist)
    {
        #getting all vms in the vmlist while looping through subs and getting properties
        if ($null -ne (Get-AzVM -Name $vm))
        {
            # I just need the vms and their Names, RG, and subId for later
            $targetvms += Get-AzVM -Name $vm | select Name, ResourceGroupName, Id, @{N='SubId';E={$_.Id.Substring(15, 36)}}
        }
    }
}

foreach ($targetvm in $targetvms)
{
    #setting context according to each vm that was pulled then doing stuff on it
    $subId = $targetvm.SubId
    Get-AzSubscription -SubscriptionId $subId | Set-AzContext

    Stop-AzVM -Name $targetvm.Name -ResourceGroupName $targetvm.ResourceGroupName -Force
    
    $provisioningstate = $targetvm | Get-AzVM -Status 
    
    Update-AzTag -ResourceId $targetvm.Id -Tag $tag -Operation Merge
    
    #if no resource lock exists on the resource, create a new lock
    if ($null -eq (Get-AzResourceLock -ResourceName $targetvm.Name -ResourceGroupName $targetvm.ResourceGroupName -ResourceType "Microsoft.Compute/VirtualMachines"))
    {
        $newlock = New-AzResourceLock `
        -LockName 'SCREAM TEST' `
        -LockLevel ReadOnly `
        -Scope $targetvm.Id `
        -Force `
        -LockNotes 'This VM is under scream test. Contact CloudOperations@Textron.com for status'
    }
    
    $lock = get-azresourcelock -ResourceType "Microsoft.Compute/VirtualMachines" -ResourceName $targetvm.Name -ResourceGroupName $targetvm.ResourceGroupName
    
    # checking to see if the lock wasn't established, the VM is not stopped, or was not tagged with Decom tag
    if (($null -eq $lock) -and !($targetvm.Tags.ContainsKey('Decom')) -and ($provisioningstate.Statuses[1].DisplayStatus -ne 'VM deallocated'))
    {
        Write-Host "The VM" $targetvm.Name "is not stopped, does not a have a Decom tag, or does not have a lock" -ForegroundColor Green
    } else {
        Write-Host "Scream test initiated" -ForegroundColor Green
    }
}

