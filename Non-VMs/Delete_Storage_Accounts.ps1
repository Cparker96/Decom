Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription 
$storacclist = "kauiotfunctionp94e2", "kauiothydrastoragedev", "kauiothydrastorageprod", "kauiotstoragequeuedev", "storageaccountkauteaf68", "kauiotblobstorage", "kauiotblobprod"
$targetstoraccs = @()

# delete storage accounts after soft delete time frame is complete
foreach ($sub in $subs)
{
    Set-AzContext -Subscription $sub

    foreach ($sa in $storacclist)
    {
        # getting all storage accts that are listed in the var
        $targetstoraccs += Get-AzStorageAccount | where StorageAccountName -eq $sa | select StorageAccountName, ResourceGroupName, Id, @{N='SubId';E={$_.Id.Substring(15, 36)}}
    }
}

foreach ($targetstoracct in $targetstoraccs)
{
    # setting the context according to each storaget acct
    $subId = $targetstoracct.SubId
    Get-AzSubscription -SubscriptionId $subId | Set-AzContext

    # check to make sure that soft delete timeframe is up
    $validationproperties = Get-AzStorageBlobServiceProperty -ResourceGroupName $targetstoracct.ResourceGroupName -StorageAccountName $targetstoracct.StorageAccountName

    # remove the resource lock
    Remove-AzResourceLock -LockName 'DO NOT DELETE' -Scope $targetstoracct.Id -Force

    if ($validationproperties.DeleteRetentionPolicy.Enabled -eq $true)
    {
        Remove-AzStorageAccount -ResourceGroupName $targetstoracct.ResourceGroupName -Name $targetstoracct.StorageAccountName -Force
        Write-Host "Storage account was deleted" -ForegroundColor Green
    }
}

### This is to find all Storage Accounts that have the Hierarchical Namespace property set to 'True'
# $namespaceTrue = [System.Collections.ArrayList]@()
# foreach ($sub in $subs)
# {
#     Set-AzContext -Subscription $sub
#     $namespaceTrue += Get-AzStorageAccount | select StorageAccountName, ResourceGroupName, EnableHierarchicalNamespace | where {$_.EnableHierarchicalNamespace -eq $true}
# }