<#
    .SYNOPSIS
        Unlinks the VM object from Tenable
    .DESCRIPTION
        This function unlinks the VM object from Tenable
    .PARAMETER Environment
        The $VmObj variable which pulls in metadata from the server 
    .EXAMPLE

    .NOTES
        FunctionName    : UnlinkVM-Tenable
        Created by      : Cody Parker
        Date Coded      : 11/9/2021
        Modified by     : 
        Date Modified   : 

#>
Function UnlinkVM-Tenable
{
    Param
    (
        [parameter(Position = 0, Mandatory=$true)] [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        [parameter(Position = 1, Mandatory=$true)] [String] $TenableAccessKey,
        [parameter(Position = 2, Mandatory=$true)] [String] $TenableSecretKey
    )
    [System.Collections.ArrayList]$Validation = @()
    try 
    {
        # gets the agent's info
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $resource = "https://cloud.tenable.com/scanners/null/agents?offset=0&limit=50&sort=name:asc&wf=core_version,distro,groups,ip,name,platform,status&w=$($VM.Name)"
        $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
        $agent = (Invoke-RestMethod -Uri $resource -Method Get -Headers $headers).agents 
        
        # run through a couple checks just to see what comes up
        if (($null -eq $agent) -or ($agent.count -eq 0))
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Identify Tenable Object'
            Status = 'Skipped'
            FriendlyError = "This agent has either been unlinked, or someone else has deleted it"
            PsError = $PSItem.Exception}) > $null

            break
        } elseif ($agent.count -gt 1) {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Identify Tenable Object'
            Status = 'Failed'
            FriendlyError = "Multiple agents were found with this server name. Please go troubleshoot"
            PsError = $PSItem.Exception}) > $null
        } else {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Identify Tenable Object'
            Status = 'Passed'
            FriendlyError = "Agent found. Unlinking..."
            PsError = ''}) > $null

            try 
            {
                # then get the ID to for the endpoint
                $agentid = $agent.id
        
                #unlink the agent
                $headers = $null
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $targetagent = "https://cloud.tenable.com/scanners/1/agents/$($agentid)"
                $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
                $unlink = Invoke-WebRequest -Uri $targetagent -Method Delete -Headers $headers
        
                if ($unlink.StatusCode -ne 200)
                {
                    $Validation.Add([PSCustomObject]@{System = 'Server' 
                    Step = 'Tenable Unlink'
                    Status = 'Failed'
                    FriendlyError = "Agent was not unlinked. Please try again"
                    PsError = $PSItem.Exception}) > $null
                } elseif ($unlink.StatusCode -eq 200) {
                    $Validation.Add([PSCustomObject]@{System = 'Server' 
                    Step = 'Tenable Unlink'
                    Status = 'Passed'
                    FriendlyError = ""
                    PsError = ''}) > $null

                    return $Validation, $unlink
                } 

                # try 
                # {
                #     # check agent status
                #     $headers = $null
                #     $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                #     $resource = "https://cloud.tenable.com/scanners/null/agents?offset=0&limit=50&sort=name:asc&wf=core_version,distro,groups,ip,name,platform,status&w=$($VM.Name)"
                #     $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
                #     $checkagent = (Invoke-WebRequest -Uri $resource -Method Get -Headers $headers).agents     
                # }
                # catch {
                #     $PSItem.Exception
                # }
            }
            catch {
                $Validation.Add([PSCustomObject]@{System = 'Server' 
                Step = 'Tenable Unlink'
                Status = 'Failed'
                FriendlyError = "Couldn't authenticate with Tenable. Please try again"
                PsError = $PSItem.Exception}) > $null
        
                return $Validation
            }
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Identify Tenable Object'
        Status = 'Failed'
        FriendlyError = "Couldn't authenticate with Tenable. Please try again"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }
    
    return $Validation, $unlink
}




### STUFF THAT I DON'T NEED TO USE RIGHT NOW BUT IS HELPFUL ####


# lists the scanner details
# $headers = $null
# $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
# $resource = 'https://cloud.tenable.com/scanners/'
# $headers.Add("X-ApiKeys", 'accessKey=70e9fff3f75648e6c891510c1807390c9e6f78c7f7d945979731d0c903eaccfd; secretKey=32922c758c81ad3323c44bdf8596221d48efb692f0f8ca374944223b7f77f269')
# $response1 = Invoke-RestMethod -Uri $resource -Method Get -Headers $headers

# lists the agent groups per scanner
# $headers = $null
# $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
# $resource = 'https://cloud.tenable.com/scanners/1/agent-groups'
# $headers.Add("X-ApiKeys", 'accessKey=70e9fff3f75648e6c891510c1807390c9e6f78c7f7d945979731d0c903eaccfd; secretKey=32922c758c81ad3323c44bdf8596221d48efb692f0f8ca374944223b7f77f269')
# $response2 = Invoke-RestMethod -Uri $resource -Method Get -Headers $headers

# lists my user details
# $headers = $null
# $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
# $resource = 'https://cloud.tenable.com/users'
# $headers.Add("X-ApiKeys", 'accessKey=70e9fff3f75648e6c891510c1807390c9e6f78c7f7d945979731d0c903eaccfd; secretKey=32922c758c81ad3323c44bdf8596221d48efb692f0f8ca374944223b7f77f269')
# $response2 = Invoke-RestMethod -Uri $resource -Method Get -Headers $headers