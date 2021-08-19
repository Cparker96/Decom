Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription
$sqllist = "kauiotsqlserver"
$targetsqlpaas = @()
$tag = @{Decom="Scream Test"}

foreach ($sub in $subs)
{
    Set-AzContext -Subscription $sub

    # get all sql paas in the list
    foreach ($sql in $sqllist)
    {
        $targetsqlpaas += Get-AzResource | where {$_.Name -eq $sql} | select Name, ResourceGroupName, Id, @{N='SubId';E={$_.Id.Substring(15, 36)}}
    }
}

foreach ($sqlpaas in $targetsqlpaas)
{
    # setting the context according to each sql paas
    $subId = $sqlpaas.SubId
    Get-AzSubscription -SubscriptionId $subId | Set-AzContext

    # get all db's associated                                                  # filter out the default master schemas and Basic tier db's - retention policy only allows for 7 days (need at least 14 for scream test)
    $databases = Get-AzSqlDatabase -ServerName $sqlpaas.Name -ResourceGroupName $sqlpaas.ResourceGroupName | where {($_.DatabaseName -ne 'master') -and ($_.SkuName -ne 'Basic')}

    foreach ($db in $databases)
    {
        # get the retention policies
        $retentionpolicies = Get-AzSqlDatabaseBackupShortTermRetentionPolicy -ResourceGroupName $db.ResourceGroupName -ServerName $db.ServerName -DatabaseName $db.DatabaseName

        foreach ($policy in $retentionpolicies)
        {
            if ($policy.RetentionDays -lt 14)
            {
                Write-Host "Updating retention policy for" $policy.DatabaseName -ForegroundColor Blue
                Set-AzSqlDatabaseBackupShortTermRetentionPolicy -RetentionDays 14 -ResourceGroupName $db.ResourceGroupName -ServerName $db.ServerName -DatabaseName $db.DatabaseName
            } elseif ($policy.RetentionDays -ge 14) {
                Write-Host "The retention policy for" $policy.DatabaseName "already meets the standard scream test requirements" -ForegroundColor Green
            }
        }

        # delete db's for scream test
        Write-Host "Now deleting" $db.DatabaseName -ForegroundColor Blue
        Remove-AzSqlDatabase -DatabaseName $db.DatabaseName -ResourceGroupName $db.ResourceGroupName -ServerName $db.ServerName -Force
    }

    # apply decom tag
    Write-Host "Adding decom tag to" $sqlpaas.Name -ForegroundColor Yellow
    Update-AzTag -ResourceId $sqlpaas.Id -Tag $tag -Operation Merge
}

