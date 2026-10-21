# dev

function Export-AllModernDashboards {
    [CmdletBinding()]
    Param()

    Begin {
        # Set the output folder to "ExportDashboard" in the current directory
        $OutputFolder = Join-Path -Path (Get-Location) -ChildPath "ExportDashboard"
        
        # Check if the output folder exists, if not, create it
        if (-not (Test-Path -Path $OutputFolder)) {
            New-Item -Path $OutputFolder -ItemType Directory | Out-Null
            Write-Host "Created output folder '$OutputFolder'"
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
        try {
            # Query to select all dashboard IDs
            $Swql = "SELECT DashboardID FROM Orion.Dashboards.Instances WHERE ParentID IS NULL"
            $DashboardIds = Get-SwisData -SwisConnection $SwisConnection -Query $Swql

            # Export each dashboard
            foreach ($id in $DashboardIds) {
                $dashboardData = Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName "Orion.Dashboards.Instances" -Verb "Export" -Arguments $id
                $dashboardObject = $dashboardData.'#text' | ConvertFrom-Json
                $dashboardName = $dashboardObject.dashboards.name
                
                # Sanitize the dashboard name to be used as filename
                $safeName = $dashboardName -replace '[\\/:*?"<>|]', '-'
                $fileName = "$safeName.json"
                $filePath = Join-Path -Path $OutputFolder -ChildPath $fileName

                # Export to file
                $dashboardObject | ConvertTo-Json -Depth 25 | Out-File -FilePath $filePath
                Write-Host "Exported dashboard '$dashboardName' to '$filePath'"
            }
        } catch {
            Write-Error "An error occurred while exporting dashboards. Error: $_"
        }
    }

    End {
        Write-Host "Completed exporting all Modern Dashboards to '$OutputFolder'."
    }
}

# Execute the function to export all dashboards to the "ExportDashboard" folder
Export-AllModernDashboards
