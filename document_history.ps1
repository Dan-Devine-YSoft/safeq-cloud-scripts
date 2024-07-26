Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$apiKey = "addapikeyhere" # API key requires ViewReport rights
$domain = "customerdomain" # Add customer domain eg customer.au.ysoft.cloud
$csvPath = "document_history.csv" # Define a name for the CSV file
$maxRecords = "2000" # Define maximum number of records returned per API call, must be between 200 and 2000.  If 2000 fails, try a lower number eg 1000
function Show-DatePicker {
    param (
        [string]$message = "Select a date"
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $message
    $form.Width = 250
    $form.Height = 250
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    $calendar = New-Object System.Windows.Forms.MonthCalendar
    $calendar.MaxSelectionCount = 1
    $calendar.Dock = [System.Windows.Forms.DockStyle]::Fill
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

function Fetch-DocumentHistory {
    param (
        [string]$apiUrlBase,
        [string]$apiKey,
        [hashtable]$statusMapping
    )

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
    Write-Host "Valid start date and end date are required."
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
    Write-Host "API key is required."
    exit 1
}

if (-not $domain) {
    Write-Host "Domain is required."
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

if (-not (Test-Path $csvPath)) {
    $csvHeaders = "date,time,userName,documentName,jobType,outputPortName,grayscale,colorPages,totalPages,paperSize,status"
    Out-File -FilePath $csvPath -InputObject $csvHeaders -Encoding UTF8
}

$totalDocumentDetails | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8
Write-Host "Document details appended to $csvPath successfully."
