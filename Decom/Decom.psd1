@{
RootModule = 'Decom.psm1'
ModuleVersion = '1.2'
Author = 'your_author'
CompanyName = 'your_company'
RequiredModules = @("az", @{ModuleName = "az"; ModuleVersion= "5.5.0"}; "ActiveDirectory", @{ModuleName = "ActiveDirectory"; ModuleVersion= "1.0.1.0"}; "dbatools", @{ModuleName = "dbatools"; ModuleVersion = "1.0.153"})
Description = "your_description"
PowerShellVersion = '7.1.2'
DotNetFrameworkVersion = '4.0'
CLRVersion = '4.0'
AliasesToExport = @()
FunctionsToExport = @('Scream_Test', 'Delete-VM', 'Remove-ActiveDirectoryObject', 'UnlinkVM-Tenable')
}

