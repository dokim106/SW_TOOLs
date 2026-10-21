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
$swis = Connect-Swis -Hostname $hostname -Username $username -Password $plainPasswordBegin

{
    # if no dashboard ids are provided, assume we export them all, so get the list
    if ( ( -not $DashboardId ) -and ( $IncludeSystem ) ) {
        Write-Verbose -Message "EXPORT ALL: No DashboardIds Provided - exporting all (including system dashboards)"
        $Swql = "SELECT DashboardID FROM Orion.Dashboards.Instances WHERE ParentID IS NULL"
        $DashboardId = Get-SwisData -SwisConnection $SwisConnection -Query $Swql
    } elseif ( -not $DashboardId ) {
        Write-Verbose -Message "EXPORT ALL: No DashboardIds Provided - exporting all (excluding system dashboards)"
        $Swql = "SELECT DashboardID FROM Orion.Dashboards.Instances WHERE ParentID IS NULL AND IsSystem = 'FALSE'"
        $DashboardId = Get-SwisData -SwisConnection $SwisConnection -Query $Swql
    }

    # How deep does the Json go?  From initial testing it looks like 25 is sufficient, this gives flexibility
    $JsonDepth = 25
}
Process {
    ForEach ( $d in $DashboardId ) {
        $DashboardText = Invoke-SwisVerb -SwisConnection $SwisConnection -EntityName Orion.Dashboards.Instances -Verb Export -Arguments $d
        
        # The name is stored within the Json file, so we need to load it as Json and interpret it.
        $DashboardObject = $DashboardText.'#text' | ConvertFrom-Json
        $DashboardName = $DashboardObject.dashboards.name
        if ( $DashboardObject.dashboards.unique_key -notmatch '[a-f,0-9]{8}-[a-f,0-9]{4}-[a-f,0-9]{4}-[a-f,0-9]{4}-[a-f,0-9]{12}' ) {
            # This is a system dashboard, so add "SYSTEM" to the name
            $DashboardName = "SYSTEM_$( $DashboardName )"
        }

        $ExportFileName = "$( Remove-InvalidFileNameChars -Name $DashboardName -Replacement "-" ).json"
        if ( $IncludeId ) {
            $ExportFileName = "$( $d )_$ExportFileName"
        }

        $ExportFilePath = Join-Path -Path $OutputFolder -ChildPath $ExportFileName
        
        # Check to see if the export file already exists and we are not forcing overwrite
        if ( ( -not ( Test-Path -Path $ExportFilePath -ErrorAction SilentlyContinue ) ) -or ( $Force ) ) {
            # Ask if we want to export - skip this check by passing '-Confirm:$false'
            if ( $pscmdlet.ShouldProcess("to '$OutputFolder'", "Export '$DashboardName'") ) {
                # Actually do the export
                Write-Verbose -Message "Exporting '$DashboardName'"
                $DashboardObject | ConvertTo-Json -Depth $JsonDepth -Compress:$Compress | Out-File -FilePath $ExportFilePath -Force:$Force
            }
        }
        else {
            Write-Warning -Message "Skipping export of '$DashboardName' because '$ExportFilePath' already exists.  If you wish to overwrite, use the '-Force' parameter."
        }
    }
}
End {
    # nothing to do here
}
}