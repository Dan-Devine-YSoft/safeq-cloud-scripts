# document_history.ps1 - Dan Devine @ Ysoft
# This script will query the /documents/history API endpoint and create a CSV file with the content.  It requires some minor configuration as detailed here: https://github.com/Dan-Devine-YSoft/safeq-cloud-scripts/wiki/Document-History

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# User-defined variables - you can edit this section

$configFilePath = "document_history.cfg"
$csvPath = "document_history.csv"
$maxRecords = "2000"
$logFilePath = "document_history.log"

######  DO NOT EDIT BELOW THIS LINE  ######

# Initialize log file
if (-not (Test-Path $logFilePath)) {
    New-Item -ItemType File -Path $logFilePath -Force
}

function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content -Path $logFilePath -Value $logMessage
    Write-Host $logMessage
}

function Get-UserCredentials {
    param (
        [string]$prompt
    )
    $secureString = Read-Host -Prompt $prompt -AsSecureString
    return $secureString
}

function Initialize-Config {
    $config = @{}

    if (Test-Path $configFilePath) {
        $configContent = Get-Content -Path $configFilePath -Raw
        if ($configContent) {
            $config = $configContent | ConvertFrom-Json
        }
    }

    # Ensure $config is a hashtable
    if (-not $config -or $config -isnot [hashtable]) {
        $config = @{}
    }

    if (-not $config.PSObject.Properties.Match('domain').Count) {
        $config.domain = Read-Host "Enter domain eg. customer.au.ysoft.cloud"
    }

    if (-not $config.PSObject.Properties.Match('apikey').Count) {
        $apiKey = Read-Host "Enter API key" -AsSecureString
        $config.apikey = $apiKey | ConvertFrom-SecureString
    }

    if (-not $config.PSObject.Properties.Match('userid').Count) {
        $config.userid = Read-Host "Enter username with ViewReport access"
    }

    if (-not $config.PSObject.Properties.Match('password').Count) {
        $password = Read-Host "Enter password for the above user" -AsSecureString
        $config.password = $password | ConvertFrom-SecureString
    }

    # Write the complete config back to the file
    $config | ConvertTo-Json -Depth 32 | Set-Content -Path $configFilePath -Force

    return $config
}

function Get-Config {
    $config = @{}
    if (Test-Path $configFilePath) {
        $configContent = Get-Content -Path $configFilePath -Raw
        if ($configContent) {
            $config = $configContent | ConvertFrom-Json
        }
    }
    return $config
}

function ConvertFrom-SecureConfigString {
    param (
        [string]$secureString
    )
    return $secureString | ConvertTo-SecureString
}

function ConvertTo-PlainText {
    param (
        [SecureString]$secureString
    )
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))
}

# Load existing configuration
$config = Get-Config

# Prompt for missing values
if (-not $config.PSObject.Properties.Match('domain').Count -or -not $config.domain) {
    $config.domain = Read-Host "Enter domain"
}

if (-not $config.PSObject.Properties.Match('apikey').Count -or -not $config.apikey) {
    $apiKey = Read-Host "Enter API key" -AsSecureString
    $config.apikey = $apiKey | ConvertFrom-SecureString
}

if (-not $config.PSObject.Properties.Match('userid').Count -or -not $config.userid) {
    $config.userid = Read-Host "Enter user ID"
}

if (-not $config.PSObject.Properties.Match('password').Count -or -not $config.password) {
    $password = Read-Host "Enter password" -AsSecureString
    $config.password = $password | ConvertFrom-SecureString
}

# Write the complete config back to the file
$config | ConvertTo-Json -Depth 32 | Set-Content -Path $configFilePath -Force

# Convert secure strings back to secure strings for use
$domain = $config.domain
$apiKey = ConvertFrom-SecureConfigString -secureString $config.apikey
$userid = $config.userid
$securePassword = ConvertFrom-SecureConfigString -secureString $config.password

# Convert the secure API key to plain text for use
$plainApiKey = ConvertTo-PlainText -secureString $apiKey

$loginUrl = "https://${domain}:7300/api/v1/login"
$apiBaseUrl = "https://${domain}:7300/api/v1"

Write-Log "Using API Key: $plainApiKey"

function Get-UserToken {
    param (
        [string]$userid,
        [SecureString]$securePassword,
        [string]$plainApiKey
    )

    $password = ConvertTo-PlainText -secureString $securePassword

    $headers = @{
        "X-Api-Key" = "$plainApiKey"
    }

    $body = @{
        authtype = 0
        userid   = $userid
        password = $password
    }

    try {
        Write-Log "Requesting user token..."
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers $headers -ContentType "application/x-www-form-urlencoded" -Body $body -SkipCertificateCheck
        return $response.token.access_token
    } catch {
        Write-Log "Error obtaining user token: $_"
        exit 1
    }
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

function ConvertFrom-ApiResponse {
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
            date = $localDateTime.ToString("yyyy-MM-dd")
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

function Get-DocumentHistory {
    param (
        [string]$apiUrlBase,
        [string]$token,
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

        Write-Log "Getting records from API, please wait... (Page $pageCount)"
        try {
            for ($i = 0; $i -lt $retryCount; $i++) {
                try {
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{
                        "X-Api-Key" = "$plainApiKey"
                        "Authorization" = "Bearer $token" } -SkipCertificateCheck
                    Write-Log "Records obtained successfully."
                    break
                } catch {
                    Write-Log "Attempt $($i + 1) failed: $_"
                    if ($i -eq $retryCount - 1) {
                        throw
                    }
                    Start-Sleep -Seconds 5
                }
            }
        }
        catch {
            Write-Log "Error fetching data from API: $_"
            return $documentDetails
        }

        if (-not $response -or -not $response.documents) {
            Write-Log "No documents found or invalid response."
            return $documentDetails
        }

        # Process the response
        $documentDetails = ConvertFrom-ApiResponse -response $response -documentDetails $documentDetails -statusMapping $statusMapping

        # Get the nextPageToken if available
        $nextPageToken = $response.nextPageToken
        $pageCount++

        # Add a 2-second delay between API calls
        Start-Sleep -Seconds 2

    } while ($nextPageToken)

    return $documentDetails
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Get start and end dates
$startDate = Show-DatePicker -message "Select Start Date"
$endDate = Show-DatePicker -message "Select End Date"

# Ensure dates are valid before proceeding
if (-not $startDate -or -not $endDate -or -not ($startDate -is [DateTime]) -or -not ($endDate -is [DateTime])) {
    Write-Log "Valid start date and end date are required."
    exit 1
}

if ($startDate -gt $endDate) {
    Write-Log "Start date cannot be later than end date."
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

$totalDocumentDetails = @()
$currentStartDate = $startDate
while ($currentStartDate -lt $endDate) {
    $currentEndDate = $currentStartDate.AddDays(6)
    if ($currentEndDate -gt $endDate) {
        $currentEndDate = $endDate
    }

    $formattedStartDate = $currentStartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $formattedEndDate = $currentEndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    $apiUrlBase = "$apiBaseUrl/documents/history?datestart=${formattedStartDate}&dateend=${formattedEndDate}&maxrecords=${maxRecords}"
    $documentDetails = Get-DocumentHistory -apiUrlBase $apiUrlBase -token $token -statusMapping $statusMapping
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
    Write-Log "Document details appended to $csvPath successfully."
} catch {
    Write-Log "Error writing to CSV file: $_"
}
