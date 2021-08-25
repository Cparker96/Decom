Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription 
$sqlpaas = "kauiotsqlserver"
$targetsqlpaas = @()

foreach ($sub in $subs)
{
    Set-AzContext -Subscription $sub

    foreach ($sql in $sqlpaas)
    {
        # getting all sql paas resources listed in the var
        $targetsqlpaas += Get-AzResource | where {$_.Name -eq $sql} | select Name, ResourceGroupName, Id, @{N='SubId';E={$_.Id.Substring(15, 36)}}, Tags
    }
}

foreach ($sqlpaas in $targetsqlpaas)
{
    # setting the context according to each sql paas
    $subId = $sqlpaas.SubId
    Get-AzSubscription -SubscriptionId $subId | Set-AzContext

    $activedatabases = Get-AzSqlDatabase -ResourceGroupName $sqlpaas.ResourceGroupName -ServerName $sqlpaas.Name | where {$_.DatabaseName -ne 'master'}

    if ($sqlpaas.Tags.ContainsKey('Decom') -and ($null -eq $activedatabases))
    {
        Write-Host "Deleting sql paas resource - " $sqlpaas.Name -ForegroundColor Green
        Remove-AzResource -ResourceId $sqlpaas.Id -Force
    } else {
        Write-Host "Resource cannot be deleted because it still contains a Decom tag or active database" -ForegroundColor Red
    }
}
