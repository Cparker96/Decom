<#
    .SYNOPSIS
        Takes the object out of Active Directory
    .DESCRIPTION
        This function authenticates to Textron AD and deletes the object
    .PARAMETER Environment
        The $VmObj variable which pulls in metadata from the server 
    .EXAMPLE

    .NOTES
        FunctionName    : Remove-ActiveDirectoryObject
        Created by      : Cody Parker
        Date Coded      : 11/9/2021
        Modified by     : 
        Date Modified   : 

#>
Function Remove-ActiveDirectoryObject
{
    Param
    (
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        [parameter(Position = 0, Mandatory=$true)] [System.Management.Automation.PSCredential] $cred,
        [Parameter(Mandatory=$true)][ValidateNotNull()][string] $credssp_RSAT_host
    )

    [System.Collections.ArrayList]$Validation = @()

    try 
    {
        $wsman = Enable-WSManCredSSP -Role Client -DelegateComputer $credssp_RSAT_host -Force
        $SessionId = New-PSSession -ComputerName $credssp_RSAT_host -Credential $cred -Authentication Credssp
    }
    catch {
        
    }

    # try 
    # {
    #     # find the object if it exists in AD
    #     $search = Get-ADComputer -Identity $VM.Name -ErrorAction SilentlyContinue

    #     if ($null -eq $search)
    #     {
    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'AD Object Search'
    #         Status = 'Skipped'
    #         FriendlyError = "The VM $($VM.Name) couldn't be found in AD, or has already been taken out"
    #         PsError = ''}) > $null

    #         break
    #     } else {
    #         $Validation.Add([PSCustomObject]@{System = 'Server' 
    #         Step = 'AD Object Search'
    #         Status = 'Passed'
    #         FriendlyError = ""
    #         PsError = ''}) > $null

    #         try 
    #         {
    #             # delete the object
    #             $deletedobject = -Identity $VM.Name | Remove-ADObject -Credential $adcred -Confirm:$false -Recursive 
        
    #             if ($null -eq $deletedobject)
    #             {
    #                 $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                 Step = 'AD Object Delete'
    #                 Status = 'Passed'
    #                 FriendlyError = ""
    #                 PsError = ''}) > $null
                
    #             } else {
    #                 $Validation.Add([PSCustomObject]@{System = 'Server' 
    #                 Step = 'AD Object Delete'
    #                 Status = 'Failed'
    #                 FriendlyError = "There seems to be an issue with this object. Please go troubleshoot"
    #                 PsError = $PSItem.Exception}) > $null
    #             }
    #         }
    #         catch {
    #             $Validation.Add([PSCustomObject]@{System = 'Server' 
    #             Step = 'AD Object Delete'
    #             Status = 'Failed'
    #             FriendlyError = "Couldn't authenticate to AD. Please try again"
    #             PsError = $PSItem.Exception}) > $null
        
    #             return $Validation
    #         }
    #     }   
    # }
    # catch {
    #     $Validation.Add([PSCustomObject]@{System = 'Server' 
    #     Step = 'AD Object Search'
    #     Status = 'Failed'
    #     FriendlyError = "Couldn't authenticate to AD. Please try again"
    #     PsError = $PSItem.Exception}) > $null

    #     return $Validation
    # }
}
