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

# Define the directory to store exported alerts
$exportDirectory = Join-Path -Path $PSScriptRoot -ChildPath "Alerts Exports"

# Check if the directory exists, if not, create it
if (-not (Test-Path -Path $exportDirectory))
{
    New-Item -Path $exportDirectory -ItemType Directory
}
  
# Get all AlertIds, add to array
$AlertList = Get-SwisData $swis "SELECT AlertId FROM Orion.AlertConfigurations WHERE Enabled = True"  
$AlertIds = $AlertList -split ' '  

# Iterate through the AlertIds array, back up each rule found
foreach($alertid in $AlertIds){  
  $alerttitle = Get-SwisData $swis "SELECT Name FROM Orion.AlertConfigurations WHERE AlertId = $alertid"  
  
  # Remove all possible 'special characters' from the alert title
  $alerttitle = $alerttitle -replace '([#|\|"|,|/|:|<|>|\[|\]|%|$|@|?])', ''  
  # Remove all spaces from the alert title, replace with underscore
  $alerttitle = $alerttitle -replace '\s', '_'  
  
  # Define the filename with path to save it in the "Alerts Exports" directory
  $filename = Join-Path -Path $exportDirectory -ChildPath "$alerttitle-ID-$alertid.xml"  
  
  # Export the alert configuration
  $ExportedAlert = Invoke-SwisVerb $swis Orion.AlertConfigurations Export @($alertid)
  
  # Save the exported configuration to a file
  Set-Content -Path $filename -Value $ExportedAlert.InnerText
}

# End script
