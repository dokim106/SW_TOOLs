Invoke-WebRequest "https://raw.githubusercontent.com/solarwinds/OrionSDK/master/Samples/PowerShell/functions/func_ModernDashboards.ps1" -OutFile "func_ModernDashboards.ps1"
. .\func_ModernDashboards.ps1
Get-Command -Noun "ModernDashboard"
# Add-Type command to load Windows Forms for OpenFileDialog
Add-Type -AssemblyName System.Windows.Forms

# Import SolarWinds Information Service PowerShell Module
Import-Module SwisPowerShell

# User input for credentials and server hostname
$serverHostname = Read-Host "Enter the SolarWinds Orion server hostname"
$OrionCredentials = Get-Credential -Message "Enter your SolarWinds Orion credentials"
Connect-Swis -Credential $OrionCredentials -Hostname $serverHostname

# Operation selection (export or import)
$operation = Read-Host "Enter 'export' to export a dashboard, 'import' to import a dashboard"

if ($operation -eq "export") {
    # User input for Dashboard ID
    $dashboardId = Read-Host "Please enter the Dashboard ID you want to export"

    # Export Dashboard
    try {
        $exportedDashboard = Get-SwisData $SwisConnection -Query "SELECT Uri, Definition FROM Orion.Dashboards.Instances WHERE Id=@id" -Parameters @{id=$dashboardId}
        $exportFileName = "exported_dashboard_$dashboardId.json"
        $exportedDashboard.Definition | Out-File $exportFileName
        Write-Host "Dashboard exported as $exportFileName"
    } catch {
        Write-Host "An error occurred during export: $_"
    }
}
elseif ($operation -eq "import") {
    # OpenFileDialog for importing dashboard
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "JSON files (*.json)|*.json"

    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $importFilePath = $openFileDialog.FileName

            # Import Dashboard
            $dashboardJson = Get-Content $importFilePath -Raw
            Invoke-SwisVerb $SwisConnection Orion.Dashboards.Instances CreateDashboard $dashboardJson
            Write-Host "Dashboard imported from $importFilePath"
        } catch {
            Write-Host "An error occurred during import: $_"
        }
    }
}
else {
    Write-Host "Invalid operation. Please enter either 'export' or 'import'."
}


