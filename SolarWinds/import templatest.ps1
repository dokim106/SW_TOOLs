# Ensure the presence of the OrionSDK SwisSnapin
if (!(Get-PSSnapin -Name "SwisSnapin" -ErrorAction SilentlyContinue)) {
    Add-PSSnapin SwisSnapin -ErrorAction SilentlyContinue    
}

# Prompt user for Orion server details
$hostname = Read-Host "Enter the hostname or IP address of the Orion server"
$username = Read-Host "Enter the username"
$password = Read-Host "Enter the password" -AsSecureString

# Convert the secure string password to a plain text string for the connection
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($password)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)

# Establish connection to SolarWinds
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $plainPassword

# Setting a default value for DirectoryPath to use if not provided as a parameter
Param(
    [string]$DirectoryPath = [Environment]::GetFolderPath("Desktop") + "\SolarWindsImports"
)

# Setup logging
if (-not (Test-Path -Path $DirectoryPath)) {
    New-Item -ItemType Directory -Force -Path $DirectoryPath
}
$Logfile = Join-Path -Path $DirectoryPath -ChildPath "ImportLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $Logfile -Append -IncludeInvocationHeader

try {
    # Retrieve all XML files in the specified directory
    $xmlFiles = Get-ChildItem -Path $DirectoryPath -Filter "*.xml"
    
    foreach ($file in $xmlFiles) {
        $filePath = $file.FullName
        Write-Host "Importing template from file: $filePath"
        
        # Load the XML content from the file
        $xmlContent = Get-Content -Path $filePath -Raw
        
        # Placeholder for the actual import command. Replace with your specific command.
        # Example: invoke-swisverb $swis "orion.apm.applicationtemplate" "ImportTemplate" $xmlContent
        Write-Host "Assuming import of `$xmlContent` to SolarWinds. Replace this line with actual import command."
    }
} catch {
    Write-Error "An error occurred: $_"
} finally {
    Stop-Transcript
}

# Reminder to replace the placeholder import command with the actual command suitable for your environment.
