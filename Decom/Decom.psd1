@{
RootModule = 'Decom.psm1'
ModuleVersion = '1.2'
Author = 'Cody Parker'
CompanyName = 'Textron Inc.'
RequiredModules = @("az", @{ModuleName = "az"; ModuleVersion= "5.5.0"}; "ActiveDirectory", @{ModuleName = "ActiveDirectory"; ModuleVersion= "1.0.1.0"})
Description = "A module for Textron decommissioning of resources"
PowerShellVersion = '7.1.2'
DotNetFrameworkVersion = '4.0'
CLRVersion = '4.0'
AliasesToExport = @()
FunctionsToExport = @('Scream-Test', 'Remove-tazVirtualMachine', 'Delete-VM', 'Remove-ActiveDirectoryObject', 'UnlinkVM-Tenable')
}

