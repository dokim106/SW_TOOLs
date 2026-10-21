# Requires SwisPowerShell Module v3.0+

function Import-AllModernDashboards {
    [CmdletBinding()]
    Param()

    Begin {
        # Set the input folder to "ExportDashboard" in the current directory
        $InputFolder = Join-Path -Path (Get-Location) -ChildPath "ExportDashboard"

        # Check if the input folder exists
        if (-not (Test-Path -Path $InputFolder)) {
            Write-Error "Input folder '$InputFolder' does not exist."
            return
        }

        # Prompt for server address, username, and password
        $serverAddress = Read-Host -Prompt "Enter the SolarWinds server address"
        $credential = Get-Credential -Message "Enter your username and password for SolarWinds"

        # Establish connection to SWIS
        try {
            $SwisConnection = Connect-Swis -Hostname $serverAddress -Credential $credential
        } catch {
            Write-Error "Failed to connect to SolarWinds Information Service. Error: $_"
            return
        }
    }

    Process {
        # Get all JSON files in the input folder
        $dashboardFiles = Get-ChildItem -Path $InputFolder -Filter "*.json"

        if ($dashboardFiles.Count -eq 0) {
            Write-Warning "No JSON files found in '$InputFolder'."
            return
        }

        # Import each dashboard
        foreach ($file in $dashboardFiles) {
            try {
                $dashboardJsonContent = Get-Content -Path $file.FullName -Raw
                $dashboardJson = $dashboardJsonContent | ConvertFrom-Json
                $dashboardName = $dashboardJson.dashboards.name

                # Import dashboard
                Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName "Orion.Dashboards.Instances" -Verb "Import" -Arguments ($dashboardJsonContent)
                Write-Host "Successfully imported dashboard '$dashboardName' from file '$($file.Name)'."
            } catch {
                Write-Error "Failed to import dashboard from file '$($file.Name)'. Error: $_"
            }
        }
    }

    End {
        Write-Host "Completed importing all Modern Dashboards from '$InputFolder'."
    }
}

# Execute the function to import all dashboards from the "ExportDashboard" folder
Import-AllModernDashboards
