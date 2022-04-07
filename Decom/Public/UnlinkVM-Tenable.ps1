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

    # first I want to test and make sure the connection is good - using 902 as the test
    try {
        Write-Host "Testing Tenable connection"
        # gets the agent's info
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $resource = "https://cloud.tenable.com/scanners/null/agents?offset=0&limit=50&sort=name:asc&wf=core_version,distro,groups,ip,name,platform,status&w=TXAINFAZU902"
        $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
        $testconnectionagent = (Invoke-RestMethod -Uri $resource -Method Get -Headers $headers).agents 

        if ($null -ne $testconnectionagent)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Tenable Connection'
            Status = 'Passed'
            FriendlyError = ""
            PsError = ''}) > $null
        }
    }
    catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Tenable Connection'
        Status = 'Failed'
        FriendlyError = "Failed to establish Tenable connection. Please check your keys"
        PsError = $PSItem.Exception}) > $null

        return $Validation
    }

    try 
    { 
        Write-Host "Pulling Tenable agent info"
        # gets the agent's info
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $resource = "https://cloud.tenable.com/scanners/null/agents?offset=0&limit=50&sort=name:asc&wf=core_version,distro,groups,ip,name,platform,status&w=$($VM.Name)"
        $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
        $agent = Invoke-RestMethod -Uri $resource -Method Get -Headers $headers

        if ($agent.pagination.total -eq 0)
        {
            $Validation.Add([PSCustomObject]@{System = 'Server' 
            Step = 'Identify Tenable Object'
            Status = 'Skipped'
            FriendlyError = "This agent has either been unlinked or someone else has deleted it"
            PsError = ''}) > $null
        }
    } catch {
        $Validation.Add([PSCustomObject]@{System = 'Server' 
        Step = 'Identify Tenable Object'
        Status = 'Failed'
        FriendlyError = "Failed to find agent in Tenable. Please check"
        PsError = $PSItem.Exception}) > $null

        return $validation
    }

    if ($agent.pagination.total -ne 0)
    {
        # run through a couple checks just to see what comes up
        if ($agent.pagination.total -gt 1) {
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
                
                Write-Host "Unlinking the agent"
                #unlink the agent
                $headers = $null
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $targetagent = "https://cloud.tenable.com/scanners/1/agents/$($agentid)"
                $headers.Add("X-ApiKeys", "accessKey=$TenableaccessKey; secretKey=$TenablesecretKey")
                $unlink = Invoke-WebRequest -Uri $targetagent -Method Delete -Headers $headers
                start-sleep -Seconds 20

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
            }
            catch {
                $Validation.Add([PSCustomObject]@{System = 'Server' 
                Step = 'Tenable Unlink'
                Status = 'Failed'
                FriendlyError = "Could not unlink Tenable object. Please check"
                PsError = $PSItem.Exception}) > $null

                return $Validation
            }  
        }
    }
    return $Validation, $unlink
}