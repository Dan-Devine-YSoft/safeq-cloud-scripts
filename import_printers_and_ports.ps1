############## Configuration ###############

$customerDomain = "domain"
$apiKey="api-key" # Needs to have extended rights [ViewOutputPort, CreateOutputPort, ViewInputPort and
# CreateInputPort], security should be configured to Allow unauthenticated requests and Allow untrusted endpoints, can be
# disabled after import

############## Users CSV file ##############
# [Mandatory fields]
# portName (name of port and print queue)
# portAddress (ip address of device)
# vendor (unknown, fujifilm, ricoh, km, sharp, hp, lexmark, xerox, kyocera, toshiba, canon, brother, epson, eop)
# printProtocol (0=tcp, 1=ipp - use tcp if unsure as ipp may have certificate requirements)
# outputType (0 = raw, 1 = PDF, 3 = PCL6, 4 = Postscript level 3)
# deviceSerial
#
# [printers.csv example]
# portName;portAddress;vendor;printProtocol;outputType;deviceSerial
# Printer1;10.1.1.1;unknown;0;4;123456
# Printer2;10.1.1.2;unknown;0;4;234567
# Printer3;10.1.1.3;unknown;0;4;345678
# **  NB **  NB  **
# The current version of this script does not check if the printer port already exists.  SafeQ Cloud allows the same IP
# address to be used multiple times in order to cater for certain scenarios.  For now please ensure you test in a test
# tenancy that you can easily delete before using in production

$csvFilePath="printers.csv" # this file should be located in the same folder as the script
$csvDelimiter=";" # ideally use ; to avoid any parsing issues
############################################

# Construct a URL for the /outputports endpoint and store it in a variable
$apiOutputPortUrl = "https://$customerDomain" + ":7300/api/v1/outputports"

# Construct a URL for the /inputports endpoint and store it in a variable
$apiInputPortUrl = "https://$customerDomain" + ":7300/api/v1/inputports"

# Import the contents of the csv into a variable
$data = Import-Csv -Path $csvFilePath -Delimiter $csvDelimiter

# SafeQ Cloud allows for multiple output port entries with the same IP address.  Therefore the following section of code checks the list provided in the CSV and compares it against what already exists in your SQC tenancy.  If the IP address or DNS name of a device exists, then it will skip that line in the CSV and not create either a port or a queue for that device.  It will continue to parse the remaining lines in the csv.  If you intentionally want duplicates to be created, comment out the two blocks of code between the #- Deal with Duplicates -# and #- End Deal with Duplicates-# tags

#- Deal with Duplicates -#
function PortAddressExists($portAddress) {
    $existingPorts = Invoke-RestMethod -Uri $apiOutputPortUrl -Method Get -Headers @{ "X-Api-Key" = $apiKey } -SkipCertificateCheck
    return $existingPorts | Where-Object { $_.address -eq $portAddress }
}
#- End Deal with Duplicates -#

$data | ForEach-Object {

#- Deal with Duplicates -#

    $portAddress = $_.portAddress
    # Check if portAddress already exists
    if (PortAddressExists($portAddress)) {
        Write-Output "Port address $portAddress already exists. Skipping creation."
    }

    else {

#- End Deal with Duplicates -#

# Create an array and store the contents of each switch required for creating the output port

        $body = @()
        $body += "domainname=$customerDomain"
        $body += "portname=$($_.portName)"
        $body += "address=$($_.portAddress)"
        $body += "porttype=1"
        $body += "vendor=$($_.vendor)"
        $body += "printprotocol=$($_.printProtocol)"
        $body += "outputtype=$($_.outputType)"
        $body += "deviceserial=$($_.deviceSerial)"

# Create an array and store the contents of each switch required for creating the input port

        $bodyInputPort = @()
        $bodyInputPort += "domainname=$customerDomain"
        $bodyInputPort += "portname=$($_.portName)"
        $bodyInputPort += "porttype=1"

# Create a string from the contents of both arrays and add a & between switches in order to create something compliant to submit to the API endpoint

        $bodyString = [String]::Join("&", $body)
        $bodyInputPortString = [String]::Join("&", $bodyInputPort)

# Attempt to create the required ports and queues

        try {
            Write-Output "Creating printer port for $($_.portName) : $bodyString"
            # Create the port and store the API response in the $response variable
            $response = Invoke-RestMethod -Uri $apiOutputPortUrl -Method Put -ContentType "application/x-www-form-urlencoded" -Headers @{ "X-Api-Key" = $apiKey } -Body $bodyString -SkipCertificateCheck
            # Extract the port ID into the $responseId variable
            $responseId = $response.id
            # Add the port ID to the bodyInputPort array as an additional parameter
            $bodyInputPortString += "&outputportid=$responseId"
            Write-Output "Printer port for $($_.portName) successfully created"
            Start-Sleep -Seconds 1
            Write-Output "Creating direct print queue for $($_.portName) : $bodyInputPortString"
            # Create the direct print queue for the previously created port
            Invoke-Restmethod -Uri $apiInputPortUrl -Method Put -ContentType "application/x-www-form-urlencoded" -Headers @{ "X-Api-Key" = $apiKey} -Body $bodyInputPortString -SkipCertificateCheck
            Write-Output "Direct print queue for $($_.portName) successfully created"
            Start-Sleep -Seconds 1
        } catch {
            Write-Output "Unable to create $($_.portName): $_"
        }
    }
}