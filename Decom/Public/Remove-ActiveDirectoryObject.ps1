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
        [parameter(Position = 0, Mandatory=$true)] [System.Management.Automation.PSCredential] $cred
    )

    [System.Collections.ArrayList]$Validation = @()

    try 
    {
        # check that ADUC is installed
        Import-Module ActiveDirectory
        start-sleep -seconds 10

        $checkmodule = Get-Module ActiveDirectory

        if ($checkmodule.Name -eq 'ActiveDirectory')
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Import AD'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null

            try 
            {
                Write-Host "Searching for the object in AD"
                # search for the object in AD
                $search = Get-ADComputer -Identity $VM.Name -ErrorAction SilentlyContinue 

                if ($null -eq $search)
                {
                    $Validation.Add([PSCustomObject]@{System = 'Server' 
                    Step = 'AD Object Search'
                    Status = 'Skipped'
                    FriendlyError = "This object either doesn't exist, or someone has already deleted it"
                    PsError = ''}) > $null
                } else {
                    $Validation.Add([PSCustomObject]@{System = 'Server' 
                    Step = 'AD Object Search'
                    Status = 'Passed'
                    FriendlyError = "Found object. Removing..."
                    PsError = ''}) > $null
                    
                    try 
                    {
                        Write-Host "Deleting the object in AD"
                        # delete the object
                        $deleteobject = Get-ADComputer -Identity $VM.Name | Remove-ADObject -Credential $cred -Confirm:$false -IncludeDeletedObjects -Recursive

                        if ($null -eq $deleteobject)
                        {
                            $Validation.Add([PSCustomObject]@{System = 'Server' 
                            Step = 'AD Object Delete'
                            Status = 'Passed'
                            FriendlyError = ""
                            PsError = ''}) > $null
                        } else {
                            $Validation.Add([PSCustomObject]@{System = 'Server' 
                            Step = 'AD Object Search'
                            Status = 'Failed'
                            FriendlyError = "Failed to delete AD object"
                            PsError = $PSItem.Exception}) > $null
                        }
                    }
                    catch {
                        $Validation.Add([PSCustomObject]@{System = 'Server' 
                        Step = 'AD Object Delete'
                        Status = 'Failed'
                        FriendlyError = "Could not delete AD object that was found"
                        PsError = $PSItem.Exception}) > $null

                        return $Validation
                    }
                    
                    try 
                    {
                        # validate object is gone
                        $reviewsearch = Get-ADComputer -Identity $VM.Name 
                    }
                    catch {
                        $PSItem.Exception
                    }
                }
            }
            catch {
                $Validation.Add([PSCustomObject]@{System = 'Server' 
                Step = 'AD Object Search'
                Status = 'Failed'
                FriendlyError = "Failed to search for AD object"
                PsError = ''}) > $null 

                return $Validation
            }
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Import AD'
            Status = 'Failed'
            FriendlyError = "Failed to import AD"
            PsError = $PSItem.Exception}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Import AD'
        Status = 'Failed'
        FriendlyError = "Failed to import module Active Directory. Please check"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }
    return $Validation, $reviewsearch
}
