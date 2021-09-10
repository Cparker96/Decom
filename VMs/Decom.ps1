Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription 
$vmlist = "TXAAPPAZU845"
$targetvms = @()

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
    Set-AzContext -SubscriptionId $targetvm.SubId

    Remove-AzResourceLock -LockName 'SCREAM TEST' -Scope $targetvm.Id -Force

    #Deleting VM and resources associated
    Remove-AzrVirtualMachine -Name $targetvm.Name -ResourceGroupName $targetvm.ResourceGroupName

    # set a sleep timer for it to delete all the associated resources, it takes time BE PATIENT
    Start-Sleep -Seconds 60

    $rogueobj = Get-AzResource | where-object {$_.Name -match $targetvm.Name}
    
    #checking to see if any associated resources weren't deleted
    if (!($rogueobj))
    {
        Write-Host "There are still pending associated resource(s) that need to be deleted" -ForegroundColor Red
    }
   Write-Host "Success" -ForegroundColor Green
}

