# Check if PSWriteOffice module is installed
if (!(Get-InstalledModule -Name PSWriteOffice -ErrorAction SilentlyContinue)) {
    try {
        # Attempt to install the module if not found
        Install-Module -Name PSWriteOffice -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "PSWriteOffice module installed successfully."
    }
    catch {
        $installErrorMessage = "Failed to install PSWriteOffice Module."
        Write-L1Log -message $installErrorMessage -severity "FATAL"
        exit
    }
}

try {
    # Attempt to import the module
    Import-Module PSWriteOffice -ErrorAction Stop
    Write-Host "PSWriteOffice module imported successfully."
}
catch {
    $importErrorMessage = "Failed to import PSWriteOffice Module."
    Write-L1Log -message $importErrorMessage -severity "FATAL"
    exit
}

# Verify the module is imported and available
if (Get-Module PSWriteOffice) {
    Write-Host "PSWriteOffice module is available."
} else {
    $moduleAvailabilityMessage = "PSWriteOffice Module is not available even after installation."
    Write-L1Log -message $moduleAvailabilityMessage -severity "FATAL"
}