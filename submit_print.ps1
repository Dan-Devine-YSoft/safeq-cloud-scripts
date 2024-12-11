# submit_print.ps1 - Dan Devine @ Ysoft
# This script will submit a job to the SafeQ Cloud API on behalf of a user.  It will prompt for user credentials
# to generate a user token

# User-defined variables - you can edit this section
$configFilePath = "submit_job.cfg"
$logFilePath = "submit_job.log"

######  DO NOT EDIT BELOW THIS LINE  ######

# Initialize log file
if (-not (Test-Path $logFilePath)) {
    $null = New-Item -ItemType File -Path $logFilePath -Force
}

function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$level] - $message"
    Add-Content -Path $logFilePath -Value $logMessage
    Write-Host $logMessage
}

function Get-UserCredentials {
    param (
        [string]$prompt
    )
    return Read-Host -Prompt $prompt -AsSecureString
}

function Initialize-Config {
    $config = @{}
    if (Test-Path $configFilePath) {
        $configContent = Get-Content -Path $configFilePath -Raw
        if ($configContent) {
            $config = $configContent | ConvertFrom-Json
        }
    }
    if (-not $config -or $config -isnot [hashtable]) {
        $config = @{}
    }

    if (-not $config.PSObject.Properties.Match('domain').Count) {
        $config.domain = Read-Host "Enter your SafeQ Cloud domain (eg. customer.au.ysoft.cloud)"
    }

    if (-not $config.PSObject.Properties.Match('apikey').Count) {
        $apiKey = Get-UserCredentials -prompt "Enter API key"
        $config.apikey = $apiKey | ConvertFrom-SecureString
    }

    if (-not $config.PSObject.Properties.Match('userid').Count) {
        $config.userid = Read-Host "Enter username with AddJob advanced API permissions"
    }

    if (-not $config.PSObject.Properties.Match('password').Count) {
        $password = Get-UserCredentials -prompt "Enter password for the above user"
        $config.password = $password | ConvertFrom-SecureString
    }

    if (-not $config.PSObject.Properties.Match('fileName').Count) {
        $config.fileName = Read-Host "Enter the file name to print (including full path)"
        if (-not (Test-Path $config.fileName)) {
            Write-Host "The file '$($config.fileName)' does not exist. Please provide a valid file path."
            exit 1
        }
    }

    if (-not $config.PSObject.Properties.Match('submitUsername').Count) {
        $config.submitUsername = Read-Host "Enter the username to submit the print job as"
    }

    if (-not $config.PSObject.Properties.Match('queueName').Count) {
        $config.queueName = Read-Host "Enter the queue name to submit the print job to"
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
    $config.domain = Read-Host "Enter your SafeQ Cloud domain (eg. customer.au.ysoft.cloud)"
}

if (-not $config.PSObject.Properties.Match('apikey').Count -or -not $config.apikey) {
    $apiKey = Get-UserCredentials -prompt "Enter API key"
    $config.apikey = $apiKey | ConvertFrom-SecureString
}

if (-not $config.PSObject.Properties.Match('userid').Count -or -not $config.userid) {
    $config.userid = Read-Host "Enter username with AddJob advanced API permissions"
}

if (-not $config.PSObject.Properties.Match('password').Count -or -not $config.password) {
    $password = Get-UserCredentials -prompt "Enter password for above user"
    $config.password = $password | ConvertFrom-SecureString
}

if (-not $config.PSObject.Properties.Match('fileName').Count -or -not $config.fileName) {
    $config.fileName = Read-Host "Enter the file name to print (including full path)"
    if (-not (Test-Path $config.fileName)) {
        Write-Host "The file '$($config.fileName)' does not exist. Exiting."
        exit 1
    }
}

if (-not $config.PSObject.Properties.Match('submitUsername').Count -or -not $config.submitUsername) {
    $config.submitUsername = Read-Host "Enter the username to submit the print job as"
}

if (-not $config.PSObject.Properties.Match('queueName').Count -or -not $config.queueName) {
    $config.queueName = Read-Host "Enter the queue name to submit the print job to"
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

Write-Log "Using API Key."

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
        Write-Log "Error obtaining user token: $_" -level "ERROR"
        exit 1
    }
}

function Put-PrintJob {
    param (
        [string]$apiBaseUrl,
        [string]$token,
        [string]$username,
        [string]$portname,
        [string]$title,
        [string]$filePath,
        [int]$providerid = 0,  # Optional
        [int]$copies = 1,  # Optional
        [bool]$grayscale = $false,  # Optional
        [int]$duplex = 0,  # Optional: 0=simplex, 1=long edge, 2=short edge
        [string]$outputpagesize = "Original",  # Optional
        [int]$pageorientation = 0,  # Optional: 0=portrait, 1=landscape
        [int]$scale = 100  # Optional
    )

    $apiUrl = "$apiBaseUrl/documents"
    $headers = @{
        "X-Api-Key"      = $plainApiKey
        "Authorization"  = "Bearer $token"
    }

    if (-not (Test-Path $filePath)) {
        Write-Log "Error: File $filePath not found." -level "ERROR"
        return
    }

    # Prepare the HTTP content
    $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
    $multipartContent.Add([System.Net.Http.StringContent]::new($username), "username")
    $multipartContent.Add([System.Net.Http.StringContent]::new($portname), "portname")
    $multipartContent.Add([System.Net.Http.StringContent]::new($title), "title")
    $multipartContent.Add([System.Net.Http.StringContent]::new($providerid.ToString()), "providerid")
    $multipartContent.Add([System.Net.Http.StringContent]::new($copies.ToString()), "copies")
    $multipartContent.Add([System.Net.Http.StringContent]::new($grayscale.ToString().ToLower()), "grayscale")
    $multipartContent.Add([System.Net.Http.StringContent]::new($duplex.ToString()), "duplex")
    $multipartContent.Add([System.Net.Http.StringContent]::new($outputpagesize), "outputpagesize")
    $multipartContent.Add([System.Net.Http.StringContent]::new($pageorientation.ToString()), "pageorientation")
    $multipartContent.Add([System.Net.Http.StringContent]::new($scale.ToString()), "scale")

    # Add the file content
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
    $multipartContent.Add($fileContent, "data", [System.IO.Path]::GetFileName($filePath))

    # Perform the API request
    $httpClient = [System.Net.Http.HttpClient]::new()
    foreach ($key in $headers.Keys) {
        $httpClient.DefaultRequestHeaders.Add($key, $headers[$key])
    }

    Write-Log "Submitting print job '$title' for user '$username'..."
    try {
        $response = $httpClient.PutAsync($apiUrl, $multipartContent).Result
        if ($response.IsSuccessStatusCode) {
            $responseContent = $response.Content.ReadAsStringAsync().Result
            Write-Log "Print job submitted successfully. Response: $responseContent"
        } else {
            Write-Log "Error submitting print job. Status: $($response.StatusCode). Response: $($response.Content.ReadAsStringAsync().Result)" -level "ERROR"
        }
    } catch {
        Write-Log "Error during API request: $_" -level "ERROR"
    } finally {
        $fileStream.Dispose()
        $httpClient.Dispose()
    }
}

# Get the user token
$token = Get-UserToken -userid $userid -securePassword $securePassword -plainApiKey $plainApiKey

# Submit the print job
Put-PrintJob -apiBaseUrl $apiBaseUrl -token $token -username $config.submitUsername -portname $config.queueName -title "Test Print" -filePath $config.fileName

Write-Log "Print job submitted for print."
