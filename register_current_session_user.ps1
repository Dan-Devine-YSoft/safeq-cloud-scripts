# Input API key for the given customer that has advanced permissions [CreateUser, ViewUser]
# and [Allow unauthenticated requests, Allow Unauthorized Endpoints] set on the key
$headers = @{
    "X-Api-Key" = "API_KEY"
}

# Input customer domain
$apiUrl = "https://CUSTOMER_DOMAIN:7300/api/v1/users"

$currentUsername = [Environment]::UserName
$response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body "username=$currentUsername" -ContentType "application/x-www-form-urlencoded"
Write-Output $response