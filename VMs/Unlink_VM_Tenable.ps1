Connect-AzAccount -Environment AzureCloud

Set-AzContext -Subscription Enterprise

# get my API keys from the key vault, need to use these in the headers var but don't know the syntax
$accessKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableAccessKey' -AsPlainText
$secretKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'ORRChecks-TenableSecretKey' -AsPlainText

$unlinklist = "TXAINFAZU902"

foreach ($vm in $unlinklist)
{
    # gets all the relevant agents and info
    $headers = $null
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $resource = "https://cloud.tenable.com/scanners/null/agents?offset=0&limit=50&sort=name:asc&wf=core_version,distro,groups,ip,name,platform,status&w=$($vm)"
    $headers.Add("X-ApiKeys", "accessKey=$accessKey; secretKey=$secretKey")
    $agent = (Invoke-RestMethod -Uri $resource -Method Get -Headers $headers).agents

    if (($null -eq $agent) -or ($agent.count -eq 0))
    {
        # check to see if agent even exists
        Write-Host "This agent has either been unlinked, or someone else has deleted it" -ForegroundColor Yellow
    }elseif ($agent.count -gt 1) {
        #check for multiple objects
        write-host "Multiple objects were found with this server name. Please go troubleshoot" -ForegroundColor Red
    }else {
        write-host "Agent found. Unlinking..." -ForegroundColor Yellow

        # then get the ID to for the endpoint
        $agentid = $agent.id

        #unlink the agent
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $targetagent = "https://cloud.tenable.com/scanners/1/agents/$($agentid)"
        $headers.Add("X-ApiKeys", "accessKey=$accessKey; secretKey=$secretKey")
        $unlink = Invoke-WebRequest -Uri $targetagent -Method Delete -Headers $headers

        if ($unlink.StatusCode -ne 200)
        {
            Write-Host "Agent $($agent.name) was not unlinked. Please try again." -ForegroundColor Red
        }else {
            Write-host "Agent $($agent.name) was successfully unlinked" -ForegroundColor Green
        }
    }
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

