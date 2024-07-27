Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$apiKey = $env:SQC_API_KEY # Use environment variable for API key
$domain = $env:SQC_DOMAIN # Use environment variable for domain
$csvPath = "document_history.csv" # Define a name for the CSV file
$maxRecords = "2000" # Define maximum number of records returned per API call, must be between 200 and 2000. If 2000 fails, try a lower number e.g., 1000
$logFilePath = "document_history.log" # Log file location and name

# Initialize log file
if (-not (Test-Path $logFilePath)) {
    New-Item -ItemType File -Path $logFilePath -Force
}

function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content -Path $logFilePath -Value $logMessage
    Write-Host $logMessage
}

function Show-DatePicker {
    param (
        [string]$message = "Select a date"
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $message
    $form.Width = 600
    $form.Height = 250
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    $calendar = New-Object System.Windows.Forms.MonthCalendar
    $calendar.MaxSelectionCount = 1
    $calendar.Dock = [System.Windows.Forms.DockStyle]::Fill

    # Set the selection range to show the current month and the preceding two months
    $today = [DateTime]::Today
    $calendar.SelectionStart = (Get-Date -Year $today.Year -Month $today.Month -Day 1).AddMonths(-2)
    $calendar.SelectionEnd = $today

    $form.Controls.Add($calendar)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $okButton.Add_Click({
        $form.Tag = $calendar.SelectionStart
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    } else {
        return $null
    }
}

function Process-ApiResponse {
    param (
        $response,
        $documentDetails,
        $statusMapping
    )

    $timeZoneInfo = [TimeZoneInfo]::Local

    foreach ($doc in $response.documents) {
        $epochStart = [DateTime]::UnixEpoch.AddMilliseconds($doc.dateTime)
        $localDateTime = [TimeZoneInfo]::ConvertTimeFromUtc($epochStart, $timeZoneInfo)
        $fullDateTime = $localDateTime.ToString("yyyy-MM-dd HH:mm:ss")

        $statusCode = [int]$doc.status
        $statusString = $statusMapping[$statusCode] -replace 'Null','Unknown status code'
        $documentName = if ([string]::IsNullOrWhiteSpace($doc.documentName)) { "NoDocumentName" } else { $doc.documentName }

        $documentDetails += [PSCustomObject]@{
            fullDateTime = $fullDateTime
            date = $localDateTime.ToString("dd-MM-yy")
            time = $localDateTime.ToString("HH:mm:ss")
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

function Fetch-DocumentHistory {
    param (
        [string]$apiUrlBase,
        [string]$apiKey,
        [hashtable]$statusMapping
    )

    $documentDetails = @()
    $nextPageToken = $null
    $pageCount = 1
    $retryCount = 3

    do {
        $apiUrl = $apiUrlBase
        if ($nextPageToken) {
            $apiUrl += "&nextPageToken=$nextPageToken"
        }

        Log-Message "Getting records from API, please wait... (Page $pageCount)"
        try {
            for ($i = 0; $i -lt $retryCount; $i++) {
                try {
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{ "X-Api-Key" = $apiKey }
                    break
                } catch {
                    Log-Message "Attempt $($i + 1) failed: $_"
                    if ($i -eq $retryCount - 1) {
                        throw
                    }
                    Start-Sleep -Seconds 5
                }
            }
        }
        catch {
            Log-Message "Error fetching data from API: $_"
            return $documentDetails
        }

        if (-not $response -or -not $response.documents) {
            Log-Message "No documents found or invalid response."
            return $documentDetails
        }

        # Process the response
        $documentDetails = Process-ApiResponse -response $response -documentDetails $documentDetails -statusMapping $statusMapping

        # Get the nextPageToken if available
        $nextPageToken = $response.nextPageToken
        $pageCount++
    } while ($nextPageToken)

    return $documentDetails
}

# Get start and end dates
$startDate = Show-DatePicker -message "Select Start Date"
$endDate = Show-DatePicker -message "Select End Date"

# Ensure dates are valid before proceeding
if (-not $startDate -or -not $endDate -or -not ($startDate -is [DateTime]) -or -not ($endDate -is [DateTime])) {
    Log-Message "Valid start date and end date are required."
    exit 1
}

if ($startDate -gt $endDate) {
    Log-Message "Start date cannot be later than end date."
    exit 1
}

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
    Log-Message "API key is required."
    exit 1
}

if (-not $domain) {
    Log-Message "Domain is required."
    exit 1
}

$totalDocumentDetails = @()
$currentStartDate = $startDate
while ($currentStartDate -lt $endDate) {
    $currentEndDate = $currentStartDate.AddDays(6)
    if ($currentEndDate -gt $endDate) {
        $currentEndDate = $endDate
    }

    $formattedStartDate = $currentStartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $formattedEndDate = $currentEndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    $apiUrlBase = "https://${domain}:7300/api/v1/documents/history?datestart=${formattedStartDate}&dateend=${formattedEndDate}&maxrecords=${maxRecords}"
    $documentDetails = Fetch-DocumentHistory -apiUrlBase $apiUrlBase -apiKey $apiKey -statusMapping $statusMapping
    $totalDocumentDetails += $documentDetails

    $currentStartDate = $currentEndDate.AddSeconds(1) # Ensure no overlap
}

# Sort the document details by full date and time before writing to CSV
$totalDocumentDetails = $totalDocumentDetails | Sort-Object -Property fullDateTime

if (-not (Test-Path $csvPath)) {
    $csvHeaders = "date,time,userName,documentName,jobType,outputPortName,grayscale,colorPages,totalPages,paperSize,status"
    Out-File -FilePath $csvPath -InputObject $csvHeaders -Encoding UTF8
}

try {
    $totalDocumentDetails | Select-Object -Property date, time, userName, documentName, jobType, outputPortName, grayscale, colorPages, totalPages, paperSize, status | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8
    Log-Message "Document details appended to $csvPath successfully."
} catch {
    Log-Message "Error writing to CSV file: $_"
}
