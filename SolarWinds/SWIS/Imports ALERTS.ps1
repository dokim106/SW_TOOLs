# Verify OrionSDK SwisSnapin presence  
if (!(Get-PSSnapin -Name "SwisSnapin" -ErrorAction SilentlyContinue))
{        
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

# Define Variables  
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $plainPassword

# Automatically set the directory containing alert XML files
$xmlDirectory = Join-Path -Path $PSScriptRoot -ChildPath "AlertExports"

# Verify if the directory exists
if (-not (Test-Path -Path $xmlDirectory))
{
    Write-Host "Directory not found: $xmlDirectory. Please ensure the 'AlertExports' folder exists in the same directory as this script."
    exit
}

# Get all XML files in the specified directory
$xmlFiles = Get-ChildItem -Path $xmlDirectory -Filter "*.xml"

# Check if there are any XML files found
if ($xmlFiles.Count -eq 0)
{
    Write-Host "No XML files found in the directory: $xmlDirectory"
    exit
}

# Import each alert configuration
foreach ($file in $xmlFiles) {
    $filePath = $file.FullName
    $AlertXml = Get-Content $filePath -Raw
    try {
        $importResult = Invoke-SwisVerb $swis Orion.AlertConfigurations Import @($AlertXml)
        Write-Host "Successfully imported alert from file: $($file.Name)"
    } catch {
        Write-Host "Failed to import alert from file: $($file.Name). Error: $_"
    }
}

Write-Host "Import process completed."
