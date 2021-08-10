

function Remove-AzrVirtualMachine {
	<#
	.SYNOPSIS
		This function is used to remove any Azure VMs as well as any attached disks. By default, this function creates a job
		due to the time it takes to remove an Azure VM.

        Modified from https://github.com/adbertram/Random-PowerShell-Work/pull/26/commits/793e856db9353c76442751ef6ea134fabafd49bd
        with these changes https://github.com/adbertram/Random-PowerShell-Work/pull/26/commits/793e856db9353c76442751ef6ea134fabafd49bd
        Then I added snapshot cleanup logic
		
	.EXAMPLE
		PS> Get-AzVm -Name 'BAPP07GEN22' | Remove-AzrVirtualMachine
	
		This example removes the Azure VM BAPP07GEN22 as well as any disks attached to it.
		
	.PARAMETER VMName
		The name of an Azure VM. This has an alias of Name which can be used as pipeline input from the Get-AzureRmVM cmdlet.
	
	.PARAMETER ResourceGroupName
		The name of the resource group the Azure VM is a part of.
	
	.PARAMETER Wait
		If you'd rather wait for the Azure VM to be removed before returning control to the console, use this switch parameter.
		If not, it will create a job and return a PSJob back.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param
	(
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[ValidateNotNullOrEmpty()]
		[Alias('Name')]
		[string]$VMName,
		
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[ValidateNotNullOrEmpty()]
		[string]$ResourceGroupName,

		[Parameter()]
		[pscredential]$Credential,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[switch]$Wait
		
	)
    #$VMName = 'TXBRAMCOGCCD01'
    #$ResourceGroupName = 'SAP_Xtend'
    #$credential

	process {
		$scriptBlock = {
			param ($VMName,
				$ResourceGroupName)
			$commonParams = @{
				'Name'              = $VMName;
				'ResourceGroupName' = $ResourceGroupName
			}
			$vm = Get-AzVm @commonParams
				
			#region Remove the boot diagnostics disk
			if ($vm.DiagnosticsProfile.bootDiagnostics) {
				Write-Verbose -Message 'Removing boot diagnostics storage container...'
				$diagSa = [regex]::match($vm.DiagnosticsProfile.bootDiagnostics.storageUri, '^http[s]?://(.+?)\.').groups[1].value
				if ($vm.Name.Length -gt 9) {
					$i = 9
				} else {
					$i = $vm.Name.Length - 1
				}

				#region Get the VM ID
				$azResourceParams = @{
					'ResourceName'      = $VMName
					'ResourceType'      = 'Microsoft.Compute/virtualMachines'
					'ResourceGroupName' = $ResourceGroupName
				}
				$vmResource = Get-AzResource @azResourceParams
				$vmId = $vmResource.Properties.VmId
				#endregion
				$vmnameNoSpecialCharacters = $vm.name -replace '[^\p{L}\p{Nd}]', ''
				$diagContainerName = ('bootdiagnostics-{0}-{1}' -f $vmnameNoSpecialCharacters.ToLower().Substring(0, $i), $vmId)
				$diagSaRg = (Get-AzStorageAccount | where { $_.StorageAccountName -eq $diagSa }).ResourceGroupName
				$saParams = @{
					'ResourceGroupName' = $diagSaRg
					'Name'              = $diagSa
				}
				#get diagnostics containers associated with the exact VM ID	
				Get-AzStorageAccount @saParams | Get-AzStorageContainer | where { $_.Name-eq $diagContainerName } | Remove-AzStorageContainer -Force
                #remove the storage account if that is the only container in it
                if($null -eq (Get-AzStorageAccount @saParams | Get-AzStorageContainer)){
                    Get-AzStorageAccount @saParams | Remove-AzStorageAccount -Force
                }
            }
			#endregion
				
			Write-Verbose -Message 'Removing the Azure VM...'
            #Unlock VM
            get-azresourcelock | where {($_.name -eq 'Decom') -and ($_.resourceName -eq $VM.name)} | Remove-AzResourceLock -force

			$null = $vm | Remove-AzVM -Force
			Write-Verbose -Message 'Removing the Azure network interface...'
			foreach($nicUri in $vm.NetworkProfile.NetworkInterfaces.Id) {
				$nic = Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName -Name $nicUri.Split('/')[-1]
				Remove-AzNetworkInterface -Name $nic.Name -ResourceGroupName $vm.ResourceGroupName -Force
				foreach($ipConfig in $nic.IpConfigurations) {
					if($null -ne $ipConfig.PublicIpAddress) {
						Write-Verbose -Message 'Removing the Public IP Address...'
						Remove-AzPublicIpAddress -ResourceGroupName $vm.ResourceGroupName -Name $ipConfig.PublicIpAddress.Id.Split('/')[-1] -Force
					} 
				}
			} 

				
			## Remove the OS disk
			Write-Verbose -Message 'Removing OS disk...'
			if ('Uri' -in $vm.StorageProfile.OSDisk.Vhd) {
				## Not managed
				$osDiskId = $vm.StorageProfile.OSDisk.Vhd.Uri
				$osDiskContainerName = $osDiskId.Split('/')[-2]

				## TODO: Does not account for resouce group 
				$osDiskStorageAcct = Get-AzStorageAccount | where { $_.StorageAccountName -eq $osDiskId.Split('/')[2].Split('.')[0] }
				$osDiskStorageAcct | Remove-AzStorageBlob -Container $osDiskContainerName -Blob $osDiskId.Split('/')[-1]

				#region Remove the status blob
				Write-Verbose -Message 'Removing the OS disk status blob...'
				$osDiskStorageAcct | Get-AzStorageBlob -Container $osDiskContainerName -Blob "$($vm.Name)*.status" | Remove-AzStorageBlob
				#endregion
			} else {
				## managed
				Get-AzDisk | where { $_.ManagedBy -eq $vm.Id } | Remove-AzDisk -Force
                Get-AzDisk | Where-Object { $_.id -eq $vm.StorageProfile.OsDisk.ManagedDisk.Id } | Remove-AzDisk -Force

                #remove Snapshots
                foreach($snapshot in Get-AzSnapshot -ResourceGroupName $vm.ResourceGroupName){
                    #if the snapshot was created by the os disk
                    if(($snapshot.CreationData.SourceResourceId -eq $vm.StorageProfile.OsDisk.ManagedDisk.Id) -or
                    ([regex]::match($vm.StorageProfile.OsDisk.Name, '(.*_OsDisk_\d_)').groups[1].value -eq 
                    [regex]::match($snapshot.name, '(.*_OsDisk_\d_)').groups[1].value)){
                        remove-azsnapshot -SnapshotName $snapshot.name -Resourcegroupname $vm.resourcegroupname -Force
                    }
                } 
			}
			
			## Remove any other attached disks
			if ('DataDiskNames' -in $vm.PSObject.Properties.Name -and @($vm.DataDiskNames).Count -gt 0) {
				Write-Verbose -Message 'Removing data disks...'
				foreach ($uri in $vm.StorageProfile.DataDisks.Vhd.Uri) {
					$dataDiskStorageAcct = Get-AzStorageAccount -Name $uri.Split('/')[2].Split('.')[0]
					$dataDiskStorageAcct | Remove-AzStorageBlob -Container $uri.Split('/')[-2] -Blob $uri.Split('/')[-1]
				}
			}
            else{
                foreach($disk in $vm.StorageProfile.DataDisks.name)
                {
                    #remove Data disk
                    Remove-AzDisk -DiskName $disk -ResourceGroupName $vm.ResourceGroupName -force
                    #remove Snapshots
                    Get-AzSnapshot -ResourceGroupName $vm.ResourceGroupName | where name -like "$disk*" | Remove-AzSnapshot -Force
                }
            }
		}
			
		if ($Wait.IsPresent) {
			& $scriptBlock -VMName $VMName -ResourceGroupName $ResourceGroupName
		} else {
			#$initScript = {$null = Login-AzAccount -Credential $Credential}
			$jobParams = @{
				'ScriptBlock'          = $scriptBlock
				'InitializationScript' = $initScript
				'ArgumentList'         = @($VMName, $ResourceGroupName)
				'Name'                 = "Azure VM $VMName Removal"
			}
			Start-Job @jobParams 
		}
	}
}
