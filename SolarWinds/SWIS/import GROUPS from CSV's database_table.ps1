# Import the necessary module for SolarWinds operations
Import-Module SwisPowerShell

# Prompt for SolarWinds server hostname or IP
$hostname = Read-Host "Enter the hostname or IP address of your SolarWinds server"

# Get credentials
$cred = Get-Credential -Message "Enter your username and password for the SolarWinds server"

# Connect to SWIS
$swis = Connect-Swis -Hostname $hostname -Credential $cred

# Prompt for the CSV file path
$csvFilePath = Read-Host "Enter the full path to the CSV file for importing groups"

# Check if the CSV file exists
if (-not (Test-Path $csvFilePath)) {
    Write-Host "CSV file not found at the specified path: $csvFilePath" -ForegroundColor Red
    exit
}

# Import the groups from the CSV file
$groupsToImport = Import-Csv -Path $csvFilePath

foreach ($group in $groupsToImport) {
    # Since ContainerID is typically a system-assigned value, we'll ignore it during creation.
    # The Owner is assumed to be 'Core' for group creation purposes unless specified otherwise in your CSV.

    # Default XML for groups without predefined members
    $emptyMembersXml = ([xml]"<ArrayOfMemberDefinitionInfo xmlns='http://schemas.solarwinds.com/2008/Orion' />").DocumentElement

    # Create the group in SolarWinds
    $groupId = (Invoke-SwisVerb $swis "Orion.Container" "CreateContainer" @(
        $group.Name,
        $group.Owner, # Assuming 'Owner' column exists and contains 'Core' or appropriate owner name
        60, # Assuming a default Refresh Frequency
        0, # Assuming a default Status Rollup Mode of 'Mixed status shows warning'
        $group.Description,
        $group.PollingEnabled,
        $emptyMembersXml # No group members are defined in the CSV
    )).InnerText

    Write-Host "Group `"$($group.Name)`" created with ID: $groupId" -ForegroundColor Green
}

Write-Host "All groups have been imported successfully." -ForegroundColor Green
