Connect-AzAccount -Environment AzureCloud

# setting variables
$subs = Get-AzSubscription 
$vmlist = "testdecomvm"
$targetvms = @()
$outstandingresources = $null

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

    #Remove-AzResourceLock -LockName 'SCREAM TEST' -Scope $targetvm.Id -Force

    try 
    {
    #Deleting VM and resources associated
    Remove-AzrVirtualMachine -Name $targetvm.Name -ResourceGroupName $targetvm.ResourceGroupName

    # set a sleep timer for it to delete all the associated resources, Azure takes time - BE PATIENT
    Start-Sleep -Seconds 300

    # first check to see if there are any rogue objects assoc. to the VM
    $rogueobj = Get-AzResource | where-object {$_.Name -match $targetvm.Name}

    if ($null -eq $rogueobj)
    {
        Write-Host "There are no outstanding resources to be deleted." -ForegroundColor Green
    } else {
        # if not null, evaulate resource type of each, perform logic based on type
        foreach ($obj in $rogueobj)
        {
            if ($obj.ResourceType = 'Microsoft.Network/networkSecurityGroups')
            {
                $nsg = Get-AzNetworkSecurityGroup -Name $obj.Name
                # The "!" executes the same is $null, except $null is mainly used to check vars, not properties
                if ((!$nsg.SecurityRules) -and (!$nsg.NetworkInterfaces) -and (!$nsg.Subnets))
                {
                    Write-Host "This NSG isn't associated to any NICs, Vnets, etc. Deleting now..." -ForegroundColor Yellow
                    Remove-AzResource -ResourceId $nsg.Id -Force
                }
                else {
                    Write-Host "Adding this to a list of outstanding resources for now..." -ForegroundColor Yellow
                    $outstandingresources += $nsg
                }
            }
            elseif ($obj.ResourceType = 'Microsoft.Automation/automationAccounts/runbooks') {

                $runbook = Get-AzAutomationRunbook -Name $obj.Name -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName

                $webhooks = Get-AzAutomationWebhook -RunbookName $obj.RunbookName -ResourceGroupName $obj.ResourceGroupName -AutomationAccountName $obj.AutomationAccountName

                # check to see if there are no jobs or webhooks assoc. to the runbook
                if (($runbook.JobCount -eq 0) -and ($null -eq $webhooks))
                {
                    Write-Host "This runbook has no jobs or webhooks associated with it. Deleting now..." -ForegroundColor Yellow
                    Remove-AzAutomationRunbook -Name $obj.Name -Force
                }
                else {
                    Write-Host "Adding this to a list of outstanding resources for now..." -ForegroundColor Yellow
                    $outstandingresources += $runbook
                }
            }
        }
        # print var for visibility
        $outstandingresources
        }
    }
    catch {
        return $error[0].exception
    }
}

# $Body = "Hello 'server_owner',`n`nAs we decommissioned your azure resource(s) detailed in 'ticket_number', `
# there were a few that came up as possibly still in use. Can you provide a 'yes' or 'no' regarding if these resources can be deleted? They look to be `
# housing a few security rules regarding the NSG, data still being stored in a runbook, etc.`n`n$($outstandingresources.Name)"

# Send-MailMessage -From 'cparker01@Textron.com' -To 'CloudOperations@Textron.com' -Subject 'Decom Outstanding Resources' -SmtpServer 'mrbbdc100.textron.com' `
#     -Body $Body