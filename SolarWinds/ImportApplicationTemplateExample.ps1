# Set up the hostname, username, and password for the system
$hostname = "localhost";
$password = New-Object System.Security.SecureString  #"" | ConvertTo-SecureString -asPlainText -Force
$username = "admin"

# Load SwisPowerShell
Import-Module "C:\Program Files (x86)\SolarWinds\Orion SDK\SWQL Studio\SwisPowerShell"

# Connect to the source system
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$source = Connect-Swis -Credential $credential -Hostname $hostname

# Load applicationTemplate to variable
$applicationTemplate = (gc ".\applicationTemplate.txt" | out-string)

# Import template
$res = Invoke-SwisVerb -Swis $source Orion.APM.ApplicationTemplate ImportTemplate @($applicationTemplate)
$importedId = $res.InnerText

Write-Host "imported template Id: $importedId"