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

#WARNING MESSAGE
#############################
Write-Host "WARNING BY DEFAULT THIS SCRIPT WILL SEND A SIMULATION TO ALL USERS, PLEASE EDIT AND DO NOT RUN IN PRODUCTION ENVIRONEMTS AS IS" -ForegroundColor Red
Write-Host "Please enter YES to continue" -ForegroundColor Yellow
$confirmation = Read-Host "Continue? [YES/NO]"
while($confirmation -ne "YES")
{
    if ($confirmation -eq 'NO') {exit}
    $confirmation = Read-Host "Continue? [YES/NO]"
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


## Get Our Users
################
Write-Host "Getting Users" -ForegroundColor Green
$UserResult = @()
$ApiUrl = "https://graph.microsoft.com/V1.0/users?`$select=userPrincipalName&`$top=999"
$Response = Invoke-RestMethod -Headers $headerParams -Uri $ApiUrl -Method Get
$Users = $Response.value
$UserResult = $Users
 
While ($Response.'@odata.nextLink' -ne $null) {
  $Response = Invoke-RestMethod -Headers $headerParams -Uri $Response.'@odata.nextLink' -Method Get
  $Users = $Response.value
  $UserResult += $Users
}

## Lets remove invalid email address (Use thos to filter out accounts with bad characters etc or exclude)
####################################
Write-Host "Parsing Users" -ForegroundColor Green
$validusers = @()
foreach ( $user in $UserResult | Where {$_.userPrincipalName -notlike '*Attack*'})
{
  $validusers += $user
}

## Lets Randomize that User list
################################
Write-Host "Randomize Users" -ForegroundColor Green
$validusers = $validusers | Sort-Object {Get-Random}

## Lets Split into XX Groups
############################
$batch = 12
$cadence = 60

## Begin looping of users
#########################
$groups = [int] ( $validusers.count / $batch )

## Output some data to UI
#########################
Write-Host "Number of users to be targetted $($validusers.count)" -ForegroundColor Green
Write-Host "Number of simulations to be created $batch" -ForegroundColor Green
Write-Host "Users per simulation $groups" -ForegroundColor Green
Write-Host "Cadence of simulations $cadence" -ForegroundColor Green
Write-Host "Auto Creating in 10 secs, ctrl C to abort" -ForegroundColor Yellow
Start-Sleep -Seconds 20

$batchNum = 0
$i = 0
while ($i -lt $validusers.Count) {
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
$targets = $validusers[$i..($i+= $groups - 1)].userPrincipalName  | Join-String -DoubleQuote -Separator ","
$batchNum++    
$createdby = "stuartcl@o365TISDFV2.onmicrosoft.com" 
$date = Get-Date -Format "HH:MM dddd MM/dd/yyyy"
$payload = $RandomPayload.id
Write-Host "Simulation Batch Number: $batchNum Rolling User Count: $i" -ForegroundColor Green 

$requestbody = @"
{
  "displayName": "Batch $batchNum $date Graph Simulation Demo Test",
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
$response = Invoke-WebRequest https://graph.microsoft.com/beta/security/attacksimulation/simulations -Method 'POST' -Headers $headerParams -Body $requestBody -TimeoutSec 120
$trackingUrl = $response.Headers.Location

$t = 0;
#Tracking the queued simulation
Write-host "Tracking url: "$trackingUrl
$operationResponse = Invoke-WebRequest $trackingUrl -Method 'GET' -Headers $headerParams -TimeoutSec 120

#Reading the newly created simulation
$content = $operationResponse.content| ConvertFrom-Json
Write-Host "Simulation creation status : "$content.status

while($t -ne 6 -and $content.status -ne "succeeded"){
    Start-Sleep -Seconds 15
    $operationResponse = Invoke-WebRequest $trackingUrl -Method 'GET' -Headers $headerParams -TimeoutSec 120
    #Reading the newly created simulation
    $content = $operationResponse.content| ConvertFrom-Json
    Write-Host "Simulation creation status : "$content.status
    $t=$t+1;
}
if($content.status -ne "succeeded"){
    Write-Host "Creating taking more time.. Please recheck after sometime."
}
else{
    $getSimulation = Invoke-WebRequest -Uri $content.resourceLocation -Method 'GET' -Headers $headerParams -TimeoutSec 120
    Write-Host "Created simulation : " ($getSimulation.Content | ConvertFrom-Json).id
}

}
