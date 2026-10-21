<#
.SYNOPSIS
    Retrieves and displays the NCM configuration archive directory and its contents, with optional MFA support.
.DESCRIPTION
    Presents a GUI form to enter SolarWinds server details, ensures the Orion SDK Snap-In or module is loaded,
    defines helper functions (Connect-SolarWinds, Get-NCMSetting, Show-Info), connects to SWIS,
    fetches the ConfigArchiveDirectory setting, verifies it exists, and lists archived config files.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Ensure the Orion SDK PowerShell module is available
if (-not (Get-Command Connect-Swis -ErrorAction SilentlyContinue)) {
    try { Import-Module SwisPowerShell -ErrorAction Stop } catch { Import-Module SwisSnapIn -ErrorAction Stop }
}

# Wrapper: connect to SolarWinds SWIS
function Connect-SolarWinds {
    param(
        [Parameter(Mandatory=$true)] [string]$Hostname,
        [Parameter(Mandatory=$true)] [string]$Username,
        [Parameter(Mandatory=$true)] [string]$Password,
        [string]$MfaCode
    )
    if ($PSBoundParameters.ContainsKey('MfaCode')) {
        return Connect-Swis -Hostname $Hostname -Username $Username -Password $Password -MfaCode $MfaCode -ErrorAction Stop
    } else {
        return Connect-Swis -Hostname $Hostname -Username $Username -Password $Password -ErrorAction Stop
    }
}

# Helper: fetch NCM settings via GetSetting verb
function Get-NCMSetting {
    [CmdletBinding()]
    param(
        [string]$SearchTerm   = '*',
        [string]$defaultValue = $null,
        [int]   $engineId     = 2
    )
    $ncmSettings = @('ConfigArchiveDirectory')
    $results = @()
    foreach ($s in $ncmSettings | Where-Object { $_ -like $SearchTerm }) {
        $resp = Invoke-SwisVerb $swis 'Cirrus.Settings' 'GetSetting' @($s, $defaultValue, $engineId) -ErrorAction Stop
        $val  = if ($resp.nil) { '' } else { $resp.InnerXml.Trim() }
        $results += [pscustomobject]@{ Setting = $s; Value = $val }
    }
    return $results
}

# Info popup helper
function Show-Info {
    param(
        [string]$Message,
        [string]$Title = 'Info'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

# Build GUI form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SolarWinds NCM Archive Location'
$form.Size = New-Object System.Drawing.Size(400,320)
$form.StartPosition = 'CenterScreen'

# Hostname
$lblHost = New-Object System.Windows.Forms.Label; $lblHost.Text='Hostname:'; $lblHost.AutoSize=$true; $lblHost.Top=20; $lblHost.Left=10
$txtHost = New-Object System.Windows.Forms.TextBox; $txtHost.Top=20; $txtHost.Left=100; $txtHost.Width=250

# Username
$lblUser = New-Object System.Windows.Forms.Label; $lblUser.Text='Username:'; $lblUser.AutoSize=$true; $lblUser.Top=60; $lblUser.Left=10
$txtUser = New-Object System.Windows.Forms.TextBox; $txtUser.Top=60; $txtUser.Left=100; $txtUser.Width=250

# Password
$lblPass = New-Object System.Windows.Forms.Label; $lblPass.Text='Password:'; $lblPass.AutoSize=$true; $lblPass.Top=100; $lblPass.Left=10
$txtPass = New-Object System.Windows.Forms.TextBox; $txtPass.Top=100; $txtPass.Left=100; $txtPass.Width=250; $txtPass.UseSystemPasswordChar=$true

# MFA checkbox and code
$chkMFA = New-Object System.Windows.Forms.CheckBox; $chkMFA.Text='Use MFA'; $chkMFA.AutoSize=$true; $chkMFA.Top=140; $chkMFA.Left=100
$lblMFA = New-Object System.Windows.Forms.Label; $lblMFA.Text='MFA Code:'; $lblMFA.AutoSize=$true; $lblMFA.Top=180; $lblMFA.Left=10
$txtMFA = New-Object System.Windows.Forms.TextBox; $txtMFA.Top=180; $txtMFA.Left=100; $txtMFA.Width=250; $txtMFA.Enabled=$false
$chkMFA.Add_CheckedChanged({ $txtMFA.Enabled = $chkMFA.Checked })

# Buttons
$btnOK = New-Object System.Windows.Forms.Button; $btnOK.Text='OK'; $btnOK.Width=80; $btnOK.Top=230; $btnOK.Left=180; $btnOK.DialogResult=[System.Windows.Forms.DialogResult]::OK
$btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text='Cancel'; $btnCancel.Width=80; $btnCancel.Top=230; $btnCancel.Left=270; $btnCancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
$form.Controls.AddRange(@($lblHost,$txtHost,$lblUser,$txtUser,$lblPass,$txtPass,$chkMFA,$lblMFA,$txtMFA,$btnOK,$btnCancel))
$form.AcceptButton=$btnOK; $form.CancelButton=$btnCancel

# Show form and gather inputs
if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Show-Info 'Operation cancelled.'; exit 1 }
$Hostname = $txtHost.Text.Trim()
$Username = $txtUser.Text.Trim()
$Password = $txtPass.Text
$UseMFA = $chkMFA.Checked
$MFACode = $txtMFA.Text.Trim()

# Validate inputs
$required = @{ Hostname = $Hostname; Username = $Username; Password = $Password }
foreach ($kvp in $required.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($kvp.Value)) {
        Show-Info "$($kvp.Key) is required."; exit 1
    }
}
if ($UseMFA -and [string]::IsNullOrWhiteSpace($MFACode)) {
    Show-Info 'MFA code is required.'; exit 1
}

# Connect to SWIS
try {
    if ($UseMFA) { $swis = Connect-SolarWinds -Hostname $Hostname -Username $Username -Password $Password -MfaCode $MFACode }
    else { $swis = Connect-SolarWinds -Hostname $Hostname -Username $Username -Password $Password }
} catch {
    Show-Info "❌ Connection failed:`n$_"; exit 1
}

# Fetch the archive directory
$settingInfo = Get-NCMSetting -SearchTerm 'ConfigArchiveDirectory'
$archivePath = ($settingInfo | Where-Object Setting -eq 'ConfigArchiveDirectory').Value
if (-not $archivePath) { Show-Info 'No archive path returned.'; exit 1 }
if (-not (Test-Path $archivePath)) { Show-Info "Path does not exist:`n$archivePath"; exit 1 }

# Display and list archived config files
Show-Info "Archive Directory:`n$archivePath"
$files = Get-ChildItem -Path $archivePath -Filter '*.xml' -ErrorAction Stop
if ($files) { $files | Select-Object FullName,@{n='Date';e={$_.LastWriteTime}} | Out-GridView -Title 'Archived Config Files' }
else { Show-Info "No files found in:`n$archivePath" }
