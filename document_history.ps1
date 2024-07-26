$apiKey = "addapikeyhere" # API key requires ViewReport rights
$domain = "customerdomain" # Add customer domain eg customer.au.ysoft.cloud
$startDate = "2024-06-01T00:00:00.000Z" # Add start date for reporting.  You can use https://www.timestamp-converter.com for this - enter a time and date under 'Your Time Zone' and cut and paste the 'ISO 8601' value shown
$endDate = "2024-06-06T00:00:00.000Z" # Add end date for reporting, noting a maximum of a 7 day time period
$csvPath = "document_history.csv" # Define a name for the CSV file
$maxRecords = "2000" # Define maximum number of records returned per API call, must be between 200 and 2000

# Status code mapping - this converts the numeric status code to the corresponding status name
$statusMapping = @{
    0 = "Ready"
    1 = "Printed"
    2 = "Deleted"
    3 = "Expired"
    4 = "Failed"
    5 = "Received"
    6 = "Awaiting-Conversion"
    7 = "Converting"
    8 = "Conversion-Failed"
    9 = "Stored"
}

# Validate inputs
if (-not $apiKey) {
    Write-Host "API key is required."
    exit 1
}

if (-not $domain) {
    Write-Host "Domain is required."
    exit 1
}

if (-not $startDate -or -not $endDate) {
    Write-Host "Start date and end date are required."
    exit 1
}

# Function to process API response and extract document details
function Process-ApiResponse($response, $documentDetails, $statusMapping) {
    $timeZoneInfo = [TimeZoneInfo]::Local

    foreach ($doc in $response.documents) {
        $epochStart = [DateTime]::UnixEpoch.AddMilliseconds($doc.dateTime)
        $localDateTime = [TimeZoneInfo]::ConvertTimeFromUtc($epochStart, $timeZoneInfo)
        $formattedDate = $localDateTime.ToString("dd-MM-yy")
        $time = $localDateTime.ToString("HH:mm:ss")

        $statusCode = [int]$doc.status
        $statusString = $statusMapping[$statusCode] -replace 'Null','Unknown status code'
        $documentName = if ([string]::IsNullOrWhiteSpace($doc.documentName)) { "NoDocumentName" } else { $doc.documentName }

        $documentDetails += [PSCustomObject]@{
            date = $formattedDate
            time = $time
            userName = $doc.userName
            documentName = $documentName
            jobType = $doc.jobType
            outputPortName = $doc.outputPortName
            grayscale = $doc.grayscale
            colorPages = $doc.colorPages
            totalPages = $doc.totalPages
            paperSize = $doc.paperSize
            status = $statusString
        }
    }

    return $documentDetails
}

# API request URL - this formats the API request URL correctly based on the customer domain and defined reporting dates
$apiUrlBase = "https://${domain}:7300/api/v1/documents/history?datestart=${startDate}&dateend=${endDate}&maxrecords=${maxRecords}"

# Start a try/catch loop to invoke the API and format the output, catering for errors
try {
    $documentDetails = @()
    $nextPageToken = $null
    $pageCount = 1

    do {
        $apiUrl = $apiUrlBase
        if ($nextPageToken) {
            $apiUrl += "&nextPageToken=$nextPageToken"
        }

        Write-Host "Getting records from API, please wait... (Page $pageCount)"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{ "X-Api-Key" = $apiKey }

        if (-not $response -or -not $response.documents) {
            Write-Host "No documents found or invalid response."
            exit 1
        }

        # Process the response
        $documentDetails = Process-ApiResponse $response $documentDetails $statusMapping

        # Get the nextPageToken if available
        $nextPageToken = $response.nextPageToken
        $pageCount++

    } while ($nextPageToken)

    if (-not (Test-Path $csvPath)) {
        $csvHeaders = "date,time,userName,documentName,jobType,outputPortName,grayscale,colorPages,totalPages,paperSize,status"
        Out-File -FilePath $csvPath -InputObject $csvHeaders -Encoding UTF8
    }

    $documentDetails | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8
    Write-Host "Document details appended to $csvPath successfully."
} catch {
    Write-Host "Error occurred: $_.Exception.Message"
    exit 1
}
