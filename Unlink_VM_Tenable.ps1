Connect-AzAccount -Environment AzureCloud

Set-AzContext -Subscription Enterprise

# get my API keys from the key vault, need to use these in the headers var but don't know the syntax
$accessKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'TenableAccessKey' -AsPlainText
$secretKey = Get-AzKeyVaultSecret -vaultName 'kv-308' -name 'TenableSecretKey' -AsPlainText

$unlinklist = 'TXAINFAZU901'
$agents1 = [System.Collections.ArrayList]@()
$agents2 = [System.Collections.ArrayList]@()
$listallagents = [System.Collections.ArrayList]@()
# gets all the relevant agents and info
$headers = $null
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$resource = 'https://cloud.tenable.com/scanners/1/agent-groups/101288/agents?offset=0&limit=5000'
$headers.Add("X-ApiKeys", "accessKey=$accessKey; secretKey=$secretKey")
$agents1 = (Invoke-RestMethod -Uri $resource -Method Get -Headers $headers).agents

# gets all the relevant agents and info
$headers = $null
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$resource = 'https://cloud.tenable.com/scanners/1/agent-groups/101288/agents?offset=5001&limit=5000'
$headers.Add("X-ApiKeys", "accessKey=$accessKey; secretKey=$secretKey")
$agents2 = (Invoke-RestMethod -Uri $resource -Method Get -Headers $headers).agents

$listallagents = $agents1 + $agents2

foreach ($vm in $unlinklist)
{
    # filter first on the name of the machine you unlinking to get the info
    $agentinfo = $listallagents | Where-Object {$_.name -eq $vm}

    if ($null -eq $agentinfo)
    {
        Write-Host "This agent has either been unlinked, or someone else has deleted it" -ForegroundColor Yellow
    } else {
        # then get the ID to for the endpoint
        $agentid = $agentinfo.id

        #unlink the agent
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $targetagent = "https://cloud.tenable.com/scanners/1/agents/$agentid"
        $headers.Add("X-ApiKeys", 'accessKey=$accessKey; secretKey=$secretKey')
        $unlink = Invoke-WebRequest -Uri $targetagent -Method Delete -Headers $headers

        if ($unlink.StatusCode -ne 200)
        {
            Write-Host: "Agent was not unlinked. Please try again." -ForegroundColor Red
        }
    }
}




### STUFF THAT I DON'T NEED TO USE RIGHT NOW ####


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

