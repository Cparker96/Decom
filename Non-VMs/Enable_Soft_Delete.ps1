Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription 
$storacclist = "testingstorageaccount3"
$targetstoraccs = @()

foreach ($sub in $subs)
{
    Set-AzContext -Subscription $sub

    foreach ($sa in $storacclist)
    {
        # getting all storage accts that are listed in the var
        $targetstoraccs += Get-AzStorageAccount | where StorageAccountName -eq $sa | select StorageAccountName, ResourceGroupName, Id, @{N='SubId';E={$_.Id.Substring(15, 36)}}, EnableHierarchicalNamespace
    }
}

foreach ($targetstoracct in $targetstoraccs)
{
    # setting the context according to each storaget acct
    $subId = $targetstoracct.SubId
    Get-AzSubscription -SubscriptionId $subId | Set-AzContext

    # check to see if Hierarchical namespace property is enabled - if it is, then soft delete will not work...for now
    if ($targetstoracct.EnableHierarchicalNamespace -eq $true)
    {
        Write-Host $targetstoracct.StorageAccountName "can't have soft delete enabled - Hier. Namespace property is True" -ForegroundColor Yellow
        continue 
    }

    # check to see if soft delete is already enabled
    $checkproperties =  Get-AzStorageBlobServiceProperty -ResourceGroupName $targetstoracct.ResourceGroupName -StorageAccountName $targetstoracct.StorageAccountName

    if ($checkproperties.DeleteRetentionPolicy.Enabled -eq $true)
    {
        Write-Host $targetstoracct.StorageAccountName "already has soft delete enabled. Moving to the next one..." -ForegroundColor Yellow
        continue
    } else {
        Enable-AzStorageBlobDeleteRetentionPolicy -ResourceGroupName $targetstoracct.ResourceGroupName -StorageAccountName $targetstoracct.StorageAccountName -RetentionDays 14

        # check to see if soft delete was applied
        $properties = Get-AzStorageBlobServiceProperty -ResourceGroupName $targetstoracct.ResourceGroupName -StorageAccountName $targetstoracct.StorageAccountName
    
        if ($properties.DeleteRetentionPolicy.Enabled -eq $true)
        {
            Write-Host $targetstoracct.StorageAccountName "was enabled for soft delete" -ForegroundColor Green
        } else {
            Write-Host $targetstoracct.StorageAccountName "was not enabled for soft delete. Please try again" -ErrorAction Stop -ForegroundColor Red
        }
    }
}



