##Functions
###########
function Join-String {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string[]]$StringArray, 
        $Separator=",",
        [switch]$DoubleQuote=$false
    )
    BEGIN{
        $joinArray = [System.Collections.ArrayList]@()
    }
    PROCESS {
        foreach ($astring in $StringArray) {
            $joinArray.Add($astring) | Out-Null
        }
    }
    END {
        $Object = [PSCustomObject]@{}
        $count = 0;
        foreach ($aString in $joinArray) {
            
            $name = "ieo_$($count)"
            $Object | Add-Member -MemberType NoteProperty -Name $name -Value $aString;
            $count = $count + 1;
        }
        $ObjectCsv = $Object | ConvertTo-Csv -NoTypeInformation -Delimiter $separator
        $result = $ObjectCsv[1]
        if (-not $DoubleQuote) {
            $result = $result.Replace('","',",").TrimStart('"').TrimEnd('"')
        }
        return $result
    }
}

#Define Client Variables Here
#############################
$ClientID = "YOURCLIENTID"
$ClientSecret = "YOURCLIENTSECRET"
$loginURL = "https://login.windows.net/"
$tenantdomain = "YOURTENANTDOMAIN"
$resource = "https://graph.microsoft.com"
 
#Construct Auth call to get Access Token 
#########################################
$graphBody = @{grant_type="client_credentials";resource=$resource;client_id=$ClientID;client_secret=$ClientSecret}
$oauth = Invoke-RestMethod -Method Post -Uri $loginURL/$tenantdomain/oauth2/token?api-version=1.0 -Body $graphBody
$headerParams = @{'Authorization'="$($oauth.token_type) $($oauth.access_token)"}


## Get Our Payloads (Limited to Cred Harvest)
###################
Write-Host "Getting Payloads" -ForegroundColor Green
$payloads = Invoke-RestMethod -Method Get -Headers $headerParams -Uri "https://graph.microsoft.com/beta/security/attackSimulation/payloads?`$filter=source%20eq%20%27Tenant%27"
$payloadlist = [System.Collections.ArrayList] ($payloads.value | Where-Object{$_.technique -like "credentialHarvesting"} | select id)


## Get Our Users from Advanced Hunting
######################################
Write-Host "Getting Users" -ForegroundColor Green
$querybody = @"
{
    "Query": "EmailEvents | where Timestamp > ago(1d) and ThreatTypes like \"Phish\" | project Timestamp, RecipientEmailAddress | top 10 by Timestamp desc"
}
"@

$Response = Invoke-WebRequest https://graph.microsoft.com/v1.0/security/runHuntingQuery -Method 'POST' -Headers $headerParams -Body $querybody -TimeoutSec 120 -ContentType application/json
$HuntUsers = $Response | ConvertFrom-Json



## Lets parse out the email address
####################################
Write-Host "Parsing Users" -ForegroundColor Green
$validusers = @()
foreach ( $user in $HuntUsers.results.RecipientEmailAddress | select $_.RecipientEmailAddress)
{
  $validusers += $user
}


## Output some data to UI
#########################
Write-Host "Number of users to be targetted $($validusers.count)" -ForegroundColor Green
Write-Host "List of Top Targetted Phish" -ForegroundColor Green
$validusers
Write-Host "Auto Creating in 20 secs, ctrl C to abort" -ForegroundColor Yellow
Start-Sleep -Seconds 20

$cadence = 60

  Write-Host "Creating Simulations" -ForegroundColor Green 
  ## Set simulation delay timer
  #############################
  Start-Sleep -Seconds $cadence

  ## Pick random payload and remove from list
  ###########################################
  $RandomPayload = Get-Random $payloadlist.ToArray()
  $payloadlist.Remove($RandomPayload)

  ## Create Simulation Variables (should be global, lazy coder!)
  ##############################
  $targets = $validusers | Join-String -DoubleQuote -Separator ','
  
  $createdby = "stuartcl@o365TISDFV2.onmicrosoft.com" 
  $date = Get-Date -Format "HH:MM dddd MM/dd/yyyy"
  $payload = $RandomPayload.id
  $requestbody = @"
{
  "displayName": "Hunting Top Targeted $date Graph Simulation",
  "description": "Graph Powershell Uberness",
  "attackType": "social",
  "payload@odata.bind": "https://graph.microsoft.com/beta/security/attacksimulation/payloads/('$payload')",
  "payloadDeliveryPlatform": "email",
  "attackTechnique": "credentialHarvesting",
  "status": "scheduled",
  "durationInDays": 2,
  "createdBy": {
    "email": "$createdby"
  },
  "includedAccountTarget": {
  "@odata.type": "#microsoft.graph.addressBookAccountTargetContent",
    "type" : "addressBook",
  "accountTargetEmails" : [
        $targets
    ]
  }
}
"@

  ##Launch the simulation
  #######################
  Invoke-WebRequest https://graph.microsoft.com/beta/security/attacksimulation/simulations -Method 'POST' -Headers $headerParams -Body $requestBody -TimeoutSec 120


