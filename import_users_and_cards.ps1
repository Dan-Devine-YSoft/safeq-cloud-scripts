############### Use Case ###################
# This script leverages the 'Create User' API function documented here:  https://docs.ysoft.cloud/api/api-functions#APIFunctions-Createuser
# The script will parse a supplied CSV and create a new user with the additional fields described below
# The script is only capable of new user creation.  It will not modify existing users, or delete/overwrite content
# This script is designed to be used as a starting place for any user creation requirement and can be extended/modified as needed

############## Configuration ###############
$customerDomain = "domain"
$apiKey="api-key" # Needs to have extended rights [ViewUser, CreateUser], Allow unauthenticated requests and Allow untrusted endpoints

############## Users CSV file ##############
# [Mandatory fields]
# username
#
# [Optional fields]
# providerId
# fullName
# email
# homeFolder
# password
# cardId
# shortId
# pin
# alias
# department
# expiration
# externalId
#
# [users.csv example]
# username;fullName;email;cardId
# user1;Full Name 1;email@domain.com;CARD01
# user2;Full Name 2;email@domain.com;CARD02
# user3;Full Name 3;email@domain.com;CARD03
#
$csvFilePath="users.csv"
$csvDelimiter=";"
############################################

$apiUrl = "https://$customerDomain" + ":7300/api/v1/users"
$data = Import-Csv -Path $csvFilePath -Delimiter $csvDelimiter
$detailTypeMap = @{
    "fullName" = 0
    "email" = 1
    "homeFolder" = 2
    "password" = 3
    "cardId" = 4
    "shortId" = 5
    "pin" = 6
    "alias" = 7
    "department" = 11
    "expiration" = 12
    "externalId" = 14
}

$data | ForEach-Object {
    $body = @()
    $body += "username=$($_.username)"

    if ($_.providerid) {
        $body += "providerid=$($_.providerid)"
    }

    foreach ($key in $_.PSObject.Properties.Name) {
        if ($detailTypeMap.ContainsKey($key)) {
            $detailType = $detailTypeMap[$key]
            $detailData = $_.$key
            $body += "detailtype=$detailType"
            $body += "detaildata=$detailData"
        }
    }

    $bodyString = [String]::Join("&", $body)

    try {
        Write-Output "Sending request for user $($_.username) : $bodyString"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Put -ContentType "application/x-www-form-urlencoded" -Headers @{ "X-Api-Key" = $apiKey } -Body $bodyString
        Write-Output "Success for user $($_.username)"
        Start-Sleep -Seconds 1
    } catch {
        Write-Output "Error for user $($_.username): $_"
    }
}