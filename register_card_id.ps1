$apiUrl = 'https://<customer-domain>:7300/api/v1/users/<username>/cards'  # Replace <customer-domain> and <username> with actual values
$apiKey = '<api-key>'  # Replace <api-key> with your actual API key
$cardId = '<card-id>'  # Replace <card-id> with the actual card ID

$headers = @{
    'X-Api-Key' = $apiKey
}

$response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ('cardid=' +$cardId) -ContentType 'application/x-www-form-urlencoded' -SkipCertificateCheck
$response