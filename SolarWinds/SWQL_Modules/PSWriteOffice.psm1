# Get library name, from the PSM1 file name
$LibraryName = 'PSWriteOffice'
$Library = "$LibraryName.dll"
$Class = "$LibraryName.Initialize"

$AssemblyFolders = Get-ChildItem -Path $PSScriptRoot\Lib -Directory -ErrorAction SilentlyContinue

# Lets find which libraries we need to load
$Default = $false
$Core = $false
$Standard = $false
foreach ($A in $AssemblyFolders.Name) {
    if ($A -eq 'Default') {
        $Default = $true
    }
    elseif ($A -eq 'Core') {
        $Core = $true
    }
    elseif ($A -eq 'Standard') {
        $Standard = $true
    }
}
if ($Standard -and $Core -and $Default) {
    $FrameworkNet = 'Default'
    $Framework = 'Standard'
}
elseif ($Standard -and $Core) {
    $Framework = 'Standard'
    $FrameworkNet = 'Standard'
}
elseif ($Core -and $Default) {
    $Framework = 'Core'
    $FrameworkNet = 'Default'
}
elseif ($Standard -and $Default) {
    $Framework = 'Standard'
    $FrameworkNet = 'Default'
}
elseif ($Standard) {
    $Framework = 'Standard'
    $FrameworkNet = 'Standard'
}
elseif ($Core) {
    $Framework = 'Core'
    $FrameworkNet = ''
}
elseif ($Default) {
    $Framework = ''
    $FrameworkNet = 'Default'
}
else {
    Write-Error -Message 'No assemblies found'
}
if ($PSEdition -eq 'Core') {
    $LibFolder = $Framework
}
else {
    $LibFolder = $FrameworkNet
}

try {
    $ImportModule = Get-Command -Name Import-Module -Module Microsoft.PowerShell.Core

    if (-not ($Class -as [type])) {
        & $ImportModule ([IO.Path]::Combine($PSScriptRoot, 'Lib', $LibFolder, $Library)) -ErrorAction Stop
    }
    else {
        $Type = "$Class" -as [Type]
        & $importModule -Force -Assembly ($Type.Assembly)
    }
}
catch {
    if ($ErrorActionPreference -eq 'Stop') {
        throw
    }
    else {
        Write-Warning -Message "Importing module $Library failed. Fix errors before continuing. Error: $($_.Exception.Message)"
        # we will continue, but it's not a good idea to do so
        # return
    }
}
# Dot source all libraries by loading external file
. $PSScriptRoot\PSWriteOffice.Libraries.ps1

function ConvertFrom-Color { 
    [alias('Convert-FromColor')]
    [CmdletBinding()]
    param (
        [ValidateScript( {
                if ($($_ -in $Script:RGBColors.Keys -or $_ -match "^#([A-Fa-f0-9]{6})$" -or $_ -eq "") -eq $false) {
                    throw "The Input value is not a valid colorname nor an valid color hex code."
                }
                else {
                    $true 
                }
            })]
        [alias('Colors')][string[]] $Color,
        [switch] $AsDecimal,
        [switch] $AsDrawingColor
    )
    $Colors = foreach ($C in $Color) {
        $Value = $Script:RGBColors."$C"
        if ($C -match "^#([A-Fa-f0-9]{6})$") {
            $C
            continue
        }
        if ($null -eq $Value) {
            continue
        }
        $HexValue = Convert-Color -RGB $Value
        Write-Verbose "Convert-FromColor - Color Name: $C Value: $Value HexValue: $HexValue"
        if ($AsDecimal) {
            [Convert]::ToInt64($HexValue, 16)
        }
        elseif ($AsDrawingColor) {
            [System.Drawing.Color]::FromArgb("#$($HexValue)")
        }
        else {
            "#$($HexValue)"
        }
    }
    $Colors
}
function Get-FileName { 
    <#
    .SYNOPSIS
    Short description

    .DESCRIPTION
    Long description

    .PARAMETER Extension
    Parameter description

    .PARAMETER Temporary
    Parameter description

    .PARAMETER TemporaryFileOnly
    Parameter description

    .EXAMPLE
    Get-FileName -Temporary
    Output: 3ymsxvav.tmp

    .EXAMPLE

    Get-FileName -Temporary
    Output: C:\Users\pklys\AppData\Local\Temp\tmpD74C.tmp

    .EXAMPLE

    Get-FileName -Temporary -Extension 'xlsx'
    Output: C:\Users\pklys\AppData\Local\Temp\tmp45B6.xlsx

    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param(
        [string] $Extension = 'tmp',
        [switch] $Temporary,
        [switch] $TemporaryFileOnly
    )

    if ($Temporary) {

        return [io.path]::Combine([System.IO.Path]::GetTempPath(), "$($([System.IO.Path]::GetRandomFileName()).Split('.')[0]).$Extension")
    }
    if ($TemporaryFileOnly) {

        return "$($([System.IO.Path]::GetRandomFileName()).Split('.')[0]).$Extension"
    }
}
function Get-RandomStringName { 
    [cmdletbinding()]
    param(
        [int] $Size = 31,
        [switch] $ToLower,
        [switch] $ToUpper,
        [switch] $LettersOnly
    )
    [string] $MyValue = @(
        if ($LettersOnly) {
            ( -join ((1..$Size) | ForEach-Object { (65..90) + (97..122) | Get-Random } | ForEach-Object { [char]$_ }))
        }
        else {
            ( -join ((48..57) + (97..122) | Get-Random -Count $Size | ForEach-Object { [char]$_ }))
        }
    )
    if ($ToLower) {
        return $MyValue.ToLower()
    }
    if ($ToUpper) {
        return $MyValue.ToUpper()
    }
    return $MyValue
}
function Remove-EmptyValue { 
    [alias('Remove-EmptyValues')]
    [CmdletBinding()]
    param(
        [alias('Splat', 'IDictionary')][Parameter(Mandatory)][System.Collections.IDictionary] $Hashtable,
        [string[]] $ExcludeParameter,
        [switch] $Recursive,
        [int] $Rerun,
        [switch] $DoNotRemoveNull,
        [switch] $DoNotRemoveEmpty,
        [switch] $DoNotRemoveEmptyArray,
        [switch] $DoNotRemoveEmptyDictionary
    )
    foreach ($Key in [string[]] $Hashtable.Keys) {
        if ($Key -notin $ExcludeParameter) {
            if ($Recursive) {
                if ($Hashtable[$Key] -is [System.Collections.IDictionary]) {
                    if ($Hashtable[$Key].Count -eq 0) {
                        if (-not $DoNotRemoveEmptyDictionary) {
                            $Hashtable.Remove($Key)
                        }
                    }
                    else {
                        Remove-EmptyValue -Hashtable $Hashtable[$Key] -Recursive:$Recursive
                    }
                }
                else {
                    if (-not $DoNotRemoveNull -and $null -eq $Hashtable[$Key]) {
                        $Hashtable.Remove($Key)
                    }
                    elseif (-not $DoNotRemoveEmpty -and $Hashtable[$Key] -is [string] -and $Hashtable[$Key] -eq '') {
                        $Hashtable.Remove($Key)
                    }
                    elseif (-not $DoNotRemoveEmptyArray -and $Hashtable[$Key] -is [System.Collections.IList] -and $Hashtable[$Key].Count -eq 0) {
                        $Hashtable.Remove($Key)
                    }
                }
            }
            else {
                if (-not $DoNotRemoveNull -and $null -eq $Hashtable[$Key]) {
                    $Hashtable.Remove($Key)
                }
                elseif (-not $DoNotRemoveEmpty -and $Hashtable[$Key] -is [string] -and $Hashtable[$Key] -eq '') {
                    $Hashtable.Remove($Key)
                }
                elseif (-not $DoNotRemoveEmptyArray -and $Hashtable[$Key] -is [System.Collections.IList] -and $Hashtable[$Key].Count -eq 0) {
                    $Hashtable.Remove($Key)
                }
            }
        }
    }
    if ($Rerun) {
        for ($i = 0; $i -lt $Rerun; $i++) {
            Remove-EmptyValue -Hashtable $Hashtable -Recursive:$Recursive
        }
    }
}
function Select-Properties { 
    <#
    .SYNOPSIS
    Allows for easy selecting property names from one or multiple objects

    .DESCRIPTION
    Allows for easy selecting property names from one or multiple objects. This is especially useful with using AllProperties parameter where we want to make sure to get all properties from all objects.

    .PARAMETER Objects
    One or more objects

    .PARAMETER Property
    Properties to include

    .PARAMETER ExcludeProperty
    Properties to exclude

    .PARAMETER AllProperties
    All unique properties from all objects

    .PARAMETER PropertyNameReplacement
    Default property name when object has no properties

    .EXAMPLE
    $Object1 = [PSCustomobject] @{
        Name1 = '1'
        Name2 = '3'
        Name3 = '5'
    }
    $Object2 = [PSCustomobject] @{
        Name4 = '2'
        Name5 = '6'
        Name6 = '7'
    }

    Select-Properties -Objects $Object1, $Object2 -AllProperties

    #OR:

    $Object1, $Object2 | Select-Properties -AllProperties -ExcludeProperty Name6 -Property Name3

    .EXAMPLE
    $Object3 = [Ordered] @{
        Name1 = '1'
        Name2 = '3'
        Name3 = '5'
    }
    $Object4 = [Ordered] @{
        Name4 = '2'
        Name5 = '6'
        Name6 = '7'
    }

    Select-Properties -Objects $Object3, $Object4 -AllProperties

    $Object3, $Object4 | Select-Properties -AllProperties

    .NOTES
    General notes
    #>
    [CmdLetBinding()]
    param(
        [Array][Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)] $Objects,
        [string[]] $Property,
        [string[]] $ExcludeProperty,
        [switch] $AllProperties,
        [string] $PropertyNameReplacement = '*'
    )
    Begin {
        function Select-Unique {
            [CmdLetBinding()]
            param(
                [System.Collections.IList] $Object
            )
            [Array] $CleanedList = foreach ($O in $Object) {
                if ($null -ne $O) {
                    $O
                }
            }
            $New = $CleanedList.ToLower() | Select-Object -Unique
            $Selected = foreach ($_ in $New) {
                $Index = $Object.ToLower().IndexOf($_)
                if ($Index -ne -1) {
                    $Object[$Index]
                }
            }
            $Selected
        }
        $ObjectsList = [System.Collections.Generic.List[Object]]::new()
    }
    Process {
        foreach ($Object in $Objects) {
            $ObjectsList.Add($Object)
        }
    }
    End {
        if ($ObjectsList.Count -eq 0) {
            Write-Warning 'Select-Properties - Unable to process. Objects count equals 0.'
            return
        }
        if ($ObjectsList[0] -is [System.Collections.IDictionary]) {
            if ($AllProperties) {
                [Array] $All = foreach ($_ in $ObjectsList) {
                    $_.Keys
                }

                $FirstObjectProperties = Select-Unique -Object $All
            }
            else {
                $FirstObjectProperties = $ObjectsList[0].Keys
            }
            if ($Property.Count -gt 0 -and $ExcludeProperty.Count -gt 0) {

                $FirstObjectProperties = foreach ($_ in $FirstObjectProperties) {
                    if ($Property -contains $_ -and $ExcludeProperty -notcontains $_) {
                        $_
                        continue
                    }
                }
            }
            elseif ($Property.Count -gt 0) {

                $FirstObjectProperties = foreach ($_ in $FirstObjectProperties) {
                    if ($Property -contains $_) {
                        $_
                        continue
                    }
                }
            }
            elseif ($ExcludeProperty.Count -gt 0) {

                $FirstObjectProperties = foreach ($_ in $FirstObjectProperties) {
                    if ($ExcludeProperty -notcontains $_) {
                        $_
                        continue
                    }
                }
            }
        }
        elseif ($ObjectsList[0].GetType().Name -match 'bool|byte|char|datetime|decimal|double|ExcelHyperLink|float|int|long|sbyte|short|string|timespan|uint|ulong|URI|ushort') {
            $FirstObjectProperties = $PropertyNameReplacement
        }
        else {
            if ($Property.Count -gt 0 -and $ExcludeProperty.Count -gt 0) {
                $ObjectsList = $ObjectsList | Select-Object -Property $Property -ExcludeProperty $ExcludeProperty
            }
            elseif ($Property.Count -gt 0) {
                $ObjectsList = $ObjectsList | Select-Object -Property $Property 
            }
            elseif ($ExcludeProperty.Count -gt 0) {
                $ObjectsList = $ObjectsList | Select-Object -Property '*' -ExcludeProperty $ExcludeProperty
            }
            if ($AllProperties) {
                [Array] $All = foreach ($_ in $ObjectsList) {
                    $ListProperties = $_.PSObject.Properties.Name
                    if ($null -ne $ListProperties) {
                        $ListProperties
                    }
                }

                $FirstObjectProperties = Select-Unique -Object $All
            }
            else {
                $FirstObjectProperties = $ObjectsList[0].PSObject.Properties.Name
            }
        }
        $FirstObjectProperties
    }
}
function Convert-Color { 
    <#
    .Synopsis
    This color converter gives you the hexadecimal values of your RGB colors and vice versa (RGB to HEX)
    .Description
    This color converter gives you the hexadecimal values of your RGB colors and vice versa (RGB to HEX). Use it to convert your colors and prepare your graphics and HTML web pages.
    .Parameter RBG
    Enter the Red Green Blue value comma separated. Red: 51 Green: 51 Blue: 204 for example needs to be entered as 51,51,204
    .Parameter HEX
    Enter the Hex value to be converted. Do not use the '#' symbol. (Ex: 3333CC converts to Red: 51 Green: 51 Blue: 204)
    .Example
    .\convert-color -hex FFFFFF
    Converts hex value FFFFFF to RGB

    .Example
    .\convert-color -RGB 123,200,255
    Converts Red = 123 Green = 200 Blue = 255 to Hex value

    #>
    param(
        [Parameter(ParameterSetName = "RGB", Position = 0)]
        [ValidateScript( { $_ -match '^([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$' })]
        $RGB,
        [Parameter(ParameterSetName = "HEX", Position = 0)]
        [ValidateScript( { $_ -match '[A-Fa-f0-9]{6}' })]
        [string]
        $HEX
    )
    switch ($PsCmdlet.ParameterSetName) {
        "RGB" {
            if ($null -eq $RGB[2]) {
                Write-Error "Value missing. Please enter all three values seperated by comma."
            }
            $red = [convert]::Tostring($RGB[0], 16)
            $green = [convert]::Tostring($RGB[1], 16)
            $blue = [convert]::Tostring($RGB[2], 16)
            if ($red.Length -eq 1) {
                $red = '0' + $red
            }
            if ($green.Length -eq 1) {
                $green = '0' + $green
            }
            if ($blue.Length -eq 1) {
                $blue = '0' + $blue
            }
            Write-Output $red$green$blue
        }
        "HEX" {
            $red = $HEX.Remove(2, 4)
            $Green = $HEX.Remove(4, 2)
            $Green = $Green.remove(0, 2)
            $Blue = $hex.Remove(0, 4)
            $Red = [convert]::ToInt32($red, 16)
            $Green = [convert]::ToInt32($green, 16)
            $Blue = [convert]::ToInt32($blue, 16)
            Write-Output $red, $Green, $blue
        }
    }
}
$Script:RGBColors = [ordered] @{
    None                   = $null
    AirForceBlue           = 93, 138, 168
    Akaroa                 = 195, 176, 145
    AlbescentWhite         = 227, 218, 201
    AliceBlue              = 240, 248, 255
    Alizarin               = 227, 38, 54
    Allports               = 18, 97, 128
    Almond                 = 239, 222, 205
    AlmondFrost            = 159, 129, 112
    Amaranth               = 229, 43, 80
    Amazon                 = 59, 122, 87
    Amber                  = 255, 191, 0
    Amethyst               = 153, 102, 204
    AmethystSmoke          = 156, 138, 164
    AntiqueWhite           = 250, 235, 215
    Apple                  = 102, 180, 71
    AppleBlossom           = 176, 92, 82
    Apricot                = 251, 206, 177
    Aqua                   = 0, 255, 255
    Aquamarine             = 127, 255, 212
    Armygreen              = 75, 83, 32
    Arsenic                = 59, 68, 75
    Astral                 = 54, 117, 136
    Atlantis               = 164, 198, 57
    Atomic                 = 65, 74, 76
    AtomicTangerine        = 255, 153, 102
    Axolotl                = 99, 119, 91
    Azure                  = 240, 255, 255
    Bahia                  = 176, 191, 26
    BakersChocolate        = 93, 58, 26
    BaliHai                = 124, 152, 171
    BananaMania            = 250, 231, 181
    BattleshipGrey         = 85, 93, 80
    BayOfMany              = 35, 48, 103
    Beige                  = 245, 245, 220
    Bermuda                = 136, 216, 192
    Bilbao                 = 42, 128, 0
    BilobaFlower           = 181, 126, 220
    Bismark                = 83, 104, 114
    Bisque                 = 255, 228, 196
    Bistre                 = 61, 43, 31
    Bittersweet            = 254, 111, 94
    Black                  = 0, 0, 0
    BlackPearl             = 31, 38, 42
    BlackRose              = 85, 31, 47
    BlackRussian           = 23, 24, 43
    BlanchedAlmond         = 255, 235, 205
    BlizzardBlue           = 172, 229, 238
    Blue                   = 0, 0, 255
    BlueDiamond            = 77, 26, 127
    BlueMarguerite         = 115, 102, 189
    BlueSmoke              = 115, 130, 118
    BlueViolet             = 138, 43, 226
    Blush                  = 169, 92, 104
    BokaraGrey             = 22, 17, 13
    Bole                   = 121, 68, 59
    BondiBlue              = 0, 147, 175
    Bordeaux               = 88, 17, 26
    Bossanova              = 86, 60, 92
    Boulder                = 114, 116, 114
    Bouquet                = 183, 132, 167
    Bourbon                = 170, 108, 57
    Brass                  = 181, 166, 66
    BrickRed               = 199, 44, 72
    BrightGreen            = 102, 255, 0
    BrightRed              = 146, 43, 62
    BrightTurquoise        = 8, 232, 222
    BrilliantRose          = 243, 100, 162
    BrinkPink              = 250, 110, 121
    BritishRacingGreen     = 0, 66, 37
    Bronze                 = 205, 127, 50
    Brown                  = 165, 42, 42
    BrownPod               = 57, 24, 2
    BuddhaGold             = 202, 169, 6
    Buff                   = 240, 220, 130
    Burgundy               = 128, 0, 32
    BurlyWood              = 222, 184, 135
    BurntOrange            = 255, 117, 56
    BurntSienna            = 233, 116, 81
    BurntUmber             = 138, 51, 36
    ButteredRum            = 156, 124, 56
    CadetBlue              = 95, 158, 160
    California             = 224, 141, 60
    CamouflageGreen        = 120, 134, 107
    Canary                 = 255, 255, 153
    CanCan                 = 217, 134, 149
    CannonPink             = 145, 78, 117
    CaputMortuum           = 89, 39, 32
    Caramel                = 255, 213, 154
    Cararra                = 237, 230, 214
    Cardinal               = 179, 33, 52
    CardinGreen            = 18, 53, 36
    CareysPink             = 217, 152, 160
    CaribbeanGreen         = 0, 222, 164
    Carmine                = 175, 0, 42
    CarnationPink          = 255, 166, 201
    CarrotOrange           = 242, 142, 28
    Cascade                = 141, 163, 153
    CatskillWhite          = 226, 229, 222
    Cedar                  = 67, 48, 46
    Celadon                = 172, 225, 175
    Celeste                = 207, 207, 196
    Cello                  = 55, 79, 107
    Cement                 = 138, 121, 93
    Cerise                 = 222, 49, 99
    Cerulean               = 0, 123, 167
    CeruleanBlue           = 42, 82, 190
    Chantilly              = 239, 187, 204
    Chardonnay             = 255, 200, 124
    Charlotte              = 167, 216, 222
    Charm                  = 208, 116, 139
    Chartreuse             = 127, 255, 0
    ChartreuseYellow       = 223, 255, 0
    ChelseaCucumber        = 135, 169, 107
    Cherub                 = 246, 214, 222
    Chestnut               = 185, 78, 72
    ChileanFire            = 226, 88, 34
    Chinook                = 150, 200, 162
    Chocolate              = 210, 105, 30
    Christi                = 125, 183, 0
    Christine              = 181, 101, 30
    Cinnabar               = 235, 76, 66
    Citron                 = 159, 169, 31
    Citrus                 = 141, 182, 0
    Claret                 = 95, 25, 51
    ClassicRose            = 251, 204, 231
    ClayCreek              = 145, 129, 81
    Clinker                = 75, 54, 33
    Clover                 = 74, 93, 35
    Cobalt                 = 0, 71, 171
    CocoaBrown             = 44, 22, 8
    Cola                   = 60, 48, 36
    ColumbiaBlue           = 166, 231, 255
    CongoBrown             = 103, 76, 71
    Conifer                = 178, 236, 93
    Copper                 = 218, 138, 103
    CopperRose             = 153, 102, 102
    Coral                  = 255, 127, 80
    CoralRed               = 255, 64, 64
    CoralTree              = 173, 111, 105
    Coriander              = 188, 184, 138
    Corn                   = 251, 236, 93
    CornField              = 250, 240, 190
    Cornflower             = 147, 204, 234
    CornflowerBlue         = 100, 149, 237
    Cornsilk               = 255, 248, 220
    Cosmic                 = 132, 63, 91
    Cosmos                 = 255, 204, 203
    CostaDelSol            = 102, 93, 30
    CottonCandy            = 255, 188, 217
    Crail                  = 164, 90, 82
    Cranberry              = 205, 96, 126
    Cream                  = 255, 255, 204
    CreamCan               = 242, 198, 73
    Crimson                = 220, 20, 60
    Crusta                 = 232, 142, 90
    Cumulus                = 255, 255, 191
    Cupid                  = 246, 173, 198
    CuriousBlue            = 40, 135, 200
    Cyan                   = 0, 255, 255
    Cyprus                 = 6, 78, 64
    DaisyBush              = 85, 53, 146
    Dandelion              = 250, 218, 94
    Danube                 = 96, 130, 182
    DarkBlue               = 0, 0, 139
    DarkBrown              = 101, 67, 33
    DarkCerulean           = 8, 69, 126
    DarkChestnut           = 152, 105, 96
    DarkCoral              = 201, 90, 73
    DarkCyan               = 0, 139, 139
    DarkGoldenrod          = 184, 134, 11
    DarkGray               = 169, 169, 169
    DarkGreen              = 0, 100, 0
    DarkGreenCopper        = 73, 121, 107
    DarkGrey               = 169, 169, 169
    DarkKhaki              = 189, 183, 107
    DarkMagenta            = 139, 0, 139
    DarkOliveGreen         = 85, 107, 47
    DarkOrange             = 255, 140, 0
    DarkOrchid             = 153, 50, 204
    DarkPastelGreen        = 3, 192, 60
    DarkPink               = 222, 93, 131
    DarkPurple             = 150, 61, 127
    DarkRed                = 139, 0, 0
    DarkSalmon             = 233, 150, 122
    DarkSeaGreen           = 143, 188, 143
    DarkSlateBlue          = 72, 61, 139
    DarkSlateGray          = 47, 79, 79
    DarkSlateGrey          = 47, 79, 79
    DarkSpringGreen        = 23, 114, 69
    DarkTangerine          = 255, 170, 29
    DarkTurquoise          = 0, 206, 209
    DarkViolet             = 148, 0, 211
    DarkWood               = 130, 102, 68
    DeepBlush              = 245, 105, 145
    DeepCerise             = 224, 33, 138
    DeepKoamaru            = 51, 51, 102
    DeepLilac              = 153, 85, 187
    DeepMagenta            = 204, 0, 204
    DeepPink               = 255, 20, 147
    DeepSea                = 14, 124, 97
    DeepSkyBlue            = 0, 191, 255
    DeepTeal               = 24, 69, 59
    Denim                  = 36, 107, 206
    DesertSand             = 237, 201, 175
    DimGray                = 105, 105, 105
    DimGrey                = 105, 105, 105
    DodgerBlue             = 30, 144, 255
    Dolly                  = 242, 242, 122
    Downy                  = 95, 201, 191
    DutchWhite             = 239, 223, 187
    EastBay                = 76, 81, 109
    EastSide               = 178, 132, 190
    EchoBlue               = 169, 178, 195
    Ecru                   = 194, 178, 128
    Eggplant               = 162, 0, 109
    EgyptianBlue           = 16, 52, 166
    ElectricBlue           = 125, 249, 255
    ElectricIndigo         = 111, 0, 255
    ElectricLime           = 208, 255, 20
    ElectricPurple         = 191, 0, 255
    Elm                    = 47, 132, 124
    Emerald                = 80, 200, 120
    Eminence               = 108, 48, 130
    Endeavour              = 46, 88, 148
    EnergyYellow           = 245, 224, 80
    Espresso               = 74, 44, 42
    Eucalyptus             = 26, 162, 96
    Falcon                 = 126, 94, 96
    Fallow                 = 204, 153, 102
    FaluRed                = 128, 24, 24
    Feldgrau               = 77, 93, 83
    Feldspar               = 205, 149, 117
    Fern                   = 113, 188, 120
    FernGreen              = 79, 121, 66
    Festival               = 236, 213, 64
    Finn                   = 97, 64, 81
    FireBrick              = 178, 34, 34
    FireBush               = 222, 143, 78
    FireEngineRed          = 211, 33, 45
    Flamingo               = 233, 92, 75
    Flax                   = 238, 220, 130
    FloralWhite            = 255, 250, 240
    ForestGreen            = 34, 139, 34
    Frangipani             = 250, 214, 165
    FreeSpeechAquamarine   = 0, 168, 119
    FreeSpeechRed          = 204, 0, 0
    FrenchLilac            = 230, 168, 215
    FrenchRose             = 232, 83, 149
    FriarGrey              = 135, 134, 129
    Froly                  = 228, 113, 122
    Fuchsia                = 255, 0, 255
    FuchsiaPink            = 255, 119, 255
    Gainsboro              = 220, 220, 220
    Gallery                = 219, 215, 210
    Galliano               = 204, 160, 29
    Gamboge                = 204, 153, 0
    Ghost                  = 196, 195, 208
    GhostWhite             = 248, 248, 255
    Gin                    = 216, 228, 188
    GinFizz                = 247, 231, 206
    Givry                  = 230, 208, 171
    Glacier                = 115, 169, 194
    Gold                   = 255, 215, 0
    GoldDrop               = 213, 108, 43
    GoldenBrown            = 150, 113, 23
    GoldenFizz             = 240, 225, 48
    GoldenGlow             = 248, 222, 126
    GoldenPoppy            = 252, 194, 0
    Goldenrod              = 218, 165, 32
    GoldenSand             = 233, 214, 107
    GoldenYellow           = 253, 238, 0
    GoldTips               = 225, 189, 39
    GordonsGreen           = 37, 53, 41
    Gorse                  = 255, 225, 53
    Gossamer               = 49, 145, 119
    GrannySmithApple       = 168, 228, 160
    Gray                   = 128, 128, 128
    GrayAsparagus          = 70, 89, 69
    Green                  = 0, 128, 0
    GreenLeaf              = 76, 114, 29
    GreenVogue             = 38, 67, 72
    GreenYellow            = 173, 255, 47
    Grey                   = 128, 128, 128
    GreyAsparagus          = 70, 89, 69
    GuardsmanRed           = 157, 41, 51
    GumLeaf                = 178, 190, 181
    Gunmetal               = 42, 52, 57
    Hacienda               = 155, 135, 12
    HalfAndHalf            = 232, 228, 201
    HalfBaked              = 95, 138, 139
    HalfColonialWhite      = 246, 234, 190
    HalfPearlLusta         = 240, 234, 214
    HanPurple              = 63, 0, 255
    Harlequin              = 74, 255, 0
    HarleyDavidsonOrange   = 194, 59, 34
    Heather                = 174, 198, 207
    Heliotrope             = 223, 115, 255
    Hemp                   = 161, 122, 116
    Highball               = 134, 126, 54
    HippiePink             = 171, 75, 82
    Hoki                   = 110, 127, 128
    HollywoodCerise        = 244, 0, 161
    Honeydew               = 240, 255, 240
    Hopbush                = 207, 113, 175
    HorsesNeck             = 108, 84, 30
    HotPink                = 255, 105, 180
    HummingBird            = 201, 255, 229
    HunterGreen            = 53, 94, 59
    Illusion               = 244, 152, 173
    InchWorm               = 202, 224, 13
    IndianRed              = 205, 92, 92
    Indigo                 = 75, 0, 130
    InternationalKleinBlue = 0, 24, 168
    InternationalOrange    = 255, 79, 0
    IrisBlue               = 28, 169, 201
    IrishCoffee            = 102, 66, 40
    IronsideGrey           = 113, 112, 110
    IslamicGreen           = 0, 144, 0
    Ivory                  = 255, 255, 240
    Jacarta                = 61, 50, 93
    JackoBean              = 65, 54, 40
    JacksonsPurple         = 46, 45, 136
    Jade                   = 0, 171, 102
    JapaneseLaurel         = 47, 117, 50
    Jazz                   = 93, 43, 44
    JazzberryJam           = 165, 11, 94
    JellyBean              = 68, 121, 142
    JetStream              = 187, 208, 201
    Jewel                  = 0, 107, 60
    Jon                    = 79, 58, 60
    JordyBlue              = 124, 185, 232
    Jumbo                  = 132, 132, 130
    JungleGreen            = 41, 171, 135
    KaitokeGreen           = 30, 77, 43
    Karry                  = 255, 221, 202
    KellyGreen             = 70, 203, 24
    Keppel                 = 93, 164, 147
    Khaki                  = 240, 230, 140
    Killarney              = 77, 140, 87
    KingfisherDaisy        = 85, 27, 140
    Kobi                   = 230, 143, 172
    LaPalma                = 60, 141, 13
    LaserLemon             = 252, 247, 94
    Laurel                 = 103, 146, 103
    Lavender               = 230, 230, 250
    LavenderBlue           = 204, 204, 255
    LavenderBlush          = 255, 240, 245
    LavenderPink           = 251, 174, 210
    LavenderRose           = 251, 160, 227
    LawnGreen              = 124, 252, 0
    LemonChiffon           = 255, 250, 205
    LightBlue              = 173, 216, 230
    LightCoral             = 240, 128, 128
    LightCyan              = 224, 255, 255
    LightGoldenrodYellow   = 250, 250, 210
    LightGray              = 211, 211, 211
    LightGreen             = 144, 238, 144
    LightGrey              = 211, 211, 211
    LightPink              = 255, 182, 193
    LightSalmon            = 255, 160, 122
    LightSeaGreen          = 32, 178, 170
    LightSkyBlue           = 135, 206, 250
    LightSlateGray         = 119, 136, 153
    LightSlateGrey         = 119, 136, 153
    LightSteelBlue         = 176, 196, 222
    LightYellow            = 255, 255, 224
    Lilac                  = 204, 153, 204
    Lime                   = 0, 255, 0
    LimeGreen              = 50, 205, 50
    Limerick               = 139, 190, 27
    Linen                  = 250, 240, 230
    Lipstick               = 159, 43, 104
    Liver                  = 83, 75, 79
    Lochinvar              = 86, 136, 125
    Lochmara               = 38, 97, 156
    Lola                   = 179, 158, 181
    LondonHue              = 170, 152, 169
    Lotus                  = 124, 72, 72
    LuckyPoint             = 29, 41, 81
    MacaroniAndCheese      = 255, 189, 136
    Madang                 = 193, 249, 162
    Madras                 = 81, 65, 0
    Magenta                = 255, 0, 255
    MagicMint              = 170, 240, 209
    Magnolia               = 248, 244, 255
    Mahogany               = 215, 59, 62
    Maire                  = 27, 24, 17
    Maize                  = 230, 190, 138
    Malachite              = 11, 218, 81
    Malibu                 = 93, 173, 236
    Malta                  = 169, 154, 134
    Manatee                = 140, 146, 172
    Mandalay               = 176, 121, 57
    MandarianOrange        = 146, 39, 36
    Mandy                  = 191, 79, 81
    Manhattan              = 229, 170, 112
    Mantis                 = 125, 194, 66
    Manz                   = 217, 230, 80
    MardiGras              = 48, 25, 52
    Mariner                = 57, 86, 156
    Maroon                 = 128, 0, 0
    Matterhorn             = 85, 85, 85
    Mauve                  = 244, 187, 255
    Mauvelous              = 255, 145, 175
    MauveTaupe             = 143, 89, 115
    MayaBlue               = 119, 181, 254
    McKenzie               = 129, 97, 60
    MediumAquamarine       = 102, 205, 170
    MediumBlue             = 0, 0, 205
    MediumCarmine          = 175, 64, 53
    MediumOrchid           = 186, 85, 211
    MediumPurple           = 147, 112, 219
    MediumRedViolet        = 189, 51, 164
    MediumSeaGreen         = 60, 179, 113
    MediumSlateBlue        = 123, 104, 238
    MediumSpringGreen      = 0, 250, 154
    MediumTurquoise        = 72, 209, 204
    MediumVioletRed        = 199, 21, 133
    MediumWood             = 166, 123, 91
    Melon                  = 253, 188, 180
    Merlot                 = 112, 54, 66
    MetallicGold           = 211, 175, 55
    Meteor                 = 184, 115, 51
    MidnightBlue           = 25, 25, 112
    MidnightExpress        = 0, 20, 64
    Mikado                 = 60, 52, 31
    MilanoRed              = 168, 55, 49
    Ming                   = 54, 116, 125
    MintCream              = 245, 255, 250
    MintGreen              = 152, 255, 152
    Mischka                = 168, 169, 173
    MistyRose              = 255, 228, 225
    Moccasin               = 255, 228, 181
    Mojo                   = 149, 69, 53
    MonaLisa               = 255, 153, 153
    Mongoose               = 179, 139, 109
    Montana                = 53, 56, 57
    MoodyBlue              = 116, 108, 192
    MoonYellow             = 245, 199, 26
    MossGreen              = 173, 223, 173
    MountainMeadow         = 28, 172, 120
    MountainMist           = 161, 157, 148
    MountbattenPink        = 153, 122, 141
    Mulberry               = 211, 65, 157
    Mustard                = 255, 219, 88
    Myrtle                 = 25, 89, 5
    MySin                  = 255, 179, 71
    NavajoWhite            = 255, 222, 173
    Navy                   = 0, 0, 128
    NavyBlue               = 2, 71, 254
    NeonCarrot             = 255, 153, 51
    NeonPink               = 255, 92, 205
    Nepal                  = 145, 163, 176
    Nero                   = 20, 20, 20
    NewMidnightBlue        = 0, 0, 156
    Niagara                = 58, 176, 158
    NightRider             = 59, 47, 47
    Nobel                  = 152, 152, 152
    Norway                 = 169, 186, 157
    Nugget                 = 183, 135, 39
    OceanGreen             = 95, 167, 120
    Ochre                  = 202, 115, 9
    OldCopper              = 111, 78, 55
    OldGold                = 207, 181, 59
    OldLace                = 253, 245, 230
    OldLavender            = 121, 104, 120
    OldRose                = 195, 33, 72
    Olive                  = 128, 128, 0
    OliveDrab              = 107, 142, 35
    OliveGreen             = 181, 179, 92
    Olivetone              = 110, 110, 48
    Olivine                = 154, 185, 115
    Onahau                 = 196, 216, 226
    Opal                   = 168, 195, 188
    Orange                 = 255, 165, 0
    OrangePeel             = 251, 153, 2
    OrangeRed              = 255, 69, 0
    Orchid                 = 218, 112, 214
    OuterSpace             = 45, 56, 58
    OutrageousOrange       = 254, 90, 29
    Oxley                  = 95, 167, 119
    PacificBlue            = 0, 136, 220
    Padua                  = 128, 193, 151
    PalatinatePurple       = 112, 41, 99
    PaleBrown              = 160, 120, 90
    PaleChestnut           = 221, 173, 175
    PaleCornflowerBlue     = 188, 212, 230
    PaleGoldenrod          = 238, 232, 170
    PaleGreen              = 152, 251, 152
    PaleMagenta            = 249, 132, 239
    PalePink               = 250, 218, 221
    PaleSlate              = 201, 192, 187
    PaleTaupe              = 188, 152, 126
    PaleTurquoise          = 175, 238, 238
    PaleVioletRed          = 219, 112, 147
    PalmLeaf               = 53, 66, 48
    Panache                = 233, 255, 219
    PapayaWhip             = 255, 239, 213
    ParisDaisy             = 255, 244, 79
    Parsley                = 48, 96, 48
    PastelGreen            = 119, 221, 119
    PattensBlue            = 219, 233, 244
    Peach                  = 255, 203, 164
    PeachOrange            = 255, 204, 153
    PeachPuff              = 255, 218, 185
    PeachYellow            = 250, 223, 173
    Pear                   = 209, 226, 49
    PearlLusta             = 234, 224, 200
    Pelorous               = 42, 143, 189
    Perano                 = 172, 172, 230
    Periwinkle             = 197, 203, 225
    PersianBlue            = 34, 67, 182
    PersianGreen           = 0, 166, 147
    PersianIndigo          = 51, 0, 102
    PersianPink            = 247, 127, 190
    PersianRed             = 192, 54, 44
    PersianRose            = 233, 54, 167
    Persimmon              = 236, 88, 0
    Peru                   = 205, 133, 63
    Pesto                  = 128, 117, 50
    PictonBlue             = 102, 153, 204
    PigmentGreen           = 0, 173, 67
    PigPink                = 255, 218, 233
    PineGreen              = 1, 121, 111
    PineTree               = 42, 47, 35
    Pink                   = 255, 192, 203
    PinkFlare              = 191, 175, 178
    PinkLace               = 240, 211, 220
    PinkSwan               = 179, 179, 179
    Plum                   = 221, 160, 221
    Pohutukawa             = 102, 12, 33
    PoloBlue               = 119, 158, 203
    Pompadour              = 129, 20, 83
    Portage                = 146, 161, 207
    PotPourri              = 241, 221, 207
    PottersClay            = 132, 86, 60
    PowderBlue             = 176, 224, 230
    Prim                   = 228, 196, 207
    PrussianBlue           = 0, 58, 108
    PsychedelicPurple      = 223, 0, 255
    Puce                   = 204, 136, 153
    Pueblo                 = 108, 46, 31
    PuertoRico             = 67, 179, 174
    Pumpkin                = 255, 99, 28
    Purple                 = 128, 0, 128
    PurpleMountainsMajesty = 150, 123, 182
    PurpleTaupe            = 93, 57, 84
    QuarterSpanishWhite    = 230, 224, 212
    Quartz                 = 220, 208, 255
    Quincy                 = 106, 84, 69
    RacingGreen            = 26, 36, 33
    RadicalRed             = 255, 32, 82
    Rajah                  = 251, 171, 96
    RawUmber               = 123, 63, 0
    RazzleDazzleRose       = 254, 78, 218
    Razzmatazz             = 215, 10, 83
    Red                    = 255, 0, 0
    RedBerry               = 132, 22, 23
    RedDamask              = 203, 109, 81
    RedOxide               = 99, 15, 15
    RedRobin               = 128, 64, 64
    RichBlue               = 84, 90, 167
    Riptide                = 141, 217, 204
    RobinsEggBlue          = 0, 204, 204
    RobRoy                 = 225, 169, 95
    RockSpray              = 171, 56, 31
    RomanCoffee            = 131, 105, 83
    RoseBud                = 246, 164, 148
    RoseBudCherry          = 135, 50, 96
    RoseTaupe              = 144, 93, 93
    RosyBrown              = 188, 143, 143
    Rouge                  = 176, 48, 96
    RoyalBlue              = 65, 105, 225
    RoyalHeath             = 168, 81, 110
    RoyalPurple            = 102, 51, 152
    Ruby                   = 215, 24, 104
    Russet                 = 128, 70, 27
    Rust                   = 192, 64, 0
    RusticRed              = 72, 6, 7
    Saddle                 = 99, 81, 71
    SaddleBrown            = 139, 69, 19
    SafetyOrange           = 255, 102, 0
    Saffron                = 244, 196, 48
    Sage                   = 143, 151, 121
    Sail                   = 161, 202, 241
    Salem                  = 0, 133, 67
    Salmon                 = 250, 128, 114
    SandyBeach             = 253, 213, 177
    SandyBrown             = 244, 164, 96
    Sangria                = 134, 1, 17
    SanguineBrown          = 115, 54, 53
    SanMarino              = 80, 114, 167
    SanteFe                = 175, 110, 77
    Sapphire               = 6, 42, 120
    Saratoga               = 84, 90, 44
    Scampi                 = 102, 102, 153
    Scarlet                = 255, 36, 0
    ScarletGum             = 67, 28, 83
    SchoolBusYellow        = 255, 216, 0
    Schooner               = 139, 134, 128
    ScreaminGreen          = 102, 255, 102
    Scrub                  = 59, 60, 54
    SeaBuckthorn           = 249, 146, 69
    SeaGreen               = 46, 139, 87
    Seagull                = 140, 190, 214
    SealBrown              = 61, 12, 2
    Seance                 = 96, 47, 107
    SeaPink                = 215, 131, 127
    SeaShell               = 255, 245, 238
    Selago                 = 250, 230, 250
    SelectiveYellow        = 242, 180, 0
    SemiSweetChocolate     = 107, 68, 35
    Sepia                  = 150, 90, 62
    Serenade               = 255, 233, 209
    Shadow                 = 133, 109, 77
    Shakespeare            = 114, 160, 193
    Shalimar               = 252, 255, 164
    Shamrock               = 68, 215, 168
    ShamrockGreen          = 0, 153, 102
    SherpaBlue             = 0, 75, 73
    SherwoodGreen          = 27, 77, 62
    Shilo                  = 222, 165, 164
    ShipCove               = 119, 139, 165
    Shocking               = 241, 156, 187
    ShockingPink           = 255, 29, 206
    ShuttleGrey            = 84, 98, 111
    Sidecar                = 238, 224, 177
    Sienna                 = 160, 82, 45
    Silk                   = 190, 164, 147
    Silver                 = 192, 192, 192
    SilverChalice          = 175, 177, 174
    SilverTree             = 102, 201, 146
    SkyBlue                = 135, 206, 235
    SlateBlue              = 106, 90, 205
    SlateGray              = 112, 128, 144
    SlateGrey              = 112, 128, 144
    Smalt                  = 0, 48, 143
    SmaltBlue              = 74, 100, 108
    Snow                   = 255, 250, 250
    SoftAmber              = 209, 190, 168
    Solitude               = 235, 236, 240
    Sorbus                 = 233, 105, 44
    Spectra                = 53, 101, 77
    SpicyMix               = 136, 101, 78
    Spray                  = 126, 212, 230
    SpringBud              = 150, 255, 0
    SpringGreen            = 0, 255, 127
    SpringSun              = 236, 235, 189
    SpunPearl              = 170, 169, 173
    Stack                  = 130, 142, 132
    SteelBlue              = 70, 130, 180
    Stiletto               = 137, 63, 69
    Strikemaster           = 145, 92, 131
    StTropaz               = 50, 82, 123
    Studio                 = 115, 79, 150
    Sulu                   = 201, 220, 135
    SummerSky              = 33, 171, 205
    Sun                    = 237, 135, 45
    Sundance               = 197, 179, 88
    Sunflower              = 228, 208, 10
    Sunglow                = 255, 204, 51
    SunsetOrange           = 253, 82, 64
    SurfieGreen            = 0, 116, 116
    Sushi                  = 111, 153, 64
    SuvaGrey               = 140, 140, 140
    Swamp                  = 35, 43, 43
    SweetCorn              = 253, 219, 109
    SweetPink              = 243, 153, 152
    Tacao                  = 236, 177, 118
    TahitiGold             = 235, 97, 35
    Tan                    = 210, 180, 140
    Tangaroa               = 0, 28, 61
    Tangerine              = 228, 132, 0
    TangerineYellow        = 253, 204, 13
    Tapestry               = 183, 110, 121
    Taupe                  = 72, 60, 50
    TaupeGrey              = 139, 133, 137
    TawnyPort              = 102, 66, 77
    TaxBreak               = 79, 102, 106
    TeaGreen               = 208, 240, 192
    Teak                   = 176, 141, 87
    Teal                   = 0, 128, 128
    TeaRose                = 255, 133, 207
    Temptress              = 60, 20, 33
    Tenne                  = 200, 101, 0
    TerraCotta             = 226, 114, 91
    Thistle                = 216, 191, 216
    TickleMePink           = 245, 111, 161
    Tidal                  = 232, 244, 140
    TitanWhite             = 214, 202, 221
    Toast                  = 165, 113, 100
    Tomato                 = 255, 99, 71
    TorchRed               = 255, 3, 62
    ToryBlue               = 54, 81, 148
    Tradewind              = 110, 174, 161
    TrendyPink             = 133, 96, 136
    TropicalRainForest     = 0, 127, 102
    TrueV                  = 139, 114, 190
    TulipTree              = 229, 183, 59
    Tumbleweed             = 222, 170, 136
    Turbo                  = 255, 195, 36
    TurkishRose            = 152, 119, 123
    Turquoise              = 64, 224, 208
    TurquoiseBlue          = 118, 215, 234
    Tuscany                = 175, 89, 62
    TwilightBlue           = 253, 255, 245
    Twine                  = 186, 135, 89
    TyrianPurple           = 102, 2, 60
    Ultramarine            = 10, 17, 149
    UltraPink              = 255, 111, 255
    Valencia               = 222, 82, 70
    VanCleef               = 84, 61, 55
    VanillaIce             = 229, 204, 201
    VenetianRed            = 209, 0, 28
    Venus                  = 138, 127, 128
    Vermilion              = 251, 79, 20
    VeryLightGrey          = 207, 207, 207
    VidaLoca               = 94, 140, 49
    Viking                 = 71, 171, 204
    Viola                  = 180, 131, 149
    ViolentViolet          = 50, 23, 77
    Violet                 = 238, 130, 238
    VioletRed              = 255, 57, 136
    Viridian               = 64, 130, 109
    VistaBlue              = 159, 226, 191
    VividViolet            = 127, 62, 152
    WaikawaGrey            = 83, 104, 149
    Wasabi                 = 150, 165, 60
    Watercourse            = 0, 106, 78
    Wedgewood              = 67, 107, 149
    WellRead               = 147, 61, 65
    Wewak                  = 255, 152, 153
    Wheat                  = 245, 222, 179
    Whiskey                = 217, 154, 108
    WhiskeySour            = 217, 144, 88
    White                  = 255, 255, 255
    WhiteSmoke             = 245, 245, 245
    WildRice               = 228, 217, 111
    WildSand               = 229, 228, 226
    WildStrawberry         = 252, 65, 154
    WildWatermelon         = 255, 84, 112
    WildWillow             = 172, 191, 96
    Windsor                = 76, 40, 130
    Wisteria               = 191, 148, 228
    Wistful                = 162, 162, 208
    Yellow                 = 255, 255, 0
    YellowGreen            = 154, 205, 50
    YellowOrange           = 255, 174, 66
    YourPink               = 244, 194, 194
}

$Script:ScriptBlockColors = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $Script:RGBColors.Keys | Where-Object { $_ -like "*$wordToComplete*" }
}
function Close-OfficeWord {
    [cmdletBinding()]
    param(
        [alias('WordDocument')][OfficeIMO.Word.WordDocument] $Document
    )
    try {
        $Document.Dispose()
    }
    catch {
        if ( $_.Exception.InnerException.Message -eq "Memory stream is not expandable.") {
            # we swallow this exception because it only fails on PS 7.
        }
        else {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw
            }
            else {
                Write-Warning "Close-OfficeWord - Couldn't close document properly. Error: $($_.Exception.Message)"
            }
        }
    }
}
function ConvertFrom-HTMLtoWord {
    <#
    .SYNOPSIS
    Converts HTML input to Microsoft Word Document

    .DESCRIPTION
    Converts HTML input to Microsoft Word Document

    .PARAMETER OutputFile
    Path to the file to save converted HTML

    .PARAMETER FileHTML
    Input HTML loaded straight from file

    .PARAMETER SourceHTML
    Input HTML loaded from string

    .PARAMETER Show
    Once conversion ends show the resulting document

    .EXAMPLE
    $Objects = @(
        [PSCustomObject] @{ Test = 1; Test2 = 'Test'; Test3 = 'Ok' }
        [PSCustomObject] @{ Test = 1; Test2 = 'Test'; Test3 = 'Ok' }
    )

    New-HTML {
        New-HTMLText -Text 'This is a test', ' another test' -FontSize 30pt
        New-HTMLTable -DataTable $Objects -Simplify
    } -Online -FilePath $PSScriptRoot\Documents\Test.html

    ConvertFrom-HTMLToWord -OutputFile $PSScriptRoot\Documents\TestHTML.docx -FileHTML $PSScriptRoot\Documents\Test.html -Show

    .EXAMPLE
    $Objects = @(
    [PSCustomObject] @{ Test = 1; Test2 = 'Test'; Test3 = 'Ok' }
    [PSCustomObject] @{ Test = 1; Test2 = 'Test'; Test3 = 'Ok' }
    )

    $Test = New-HTML {
        New-HTMLText -Text 'This is a test', ' another test' -FontSize 30pt
        New-HTMLTable -DataTable $Objects -simplify
    } -Online

    ConvertFrom-HTMLToWord -OutputFile $PSScriptRoot\Documents\TestHTML.docx -HTML $Test -Show

    .NOTES
    General notes
    #>
    [cmdletBinding(DefaultParameterSetName = 'HTML')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'HTMLFile')]
        [Parameter(Mandatory, ParameterSetName = 'HTML')]
        [string] $OutputFile,

        [Parameter(Mandatory, ParameterSetName = 'HTMLFile')][alias('InputFile')][string] $FileHTML,
        [Parameter(Mandatory, ParameterSetName = 'HTML')][alias('HTML')][string] $SourceHTML,

        [Parameter(Mandatory, ParameterSetName = 'HTMLFile')]
        [Parameter(Mandatory, ParameterSetName = 'HTML')]
        [switch] $Show
    )

    $Document = New-OfficeWord -FilePath $OutputFile

    if ($FileHTML) {
        $HTML = Get-Content -LiteralPath $FileHTML -Raw
    }
    elseif ($SourceHTML) {
        $HTML = $SourceHTML
    }

    try {
        $Converter = [HtmlToOpenXml.HtmlConverter]::new($Document._document.MainDocumentPart)
        $Converter.ParseHtml($HTML)
    }
    catch {
        Write-Warning -Message "ConvertFrom-HTMLtoWord - Couldn't convert HTML to Word. Error: $($_.Exception.Message)"
    }

    Save-OfficeWord -Document $Document -Show:$Show.IsPresent
}
function Export-OfficeExcel {
    [cmdletBinding()]
    param(
        [string] $FilePath,
        [alias('Name')][string] $WorksheetName = 'Sheet1',
        [alias("TargetData")][Parameter(ValueFromPipeline = $true)][Array] $DataTable,
        [int] $Row = 1,
        [int] $Column = 1,
        [switch] $Show,
        [switch] $AllProperties,
        [ClosedXML.Excel.XLTransposeOptions] $Transpose,
        [switch] $ShowRowStripes,
        [switch] $ShowColumnStripes,
        [switch] $DisableAutoFilter,
        [switch] $HideHeaderRow,
        [switch] $ShowTotalsRow,
        [switch] $EmphasizeFirstColumn,
        [switch] $EmphasizeLastColumn,
        [string] $Theme
    )
    Begin {
        $Data = [System.Collections.Generic.List[Object]]::new()
    }
    Process {
        foreach ($_ in $DataTable) {
            $Data.Add($_)
        }
    }
    End {
        New-OfficeExcel -FilePath $FilePath {
            New-OfficeExcelWorkSheet -Name $WorksheetName {
                $SplatOfficeExcelTable = @{
                    DataTable            = $Data
                    Row                  = $Row
                    Column               = $Column
                    AllProperties        = $AllProperties.IsPresent
                    DisableAutoFilter    = $DisableAutoFilter.IsPresent
                    EmphasizeFirstColumn = $EmphasizeFirstColumn.IsPresent
                    EmphasizeLastColumn  = $EmphasizeLastColumn.IsPresent
                    ShowColumnStripes    = $ShowColumnStripes.IsPresent
                    ShowRowStripes       = $ShowRowStripes.IsPresent
                    ShowTotalsRow        = $ShowTotalsRow.IsPresent
                    HideHeaderRow        = $HideHeaderRow.IsPresent
                    Transpose            = $Transpose
                    Theme                = $Theme
                }
                Remove-EmptyValue -Hashtable $SplatOfficeExcelTable
                New-OfficeExcelTable @SplatOfficeExcelTable #-DataTable $Data -Row $Row -Column $Column -AllProperties:$AllProperties -AutoFilter -Transpose $Transpose
            } -Option Replace
        } -Show:$Show.IsPresent -Save
    }
}

<#
$Script:ScriptBlockThemes = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    [ClosedXML.Excel.XLTableTheme]::GetAllThemes() | Where-Object { $_ -like "*$wordToComplete*" }
}
#>

Register-ArgumentCompleter -CommandName Export-OfficeExcel -ParameterName Theme -ScriptBlock $Script:ScriptBlockThemes
function Get-OfficeExcel {
    [cmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [switch] $Template,
        [nullable[bool]] $RecalculateAllFormulas #,
        # [ClosedXML.Excel.XLEventTracking] $EventTracking
    )

    if ($FilePath -and (Test-Path -LiteralPath $FilePath)) {
        if ($RecalculateAllFormulas -or $EventTracking) {
            $LoadOptions = [ClosedXML.Excel.LoadOptions]::new()
            if ($null -ne $RecalculateAllFormulas) {
                $LoadOptions.RecalculateAllFormulas = $RecalculateAllFormulas
            }
            if ($EventTracking) {
                $LoadOptions.EventTracking = $EventTracking
            }
            $WorkBook = [ClosedXML.Excel.XLWorkbook]::new($FilePath, $LoadOptions)
        }
        else {
            if ($FilePath) {
                try {
                    $WorkBook = [ClosedXML.Excel.XLWorkbook]::new($FilePath)
                }
                catch {
                    if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                        throw
                    }
                    else {
                        Write-Warning -Message "Get-OfficeExcel - Failed to open $FilePath. Eror: $($_.Exception.Message)"
                        return
                    }
                }
            }
            else {
                $WorkBook = [ClosedXML.Excel.XLWorkbook]::new()
            }
        }
        $WorkBook | Add-Member -MemberType NoteProperty -Name 'FilePath' -Value $FilePath -Force
        $WorkBook
    }
}
function Get-OfficeExcelValue {
    [cmdletBinding()]
    param(
        [ClosedXML.Excel.IXLWorksheet] $Worksheet,
        [int] $Row,
        [int] $Column
    )
    if ($Script:OfficeTrackerExcel) {
        $Worksheet = $Script:OfficeTrackerExcel['WorkSheet']
    }
    elseif (-not $Worksheet) {
        return
    }

    $Worksheet.Cell($Row, $Column)
}
function Get-OfficeExcelWorkSheet {
    [cmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [parameter(Position = 0, ParameterSetName = 'Name')]
        [parameter(Position = 0, ParameterSetName = 'Index')]
        [parameter(Position = 0, ParameterSetName = 'All')]
        [scriptblock] $ExcelContent,

        [parameter(ParameterSetName = 'Name')]
        [parameter(ParameterSetName = 'Index')]
        [parameter(ParameterSetName = 'All')]
        [alias('ExcelDocument')][ClosedXML.Excel.XLWorkbook]$Excel,

        [parameter(ParameterSetName = 'Name')][alias('Name')][string] $WorksheetName,
        [parameter(ParameterSetName = 'Index')][nullable[int]] $Index,
        [parameter(ParameterSetName = 'All')][switch] $All,

        [parameter(ParameterSetName = 'Name')]
        [parameter(ParameterSetName = 'Index')]
        [parameter(ParameterSetName = 'All')]
        [switch] $NameOnly
    )
    $Worksheet = $null
    # This decides between inline and standalone usage of the command
    if ($Script:OfficeTrackerExcel -and -not $Excel) {
        $Excel = $Script:OfficeTrackerExcel['WorkBook']
    }
    try {
        if ($WorksheetName) {
            $Worksheet = $Excel.Worksheets.Worksheet($WorksheetName)
        }
        elseif ($null -ne $Index) {
            $Worksheet = $Excel.Worksheets.Worksheet($Index)
        }
        else {
            $Worksheet = $Excel.Worksheets
        }
    }
    catch {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw
        }
        else {
            Write-Warning -Message "Get-OfficeExcelWorkSheet - Error: $($_.Exception.Message)"
        }
    }
    if ($Worksheet) {
        if ($ExcelContent) {
            # This is to support inline mode
            $Script:OfficeTrackerExcel['WorkSheet'] = $Worksheet
            $ExecutedContent = &  $ExcelContent
            $ExecutedContent
            $Script:OfficeTrackerExcel['WorkSheet'] = $null
        }
        else {
            # Standalone approach
            if ($NameOnly) {
                $Worksheet.Name
            }
            else {
                $Worksheet
            }
        }
    }
    else {
        if ($Index) {
            Write-Warning -Message "Get-OfficeExcelWorkSheet - WorkSheet with index $Index doesnt exits. Skipping."
        }
        elseif ($WorksheetName) {
            Write-Warning -Message "Get-OfficeExcelWorkSheet - WorkSheet with name $WorksheetName doesnt exits. Skipping."
        }
        else {
            Write-Warning -Message "Get-OfficeExcelWorkSheet - Mmm?"
        }
    }
}
function Get-OfficeExcelWorkSheetData {
    [cmdletBinding()]
    param(
        [ClosedXML.Excel.IXLWorksheet] $WorkSheet
    )

    $HeaderNames = [System.Collections.Generic.List[string]]::new()
    foreach ($Cell in $WorkSheet.RangeUsed().Row(1).Cells()) {
        if ($Cell.InnerText -ne "") {
            $Name = $Cell.InnerText
        }
        else {
            $Name = "NoName$($Cell.Address)"
        }
        # We need to check for header duplicates, if someone made a mistake
        if ($HeaderNames.Contains($Name)) {
            $Name = $Name + $($Cell.Address)
        }
        $HeaderNames.Add($Name)
    }
    $LastRowUsed = $WorkSheet.RangeUsed().RowCount()

    foreach ($Row in $WorkSheet.RangeUsed().Rows(2, $LastRowUsed)) {
        $RowData = [ordered] @{}
        for ($i = 0; $i -lt $HeaderNames.Count; $i++) {
            $RowData[$HeaderNames[$i]] = $Row.Cells($i + 1).CachedValue
        }
        [PSCustomObject] $RowData
    }
}
function Get-OfficeWord {
    [cmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [switch] $ReadOnly,
        [switch] $AutoSave
    )

    if ($FilePath -and (Test-Path -LiteralPath $FilePath)) {
        try {
            [OfficeIMO.Word.WordDocument]::Load($FilePath, $ReadOnly.IsPresent, $AutoSave.IsPresent)
        }
        catch {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw
            }
            else {
                Write-Warning "Get-OfficeWord - File $FilePath couldn't be open. Error: $($_.Exception.Message)"
            }
        }
    }
    else {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw "File $FilePath doesn't exists. Try again."
        }
        else {
            Write-Warning "Get-OfficeWord - File $FilePath doesn't exists. Try again."
        }
    }
}
function Import-OfficeExcel {
    <#
    .SYNOPSIS
    Provides a way to converting an Excel file into PowerShell objects.

    .DESCRIPTION
    Provides a way to converting an Excel file into PowerShell objects.
    If Worksheet is not specified, all worksheets will be imported and returned as a hashtable of worksheet names and worksheet objects.
    If Worksheet is specified, only the specified worksheet will be imported and returned as an array of PSCustomObjects

    .PARAMETER FilePath
    The path to the Excel file to import.

    .PARAMETER WorkSheetName
    The name of the worksheet to import. If not specified, all worksheets will be imported.

    .EXAMPLE
    $FilePath = "$PSScriptRoot\Documents\Test5.xlsx"

    $ImportedData1 = Import-OfficeExcel -FilePath $FilePath
    $ImportedData1 | Format-Table

    .EXAMPLE
    $FilePath = "$PSScriptRoot\Documents\Excel.xlsx"

    $ImportedData2 = Import-OfficeExcel -FilePath $FilePath -WorkSheetName 'Contact3'
    $ImportedData2 | Format-Table

    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param(
        [Alias('LiteralPath')][Parameter(Mandatory)][string] $FilePath,
        [string[]] $WorkSheetName
    )

    $ExcelWorkbook = Get-OfficeExcel -FilePath $FilePath
    if ($ExcelWorkbook) {
        $WorkSheetContent = [ordered] @{}
        foreach ($WorkSheet in $ExcelWorkbook.Worksheets) {
            # if user asked for specific worksheet we need to deliver
            if ($WorkSheetName) {
                if ($WorkSheet.Worksheet -notin $WorkSheetName) {
                    continue
                }
            }
            $WorkSheetContent[$WorkSheet.Name] = Get-OfficeExcelWorkSheetData -WorkSheet $WorkSheet
        }
        if ($WorkSheetName.Count -eq 1) {
            $WorkSheetContent[$WorkSheetName]
        }
        elseif ($WorkSheetName.Count -eq 0 -and $WorkSheetContent.Count -eq 1) {
            $WorkSheetContent[0]
        }
        else {
            $WorkSheetContent
        }
        $ExcelWorkbook.Dispose()
    }
}
function New-OfficeExcel {
    [cmdletBinding()]
    param(
        [scriptblock] $ExcelContent,
        [Parameter(Mandatory)][string] $FilePath,
        [switch] $Template,
        [nullable[bool]] $RecalculateAllFormulas,
        #  [ClosedXML.Excel.XLEventTracking] $EventTracking,
        [switch] $Show,
        [switch] $Save,
        [validateSet('Reuse', 'Overwrite', 'Stop')][string] $WhenExists = 'Reuse'
    )
    if ($ExcelContent) {
        $Script:OfficeTrackerExcel = [ordered] @{}
    }

    if (Test-Path -LiteralPath $FilePath) {
        if ($WhenExists -eq 'Stop') {
            Write-Warning -Message "New-OfficeExcel - File $FilePath already exists. Terminating."
            # lets clean up
            $Script:OfficeTrackerExcel = $null
            return
        }
        elseif ($WhenExists -eq 'Overwrite') {
            $WorkBook = [ClosedXML.Excel.XLWorkbook]::new()
            $WorkBook | Add-Member -MemberType NoteProperty -Name 'OpenType' -Value 'New' -Force
        }
        elseif ($WhenExists -eq 'ReUse') {
            Write-Warning -Message "New-OfficeExcel - File $FilePath already exists. Loading up."
            try {
                $WorkBook = [ClosedXML.Excel.XLWorkbook]::new($FilePath)
            }
            catch {
                # lets clean up
                $Script:OfficeTrackerExcel = $null
                if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                    throw
                }
                else {
                    Write-Warning -Message "New-OfficeExcel - File $FilePath returned error: $($_.Exception.Message)"
                    return
                }
            }
            $WorkBook | Add-Member -MemberType NoteProperty -Name 'OpenType' -Value 'Existing' -Force
        }
    }
    else {
        $WorkBook = [ClosedXML.Excel.XLWorkbook]::new()
        $WorkBook | Add-Member -MemberType NoteProperty -Name 'OpenType' -Value 'New' -Force
    }
    $WorkBook | Add-Member -MemberType NoteProperty -Name 'FilePath' -Value $FilePath -Force

    # Lets execute what user wanted to execute
    if ($ExcelContent) {
        $Script:OfficeTrackerExcel['WorkBook'] = $WorkBook
        $Script:OfficeTrackerExcel['OpenType'] = 'Existing'
        $ExecutedContent = & $ExcelContent
        $ExecutedContent
    }

    # This means we use all in one cmdlet, so we're saving
    if ($ExcelContent) {
        if ($Save) {
            Save-OfficeExcel -Show:$Show.IsPresent-FilePath $FilePath -Excel $WorkBook
        }
        # lets clean up
        $Script:OfficeTrackerExcel = $null
    }
    else {
        $WorkBook
    }
}
function New-OfficeExcelTable {
    [cmdletBinding()]
    param(
        [Array] $DataTable,
        [Object] $Worksheet,
        [alias('Row')][int] $StartRow = 1,
        [alias('Column')][int] $StartCell = 1,
        [switch] $ReturnObject,
        [ClosedXML.Excel.XLTransposeOptions] $Transpose,
        [switch] $AllProperties,
        [switch] $SkipHeader,
        [switch] $ShowRowStripes,
        [switch] $ShowColumnStripes,
        [switch] $DisableAutoFilter,
        [switch] $HideHeaderRow,
        [switch] $ShowTotalsRow,
        [switch] $EmphasizeFirstColumn,
        [switch] $EmphasizeLastColumn,
        [string] $Theme
    )
    # This decides between inline and standalone usage of the command
    if ($Script:OfficeTrackerExcel -and -not $Worksheet) {
        $WorkSheet = $Script:OfficeTrackerExcel['WorkSheet']
    }

    $Cell = $StartCell - 1
    # Table header
    if ($DataTable[0] -is [System.Collections.IDictionary]) {
        $Properties = 'Name', 'Value'
    }
    else {
        $Properties = Select-Properties -Objects $DataTable -AllProperties:$AllProperties -Property $IncludeProperty -ExcludeProperty $ExcludeProperty
    }
    # Add Table Header (Title)
    if (-not $SkipHeader) {
        foreach ($Property in $Properties) {
            $Cell++
            New-OfficeExcelValue -Row $StartRow -Value $Property -Column $Cell -Worksheet $Worksheet
        }
    }
    # Table content
    if ($DataTable[0] -is [System.Collections.IDictionary]) {
        # By Ordered Dictionary
        #$Row = 1 # we already added header
        foreach ($Data in $DataTable) {
            foreach ($Key in $Data.Keys) {
                $Row++
                New-OfficeExcelValue -Row ($Row + $StartRow) -Value $Key -Column ($StartCell) -Worksheet $Worksheet
                New-OfficeExcelValue -Row ($Row + $StartRow) -Value $Data[$Key] -Column ($StartCell + 1) -Worksheet $Worksheet
            }
        }
        $LastCell = $Worksheet.Row($StartRow + $Row).Cell($Cell)
    }
    elseif ($Properties -eq '*') {
        foreach ($Data in $DataTable) {
            $Row++
            New-OfficeExcelValue -Row ($Row + $StartRow) -Value $Data -Column ($StartCell) -Worksheet $Worksheet
        }
        $LastCell = $Worksheet.Row($StartRow + $Row).Cell($StartCell)
    }
    else {
        # By PSCustomObject
        for ($Row = 1; $Row -le $DataTable.Count; $Row++) {
            $Cell = $StartCell - 1
            foreach ($Property in $Properties) {
                $Cell++
                New-OfficeExcelValue -Row ($Row + $StartRow) -Value $DataTable[$Row - 1].$Property -Column $Cell -Worksheet $Worksheet
            }
        }
        $LastCell = $Worksheet.Row($StartRow - 1 + $Row).Cell($Cell)
    }
    $FirstCell = $Worksheet.Row($StartRow).Cell($StartCell)
    $Range = $Worksheet.Range($FirstCell.Address, $LastCell.Address)
    $TableOutput = $Range.CreateTable()

    $SplatOptions = @{
        Table                = $TableOutput
        Transpose            = $Transpose
        ShowRowStripes       = $ShowRowStripes.IsPresent
        ShowColumnStripes    = $ShowColumnStripes.IsPresent
        DisableAutoFilter    = $DisableAutoFilter.IsPresent
        HideHeaderRow        = $HideHeaderRow.IsPresent
        ShowTotalsRow        = $ShowTotalsRow.IsPresent
        EmphasizeFirstColumn = $EmphasizeFirstColumn.IsPresent
        EmphasizeLastColumn  = $EmphasizeLastColumn.IsPresent
        Theme                = $Theme
    }
    Remove-EmptyValue -Hashtable $SplatOptions
    New-OfficeExcelTableOptions @SplatOptions
}
function New-OfficeExcelTableOptions {
    [cmdletBinding()]
    param(
        $Table,
        [ClosedXML.Excel.XLTransposeOptions] $Transpose,
        [switch] $ShowRowStripes,
        [switch] $ShowColumnStripes,
        [switch] $DisableAutoFilter,
        [switch] $HideHeaderRow,
        [switch] $ShowTotalsRow,
        [switch] $EmphasizeFirstColumn,
        [switch] $EmphasizeLastColumn,
        [string] $Theme
    )

    # Apply some options to table we just added
    if ($Table) {
        if ($null -ne $Transpose) {
            $Table.Transpose($Transpose)
        }
        if ($AutoFilter) {
            $Table.InitializeAutoFilter()
        }
        if ($ShowColumnStripes) {
            $Table.ShowColumnStripes = $true
        }
        if ($ShowRowStripes) {
            $Table.ShowRowStripes = $true
        }
        if ($DisableAutoFilter) {
            $Table.ShowAutoFilter = $false
        }
        if ($ShowTotalsRow) {
            $Table.ShowsTotalRow = $true
        }
        if ($null -ne $Theme) {
            $Table.Theme = $Theme
        }
        if ($EmphasizeFirstColumn) {
            $Table.EmphasizeFirstColumn = $true
        }
        if ($EmphasizeLastColumn) {
            $Table.EmphasizeLastColumn = $true
        }
        if ($HideHeaderRow) {
            $Table.ShowHeaderRow = $false
        }
        if ($ReturnObject) {
            $Table
        }
    }
}
function New-OfficeExcelValue {
    [cmdletBinding()]
    param(
        $Worksheet,
        [Object] $Value,
        [int] $Row,
        [int] $Column,
        [string] $DateFormat,
        [string] $NumberFormat,
        [int] $FormatID
    )
    $KnownTypes = 'bool|byte|char|datetime|decimal|double|float|int|long|sbyte|short|string|timespan|uint|ulong|URI|ushort'
    if ($Script:OfficeTrackerExcel) {
        $Worksheet = $Script:OfficeTrackerExcel['WorkSheet']
    }
    elseif (-not $Worksheet) {
        return
    }

    try {
        if ($null -eq $Value) {
            $Worksheet.Cell($Row, $Column).Value = ''
        }
        elseif ($Value.GetType().Name -match $KnownTypes) {
            $Worksheet.Cell($Row, $Column).Value = [ClosedXML.Excel.XLCellValue]::FromObject($Value)
        }
        else {
            $Worksheet.Cell($Row, $Column).Value = [string] $Value
        }
    }
    catch {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw
        }
        else {
            Write-Warning "New-OfficeExcelValue - Error: $($_.Exception.Message)"
        }
    }
}
function New-OfficeExcelWorkSheet {
    [cmdletBinding()]
    param(
        [parameter(Position = 0)][scriptblock] $ExcelContent,
        [alias('ExcelDocument')][ClosedXML.Excel.XLWorkbook]$Excel,
        [parameter(Mandatory)][alias('Name')][string] $WorksheetName,
        [ValidateSet("Replace", "Skip", "Rename")][string] $Option = 'Skip',
        [switch] $Suppress,
        [string] $TabColor
    )
    $Worksheet = $null
    # This decides between inline and standalone usage of the command

    if ($null -ne $Excel) {
        # We do nothing
    }
    elseif ($Script:OfficeTrackerExcel -and -not $Excel) {
        $Excel = $Script:OfficeTrackerExcel['WorkBook']
    }
    else {
        # Excel not provided, this means most likely some other cmdlet failed up in the chain
        return
    }

    if ($Excel.Worksheets.Contains($WorksheetName)) {
        if ($Option -eq 'Skip') {
            Write-Warning -Message "New-OfficeExcelWorkSheet - WorkSheet with name $WorksheetName already exists. Skipping..."
            return
        }
        elseif ($Option -eq 'Replace') {
            Write-Warning -Message "New-OfficeExcelWorkSheet - WorkSheet with name $WorksheetName already exists. Replacing..."
            $Excel.Worksheets.Worksheet($WorksheetName).Delete()
            $Worksheet = $Excel.Worksheets.Add($WorksheetName)
        }
        elseif ($Option -eq 'Rename') {
            $NewName = "Sheet" + (Get-RandomStringName -Size 6)
            Write-Warning -Message "New-OfficeExcelWorkSheet - WorkSheet with name $WorksheetName already exists. Renaming to $NewName..."
            # $Worksheet = $Excel.Worksheets.Worksheet($WorksheetName)
            $WorkSheetName = $NewName
            $Worksheet = $Excel.Worksheets.Add($WorksheetName)
        }
    }
    else {
        $Worksheet = $Excel.Worksheets.Add($WorksheetName)
    }
    if ($Worksheet) {
        if ($TabColor) {
            Set-OfficeExcelWorkSheetStyle -TabColor $TabColor -Worksheet $Worksheet
        }
        if ($ExcelContent) {
            # This is to support inline mode
            $Script:OfficeTrackerExcel['WorkSheet'] = $Worksheet
            $ExecutedContent = &  $ExcelContent
            $ExecutedContent
            $Script:OfficeTrackerExcel['WorkSheet'] = $null
        }
        else {
            if (-not $Suppress) {
                # Standalone approach
                if ($NameOnly) {
                    $Worksheet.Name
                }
                else {
                    $Worksheet
                }
            }
        }
    }
}

Register-ArgumentCompleter -CommandName New-OfficeExcelWorkSheet -ParameterName TabColor -ScriptBlock $Script:ScriptBlockColors
function New-OfficeWord {
    [cmdletBinding()]
    param(
        [string] $FilePath,
        [switch] $AutoSave,
        [int] $Retry = 2
    )
    $Saved = $false
    $Count = 0
    while ($Count -le $Retry -and $Saved -eq $false) {
        $Count++
        try {
            $WordDocument = [OfficeImo.Word.WordDocument]::Create($FilePath, $AutoSave.IsPresent)
            $Saved = $true
        }
        catch {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw
            }
            else {
                Write-Warning "New-OfficeWord - Couldn't create new Word Document at $FilePath. Error: $($_.Exception.Message)"
            }
        }
        if (-not $Saved) {
            if ($Retry -ge $Count) {
                $FilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$($([System.IO.Path]::GetRandomFileName()).Split('.')[0]).docx")
                Write-Warning -Message "New-OfficeWord - Couldn't save using provided file name, retrying with $FilePath"
            }
            else {
                Write-Warning -Message "New-OfficeWord - Couldn't save using provided file name. Run out of retries ($Count / $Retry)."
                return
            }
        }
    }
    $WordDocument
}
function New-OfficeWordList {
    [cmdletBinding()]
    param(
        [ScriptBlock] $Content,
        [OfficeImo.Word.WordDocument] $Document,
        [OfficeIMO.Word.WordListStyle] $Style = [OfficeIMO.Word.WordListStyle]::Bulleted,
        [switch] $Suppress
    )

    $List = $Document.AddList($Style)
    if ($Content) {
        $ListItems = & $Content
        foreach ($Item in $ListItems) {
            # We will use the same function we use externally but internall
            # But we define the list now
            $Item.List = $List
            # We also don't want to have output from List Items
            $Item.Suppress = $true
            New-OfficeWordListItem @Item
        }
    }
    if (-not $Suppress) {
        $List
    }
}
function New-OfficeWordListItem {
    [cmdletBinding()]
    param(
        [OfficeIMO.Word.WordList] $List,
        [int] $Level,
        [string[]]$Text,
        [nullable[bool][]] $Bold,
        [nullable[bool][]] $Italic,
        [nullable[DocumentFormat.OpenXml.Wordprocessing.UnderlineValues][]] $Underline,
        [string[]] $Color,
        [nullable[DocumentFormat.OpenXml.Wordprocessing.JustificationValues]] $Alignment,
        [switch] $Suppress
    )
    if ($List) {
        # This is standard usage + internal function
        $ListItem = $List.AddItem($Text, $Level)
        if (-not $Suppress) {
            $ListItem
        }
    }
    else {
        # This is to be used when use within New-OfficeWordList
        [ordered] @{
            List      = $null
            Level     = $Level
            Text      = $Text
            Bold      = $Bold
            Italic    = $Italic
            Underline = $Underline
            Color     = $Color
            Alignment = $Alignment
            Suppress  = $Suppress
        }
    }
}
function New-OfficeWordTable {
    [cmdletBinding()]
    param(
        [OfficeIMO.Word.WordDocument] $Document,
        [Array] $DataTable,
        [OfficeIMO.Word.WordTableStyle] $Style = [OfficeIMO.Word.WordTableStyle]::TableGrid,
        [string] $TableLayout,
        [switch] $SkipHeader,
        [switch] $Suppress
    )

    if (-not $Document) {
        Write-Warning -Message "New-OfficeWordTable - Document is not specified. Please provide valid document."
        return
    }

    if ($DataTable[0] -is [System.Collections.IDictionary]) {
        $Properties = 'Name', 'Value'
    }
    else {
        $Properties = Select-Properties -Objects $DataTable -AllProperties:$AllProperties -Property $IncludeProperty -ExcludeProperty $ExcludeProperty
    }
    $CountRows = 0
    $CountColumns = 0

    $RowsCount = $DataTable.Count
    $ColumnsCount = $Properties.Count

    if (-not $SkipHeader) {
        # Since we need header we add additional row
        $Table = $Document.AddTable($RowsCount + 1, $ColumnsCount, $Style)
        # Add table header, if we don't explicitly ask for it to be skipped
        foreach ($Property in $Properties) {
            $Table.Rows[0].Cells[$CountColumns].Paragraphs[0].Text = $Property
            $CountColumns += 1
        }
        $CountRows += 1
    }
    else {
        # No header so less rows
        $Table = $Document.AddTable($RowsCount, $ColumnsCount, $Style)
    }

    # add table data
    foreach ($Row in $DataTable) {
        $CountColumns = 0
        foreach ($P in $Properties) {
            $Table.Rows[$CountRows].Cells[$CountColumns].Paragraphs[0].Text = $Row.$P
            $CountColumns += 1
        }
        $CountRows += 1
    }

    # return table object
    if (-not $Suppress) {
        $Table
    }

    <#
    # Table content
    if ($DataTable[0] -is [System.Collections.IDictionary]) {

    } elseif ($Properties -eq '*') {


    } else {
        # PSCustomObject
        foreach ($Data in $DataTable) {
            #$TableRow = [DocumentFormat.OpenXml.Wordprocessing.TableRow]::new()

            foreach ($Property in $Properties) {
                $TableCell = [DocumentFormat.OpenXml.Wordprocessing.TableCell]::new()
                $Paragraph = [DocumentFormat.OpenXml.Wordprocessing.Paragraph]::new()
                if ($Data.$Property) {
                   # $Text1 = New-OfficeWordText -Paragraph $Paragraph -Text $Data.$Property -ReturnObject
                }
                $TableCell.Append($Paragraph)
                $TableRow.Append($TableCell)
            }
            #$Table.Append($TableRow)

        }
    }
    #>
}
function New-OfficeWordText {
    [cmdletBinding(DefaultParameterSetName = 'Document')]
    param(
        [Parameter(ParameterSetName = 'Paragraph')]
        [Parameter(ParameterSetName = 'Document', Mandatory)][OfficeIMO.Word.WordDocument] $Document,

        [Parameter(ParameterSetName = 'Paragraph', Mandatory)]
        [OfficeIMO.Word.WordParagraph] $Paragraph,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [string[]]$Text,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [nullable[bool][]] $Bold,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [nullable[bool][]] $Italic,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [nullable[DocumentFormat.OpenXml.Wordprocessing.UnderlineValues][]] $Underline,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [string[]] $Color,

        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [DocumentFormat.OpenXml.Wordprocessing.JustificationValues] $Alignment,
        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [OfficeIMO.Word.WordParagraphStyles] $Style,
        [Parameter(ParameterSetName = 'Document')]
        [Parameter(ParameterSetName = 'Paragraph')]
        [switch] $ReturnObject
    )
    if (-not $Paragraph) {
        $Paragraph = $Document.AddParagraph()
    }
    for ($T = 0; $T -lt $Text.Count; $T++) {
        $Paragraph = $Paragraph.AddText($Text[$T])

        if ($Bold -and $Bold.Count -ge $T -and $Bold[$T]) {
            $Paragraph.Bold = $Bold[$T]
        }
        if ($Italic -and $Italic.Count -ge $T -and $Italic[$T]) {
            $Paragraph.Italic = $Italic[$T]
        }
        if ($Underline -and $Underline.Count -ge $T -and $Underline[$T]) {
            $Paragraph.Underline = $Underline[$T]
        }
        if ($Color -and $Color.Count -ge $T -and $Color[$T]) {
            $ColorToSet = (ConvertFrom-Color -Color $Color[$T])
            if ($ColorToSet) {
                $Paragraph.Color = $ColorToSet
            }
        }
        if ($Style) {
            $Paragraph.Style = $Style
        }
        if ($Alignment) {
            $Paragraph.ParagraphAlignment = $Alignment
        }
    }
    if ($ReturnObject) {
        $Paragraph
    }
}

Register-ArgumentCompleter -CommandName New-OfficeWordText -ParameterName Color -ScriptBlock $Script:ScriptBlockColors
function Remove-OfficeWordFooter {
    [cmdletBinding()]
    param(
        [parameter(Mandatory)][OfficeIMO.Word.WordDocument] $Document
    )
    try {
        [OfficeIMO.Word.WordFooter]::RemoveFooters($Document)
    }
    catch {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw
        }
        else {
            Write-Warning -Message "Remove-OfficeWordFooter - Couldn't remove footer. Error: $($_.Exception.Message)"
        }
    }
}
function Remove-OfficeWordHeader {
    [cmdletBinding()]
    param(
        [parameter(Mandatory)][OfficeIMO.Word.WordDocument] $Document
    )
    try {
        if ($Document) {
            [OfficeIMO.Word.WordHeader]::RemoveHeaders($Document)
        }
        else {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw "Couldn't remove footer. Document not provided."
            }
            else {
                Write-Warning -Message "Remove-OfficeWordHeader - Couldn't remove footer. Document not provided."
            }
        }
    }
    catch {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw
        }
        else {
            Write-Warning -Message "Remove-OfficeWordHeader - Couldn't remove footer. Error: $($_.Exception.Message)"
        }
    }
}
function Save-OfficeExcel {
    [cmdletBinding()]
    param(
        [ClosedXML.Excel.XLWorkbook] $Excel,
        [string] $FilePath,
        [switch] $Show,
        [int] $RetryCount = 1,
        [Parameter(DontShow)] $CurrentRetryCount
    )
    if ($Excel) {
        if (-not $FilePath) {
            $FilePath = $Excel.FilePath
        }
        if ($Excel.Worksheets.Count -gt 0) {
            try {
                if (-not $FilePath) {
                    if ($Excel.OpenType -eq 'Existing') {
                        $Excel.Save()
                    }
                    else {
                        if ($Excel.OpenType -eq 'New') {
                            $Excel.SaveAs($Excel.FilePath)
                        }
                    }
                }
                else {
                    $Excel.SaveAs($FilePath)
                }
                $CurrentRetryCount = 0
            }
            catch {
                if ($RetryCount -eq $CurrentRetryCount) {
                    Write-Warning "Save-ExcelDocument - Couldnt save Excel to $FilePath. Retry count limit reached. Terminating.."
                    return
                }
                $CurrentRetryCount++
                $ErrorMessage = $_.Exception.Message
                if ($ErrorMessage -like "*The process cannot access the file*because it is being used by another process.*" -or
                    $ErrorMessage -like "*Error saving file*") {
                    $FilePath = Get-FileName -Temporary -Extension 'xlsx'
                    Write-Warning "Save-OfficeExcel - Couldn't save file as it was in use or otherwise. Trying different name $FilePath"
                    Save-OfficeExcel -Excel $Excel -Show:$Show -FilePath $FilePath -RetryCount $RetryCount -CurrentRetryCount $CurrentRetryCount
                    # we return as we already show it within nested Save-OfficeExcel
                    # otherwise we would end up opening things again
                    return
                }
                else {
                    Write-Warning "Save-OfficeExcel - Error: $ErrorMessage"
                }
            }

            if ($Show) {
                try {
                    Invoke-Item -Path $FilePath
                }
                catch {
                    Write-Warning "Save-OfficeExcel - Couldn't open file $FilePath as requested."
                }
            }
        }
        else {
            Write-Warning -Message "Save-OfficeExcel - Can't save $FilePath because there are no worksheets."
        }
    }
    else {
        Write-Warning -Message "Save-OfficeExcel - Excel Workbook not provided. Skipping."
    }
}
function Save-OfficeWord {
    [cmdletBinding()]
    param(
        [alias('WordDocument')][OfficeIMO.Word.WordDocument] $Document,
        [switch] $Show,
        [string] $FilePath,
        [int] $Retry = 2
    )
    if (-not $Document) {
        Write-Warning "Save-OfficeWord - Couldn't save Word Document. Document is null."
        return
    }
    if (-not $Document.FilePath -and -not $FilePath) {
        if ($PSBoundParameters.ErrorAction -eq 'Stop') {
            throw
        }
        else {
            Write-Warning "Save-OfficeWord - Couldn't save Word Document. No file path provided."
            return
        }
    }
    if ($FilePath) {
        # File path was given so we use SaveAs
        try {
            $null = $Document.Save($FilePath, $Show.IsPresent)
        }
        catch {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw
            }
            else {
                Write-Warning "Save-OfficeWord - Couldn't save $FilePath. Error: $($_.Exception.Message)"
            }
        }
        finally {
            #$NewDocument.Dispose()
            #$Document.Dispose()
        }
    }
    else {
        if (-not $Document.AutoSave) {
            try {
                $Document.Save($Show.IsPresent)
            }
            catch {
                if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                    throw
                }
                else {
                    Write-Warning "Save-OfficeWord - Couldn't save $($Document.FilePath) Error: $($_.Exception.Message)"
                }
            }
            finally {
                #$Document.Dispose()
            }
        }
    }
    $Document.Dispose()
}
function Set-OfficeExcelCellStyle {
    [cmdletBinding()]
    param(
        $Worksheet,
        [int] $Row,
        [int] $Column,
        [string] $Format,
        [int] $FormatID,
        #[string] $Color,
        #[string] $BackGroundColor,
        [nullable[bool]] $Bold, #         Property   bool Bold {get;set;}
        [ClosedXML.Excel.XLFontCharSet] $FontCharSet, # Property   ClosedXML.Excel.XLFontCharSet FontCharSet {get;set;}
        [alias('Color')][string] $FontColor, # Property   ClosedXML.Excel.XLColor FontColor {get;set;}
        [string] $BackGroundColor,
        [ClosedXML.Excel.XLFillPatternValues] $PatternType,

        [ClosedXML.Excel.XLFontFamilyNumberingValues] $FontFamilyNumbering, # Property   ClosedXML.Excel.XLFontFamilyNumberingValues FontFamilyNumbering {get;set;}
        [string] $FontName, # Property   string FontName {get;set;}
        [double] $FontSize, # Property   double FontSize {get;set;}
        [nullable[bool]] $Italic , # Property   bool Italic {get;set;}
        [nullable[bool]] $Shadow, # Property   bool Shadow {get;set;}
        [nullable[bool]] $Strikethrough , # Property   bool Strikethrough {get;set;}
        [ClosedXML.Excel.XLFontUnderlineValues] $Underline, # Property   ClosedXML.Excel.XLFontUnderlineValues Underline {get;set;}
        [ClosedXML.Excel.XLFontVerticalTextAlignmentValues] $VerticalAlignment # Property   ClosedXML.Excel.XLFontVerticalTextAlignmentValues VerticalAlignment {get;set;}
    )
    if ($Script:OfficeTrackerExcel) {
        $Worksheet = $Script:OfficeTrackerExcel['WorkSheet']
    }
    elseif (-not $Worksheet) {
        return
    }

    # Formatting of numbers/dates
    if ($Format) {
        $Worksheet.Cell($Row, $Column).Style.NumberFormat.Format = $Format
    }
    elseif ($FormatID) {
        $Worksheet.Cell($Row, $Column).Style.NumberFormat.NumberFormatID = $FormatID
    }

    if ($FontColor) {
        $ColorConverted = [ClosedXML.Excel.XLColor]::FromHtml((ConvertFrom-Color -Color $FontColor))
        $Worksheet.Cell($Row, $Column).Style.Font.FontColor = $ColorConverted
    }
    if ($null -ne $Bold) {
        $Worksheet.Cell($Row, $Column).Style.Font.Bold = $Bold
    }
    if ($null -ne $Italic) {
        $Worksheet.Cell($Row, $Column).Style.Font.Italic = $Italic
    }
    if ($null -ne $Strikethrough) {
        $Worksheet.Cell($Row, $Column).Style.Font.Strikethrough = $Strikethrough
    }
    if ($null -ne $Shadow) {
        $Worksheet.Cell($Row, $Column).Style.Font.Shadow = $Shadow
    }
    if ($FontSize) {
        $Worksheet.Cell($Row, $Column).Style.Font.FontSize = $FontSize
    }
    if ($null -ne $Underline) {
        $Worksheet.Cell($Row, $Column).Style.Font.Underline = $Underline
    }
    if ($null -ne $VerticalAlignment) {
        $Worksheet.Cell($Row, $Column).Style.Font.VerticalAlignment = $VerticalAlignment
    }
    if ($null -ne $FontFamilyNumbering) {
        $Worksheet.Cell($Row, $Column).Style.Font.FontFamilyNumbering = $FontFamilyNumbering
    }
    if ($null -ne $FontCharSet) {
        $Worksheet.Cell($Row, $Column).Style.Font.FontCharSet = $FontCharSet
    }

    <# $Worksheet.Cell($Row, $Column).Style
    Font               : False-False-None-False-Baseline-False-11-FF000000-Calibri-Swiss
    Alignment          : General-Bottom-0-False-ContextDependent-0-False-0-False-
    Border             : None-FF000000-None-FF000000-None-FF000000-None-FF000000-None-FF000000-False-False
    Fill               : None
    IncludeQuotePrefix : False
    NumberFormat       : 0-
    Protection         : Locked
    DateFormat         : 0-
    #>

    # $Worksheet.Cell($Row, $Column).Style.Fill | fl
    # BackgroundColor : Color Index: 64
    # PatternColor    : Color Index: 64
    # PatternType     : None

    if ($BackGroundColor) {
        $ColorConverted = [ClosedXML.Excel.XLColor]::FromHtml((ConvertFrom-Color -Color $BackGroundColor))
        $Worksheet.Cell($Row, $Column).Style.Fill.BackgroundColor = $ColorConverted
    }
    if ($PatternType) {
        $Worksheet.Cell($Row, $Column).Style.Fill.PatternType = $PatternType
    }
}

Register-ArgumentCompleter -CommandName Set-OfficeExcelValueStyle -ParameterName FontColor -ScriptBlock $Script:ScriptBlockColors
Register-ArgumentCompleter -CommandName Set-OfficeExcelValueStyle -ParameterName BackGroundColor -ScriptBlock $Script:ScriptBlockColors
function Set-OfficeExcelWorkSheetStyle {
    [cmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [parameter(ParameterSetName = 'Name')]
        [parameter(ParameterSetName = 'Index')]
        [parameter(ParameterSetName = 'Native')]
        [alias('ExcelDocument')][ClosedXML.Excel.XLWorkbook]$Excel,
        [parameter(ParameterSetName = 'Name')]
        [parameter(ParameterSetName = 'Index')]
        [parameter(ParameterSetName = 'Native')]
        [string] $TabColor,
        [parameter(ParameterSetName = 'Native')] $Worksheet,
        [parameter(ParameterSetName = 'Name')][alias('Name')][string] $WorksheetName,
        [parameter(ParameterSetName = 'Index')][nullable[int]] $Index
    )
    #$Worksheet = $null
    # This decides between inline and standalone usage of the command
    if ($Script:OfficeTrackerExcel -and -not $Excel) {
        $Excel = $Script:OfficeTrackerExcel['WorkBook']
    }
    # Lets get worksheet we need
    if ($Worksheet) {
        # this means we provided worksheet object
    }
    else {
        try {
            if ($WorksheetName) {
                $Worksheet = $Excel.Worksheets.Worksheet($WorksheetName)
            }
            elseif ($null -ne $Index) {
                $Worksheet = $Excel.Worksheets.Worksheet($Index)
            }
        }
        catch {
            if ($PSBoundParameters.ErrorAction -eq 'Stop') {
                throw
            }
            else {
                Write-Warning -Message "Set-OfficeExcelWorkSheet - Error: $($_.Exception.Message)"
            }
        }
    }
    if ($Worksheet) {
        if ($TabColor) {
            $ColorConverted = [ClosedXML.Excel.XLColor]::FromHtml((ConvertFrom-Color -Color $TabColor))
            $null = $Worksheet.SetTabColor($ColorConverted)
        }
    }
}

Register-ArgumentCompleter -CommandName Set-OfficeExcelWorkSheetStyle -ParameterName TabColor -ScriptBlock $Script:ScriptBlockColors


if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -lt 461808) {
    Write-Warning "This module requires .NET Framework 4.7.2 or later."; return 
} 

# Export functions and aliases as required
Export-ModuleMember -Function @('Close-OfficeWord', 'ConvertFrom-HTMLtoWord', 'Export-OfficeExcel', 'Get-OfficeExcel', 'Get-OfficeExcelValue', 'Get-OfficeExcelWorkSheet', 'Get-OfficeExcelWorkSheetData', 'Get-OfficeWord', 'Import-OfficeExcel', 'New-OfficeExcel', 'New-OfficeExcelTable', 'New-OfficeExcelTableOptions', 'New-OfficeExcelValue', 'New-OfficeExcelWorkSheet', 'New-OfficeWord', 'New-OfficeWordList', 'New-OfficeWordListItem', 'New-OfficeWordTable', 'New-OfficeWordText', 'Remove-OfficeWordFooter', 'Remove-OfficeWordHeader', 'Save-OfficeExcel', 'Save-OfficeWord', 'Set-OfficeExcelCellStyle', 'Set-OfficeExcelWorkSheetStyle') -Alias @()
# SIG # Begin signature block
# MIItsQYJKoZIhvcNAQcCoIItojCCLZ4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBUkXCVNDr386Tc
# KfoBTca8j7RAnj9BxhRRACyIzQ+VUqCCJrQwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwggWQMIIDeKADAgECAhAFmxtXno4hMuI5B72nd3VcMA0GCSqG
# SIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBH
# NDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIw
# aTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLK
# EdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4Tm
# dDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembu
# d8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnD
# eMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1
# XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVld
# QnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTS
# YW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSm
# M9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzT
# QRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6Kx
# fgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYD
# VR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzANBgkq
# hkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNkaA9Wz3eucPn9mkqZucl4
# XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjSPMFDQK4dUPVS/JA7u5iZ
# aWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK7VB6fWIhCoDIc2bRoAVg
# X+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eBcg3AFDLvMFkuruBx8lbk
# apdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp5aPNoiBB19GcZNnqJqGL
# FNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msgdDDS4Dk0EIUhFQEI6FUy
# 3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vriRbgjU2wGb2dVf0a1TD9u
# KFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ79ARj6e/CVABRoIoqyc54
# zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5nLGbsQAe79APT0JsyQq8
# 7kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3i0objwG2J5VT6LaJbVu8
# aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0HEEcRrYc9B9F1vM/zZn4w
# ggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBH
# NDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbS
# g9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9
# /UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXn
# HwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0
# VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4f
# sbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40Nj
# gHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0
# QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvv
# mz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T
# /jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk
# 42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5r
# mQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4E
# FgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5n
# P+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcG
# CCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQu
# Y29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8v
# Y3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNV
# HSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIB
# AH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxp
# wc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIl
# zpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQ
# cAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfe
# Kuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+j
# Sbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJsh
# IUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6
# OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDw
# N7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR
# 81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2
# VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGsDCCBJigAwIBAgIQ
# CK1AsmDSnEyfXs2pvZOu2TANBgkqhkiG9w0BAQwFADBiMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjEwNDI5MDAw
# MDAwWhcNMzYwNDI4MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgQ29kZSBT
# aWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEA1bQvQtAorXi3XdU5WRuxiEL1M4zrPYGXcMW7xIUmMJ+k
# jmjYXPXrNCQH4UtP03hD9BfXHtr50tVnGlJPDqFX/IiZwZHMgQM+TXAkZLON4gh9
# NH1MgFcSa0OamfLFOx/y78tHWhOmTLMBICXzENOLsvsI8IrgnQnAZaf6mIBJNYc9
# URnokCF4RS6hnyzhGMIazMXuk0lwQjKP+8bqHPNlaJGiTUyCEUhSaN4QvRRXXegY
# E2XFf7JPhSxIpFaENdb5LpyqABXRN/4aBpTCfMjqGzLmysL0p6MDDnSlrzm2q2AS
# 4+jWufcx4dyt5Big2MEjR0ezoQ9uo6ttmAaDG7dqZy3SvUQakhCBj7A7CdfHmzJa
# wv9qYFSLScGT7eG0XOBv6yb5jNWy+TgQ5urOkfW+0/tvk2E0XLyTRSiDNipmKF+w
# c86LJiUGsoPUXPYVGUztYuBeM/Lo6OwKp7ADK5GyNnm+960IHnWmZcy740hQ83eR
# Gv7bUKJGyGFYmPV8AhY8gyitOYbs1LcNU9D4R+Z1MI3sMJN2FKZbS110YU0/EpF2
# 3r9Yy3IQKUHw1cVtJnZoEUETWJrcJisB9IlNWdt4z4FKPkBHX8mBUHOFECMhWWCK
# ZFTBzCEa6DgZfGYczXg4RTCZT/9jT0y7qg0IU0F8WD1Hs/q27IwyCQLMbDwMVhEC
# AwEAAaOCAVkwggFVMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFGg34Ou2
# O/hfEYb7/mF7CIhl9E5CMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9P
# MA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDAzB3BggrBgEFBQcB
# AQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggr
# BgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwHAYDVR0gBBUwEzAH
# BgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcNAQEMBQADggIBADojRD2NCHbuj7w6
# mdNW4AIapfhINPMstuZ0ZveUcrEAyq9sMCcTEp6QRJ9L/Z6jfCbVN7w6XUhtldU/
# SfQnuxaBRVD9nL22heB2fjdxyyL3WqqQz/WTauPrINHVUHmImoqKwba9oUgYftzY
# gBoRGRjNYZmBVvbJ43bnxOQbX0P4PpT/djk9ntSZz0rdKOtfJqGVWEjVGv7XJz/9
# kNF2ht0csGBc8w2o7uCJob054ThO2m67Np375SFTWsPK6Wrxoj7bQ7gzyE84FJKZ
# 9d3OVG3ZXQIUH0AzfAPilbLCIXVzUstG2MQ0HKKlS43Nb3Y3LIU/Gs4m6Ri+kAew
# Q3+ViCCCcPDMyu/9KTVcH4k4Vfc3iosJocsL6TEa/y4ZXDlx4b6cpwoG1iZnt5Lm
# Tl/eeqxJzy6kdJKt2zyknIYf48FWGysj/4+16oh7cGvmoLr9Oj9FpsToFpFSi0HA
# SIRLlk2rREDjjfAVKM7t8RhWByovEMQMCGQ8M4+uKIw8y4+ICw2/O/TOHnuO77Xr
# y7fwdxPm5yg/rBKupS8ibEH5glwVZsxsDsrFhsP2JjMMB0ug0wcCampAMEhLNKhR
# ILutG4UI4lkNbcoFUCvqShyepf2gpx8GdOfy1lKQ/a+FSCH5Vzu0nAPthkX0tGFu
# v2jiJmCG6sivqf6UHedjGzqGVnhOMIIGwjCCBKqgAwIBAgIQBUSv85SdCDmmv9s/
# X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5
# NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcxNDAwMDAwMFoXDTM0MTAx
# MzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMzCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPgz5/X5dLnXaEOCdwvSKOX
# ejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86l+uUUI8cIOrHmjsvlmbj
# aedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSUpIIa2mq62DvKXd4ZGIX7
# ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH9kgtXkV1lnX+3RChG4PB
# uOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PKhu60pCFkcOvV5aDaY7Mu
# 6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f5P17cz4y7lI0+9S769Sg
# LDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZD+BYQfvYsSzhUa+0rRUG
# FOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOlO0L9c33u3Qr/eTQQfqZc
# ClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrqawGw9/sqhux7UjipmAmh
# cbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9CgsqgcT2ckpMEtGlwJw1Pt7U2
# 0clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuRONhRB8qUt+JQofM604qD
# y0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglg
# hkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0O
# BBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEy
# NTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUF
# BzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6
# Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZT
# SEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAIEa1t6g
# qbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ5+PF7SaCinEvGN1Ott5s
# 1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844ektrCQDifXcigLiV4JZ0q
# BXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHnbUFcjGnRuSvExnvPnPp4
# 4pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpUurm8wWkZus8W8oM3NG6w
# QSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF4UbFKNOt50MAcN7MmJ4Z
# iQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+wQtaP4xeR0arAVeOGv6wn
# LEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Panx+VPNTwAvb6cKmx5Adza
# ROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYiyjvrmoI1VygWy2nyMpqy
# 0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjsHPW2obhDLN9OTH0eaHDA
# dwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GXREHJuEbTbDJ8WC9nR2Xl
# G3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMIIHXzCCBUegAwIBAgIQB8JSdCgU
# otar/iTqF+XdLjANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQg
# Q29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExMB4XDTIzMDQxNjAw
# MDAwMFoXDTI2MDcwNjIzNTk1OVowZzELMAkGA1UEBhMCUEwxEjAQBgNVBAcMCU1p
# a2/FgsOzdzEhMB8GA1UECgwYUHJ6ZW15c8WCYXcgS8WCeXMgRVZPVEVDMSEwHwYD
# VQQDDBhQcnplbXlzxYJhdyBLxYJ5cyBFVk9URUMwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCUmgeXMQtIaKaSkKvbAt8GFZJ1ywOH8SwxlTus4McyrWmV
# OrRBVRQA8ApF9FaeobwmkZxvkxQTFLHKm+8knwomEUslca8CqSOI0YwELv5EwTVE
# h0C/Daehvxo6tkmNPF9/SP1KC3c0l1vO+M7vdNVGKQIQrhxq7EG0iezBZOAiukNd
# GVXRYOLn47V3qL5PwG/ou2alJ/vifIDad81qFb+QkUh02Jo24SMjWdKDytdrMXi0
# 235CN4RrW+8gjfRJ+fKKjgMImbuceCsi9Iv1a66bUc9anAemObT4mF5U/yQBgAuA
# o3+jVB8wiUd87kUQO0zJCF8vq2YrVOz8OJmMX8ggIsEEUZ3CZKD0hVc3dm7cWSAw
# 8/FNzGNPlAaIxzXX9qeD0EgaCLRkItA3t3eQW+IAXyS/9ZnnpFUoDvQGbK+Q4/bP
# 0ib98XLfQpxVGRu0cCV0Ng77DIkRF+IyR1PcwVAq+OzVU3vKeo25v/rntiXCmCxi
# W4oHYO28eSQ/eIAcnii+3uKDNZrI15P7VxDrkUIc6FtiSvOhwc3AzY+vEfivUkFK
# RqwvSSr4fCrrkk7z2Qe72Zwlw2EDRVHyy0fUVGO9QMuh6E3RwnJL96ip0alcmhKA
# BGoIqSW05nXdCUbkXmhPCTT5naQDuZ1UkAXbZPShKjbPwzdXP2b8I9nQ89VSgQID
# AQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHQYD
# VR0OBBYEFHrxaiVZuDJxxEk15bLoMuFI5233MA4GA1UdDwEB/wQEAwIHgDATBgNV
# HSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQw
# OTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAy
# MUNBMS5jcmwwPgYDVR0gBDcwNTAzBgZngQwBBAEwKTAnBggrBgEFBQcCARYbaHR0
# cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMIGUBggrBgEFBQcBAQSBhzCBhDAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFwGCCsGAQUFBzAChlBo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2Rl
# U2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJBgNVHRMEAjAAMA0GCSqG
# SIb3DQEBCwUAA4ICAQC3EeHXUPhpe31K2DL43Hfh6qkvBHyR1RlD9lVIklcRCR50
# ZHzoWs6EBlTFyohvkpclVCuRdQW33tS6vtKPOucpDDv4wsA+6zkJYI8fHouW6Tqa
# 1W47YSrc5AOShIcJ9+NpNbKNGih3doSlcio2mUKCX5I/ZrzJBkQpJ0kYha/pUST2
# CbE3JroJf2vQWGUiI+J3LdiPNHmhO1l+zaQkSxv0cVDETMfQGZKKRVESZ6Fg61b0
# djvQSx510MdbxtKMjvS3ZtAytqnQHk1ipP+Rg+M5lFHrSkUlnpGa+f3nuQhxDb7N
# 9E8hUVevxALTrFifg8zhslVRH5/Df/CxlMKXC7op30/AyQsOQxHW1uNx3tG1DMgi
# zpwBasrxh6wa7iaA+Lp07q1I92eLhrYbtw3xC2vNIGdMdN7nd76yMIjdYnAn7r38
# wwtaJ3KYD0QTl77EB8u/5cCs3ShZdDdyg4K7NoJl8iEHrbqtooAHOMLiJpiL2i9Y
# n8kQMB6/Q6RMO3IUPLuycB9o6DNiwQHf6Jt5oW7P09k5NxxBEmksxwNbmZvNQ65Z
# n3exUAKqG+x31Egz5IZ4U/jPzRalElEIpS0rgrVg8R8pEOhd95mEzp5WERKFyXhe
# 6nB6bSYHv8clLAV0iMku308rpfjMiQkqS3LLzfUJ5OHqtKKQNMLxz9z185UCszGC
# BlMwggZPAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2lnbmluZyBS
# U0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQB8JSdCgUotar/iTqF+XdLjANBglghkgB
# ZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJ
# AzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8G
# CSqGSIb3DQEJBDEiBCCl33NEi/CHmV8+owJPkDuNLtPQe519Fbai+sOssdMqvDAN
# BgkqhkiG9w0BAQEFAASCAgBA7ruQmgsOSQaTybot1TYRusoi3+YfeoJDTO06KPNN
# 8HZAUkgziwwtnTO0jpZVVBANwAxGXmzKC8ZEsKlUTdgPS3wufkjjTlzNR7xSMWJz
# a2TEpu/FDqh3FUDod31fE2J2kuJcAb/ubSx6IYGvoVRmM1xL2IcpKEzlC9wY2xZ1
# wzQ033TpXu1dBHcQocsCzHTvkgP5aFpNrkIG6RaT1g5iLAJ5JMS/PWNFnyxoc8CQ
# TxnhM3RW64j50TCeC9OXsNUMIeEaYo+cujYoEhgDkoLVx5w5YwpduR6DpGiO61+h
# nfy1qRxDbIauLMVgxmEcPZzeW8BSjefn6qmgUeKJ4KeH8+KyYUAeQMC/4goBNIeN
# r73O635VU7d3zaliiQeF+jj1amkDF/jJ3gQFqQhQfabRRgrY3NACryVJ0pPaDfa7
# 85v5JcFn26ByWlV5760wk6DCxz0jiv77jnBr14i/106NP+fLWE936M1FCgy7tBu9
# KHfa+mdd0lc3dYJWnNc0IR0WBd3lHdpGPm5dYveDz8YESOzq8H0Bk9uDBIVgnYpF
# ca1NLN4lVZ8s0OirYGA7szcGwGvIUFKcav4dMp83Lm5zZLgK6UvlPUubozwqiqf5
# 185Tu1N9RpQuEJNDYuSk3SUFYnsJ8gaNqeSOSQkg+csd6CuTILkeB83hZdc3lFRJ
# Z6GCAyAwggMcBgkqhkiG9w0BCQYxggMNMIIDCQIBATB3MGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEAVEr/OUnQg5
# pr/bP1/lYRYwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNDAyMjExMTM4MjlaMC8GCSqGSIb3DQEJBDEi
# BCCUqwjXy+7xAb7S/clidknKeencdKi56FRnd3A4Z19fjjANBgkqhkiG9w0BAQEF
# AASCAgAftG8GN0hrxebCQXTl2ErCk5JufaJ8oFRsnQgTU5HDGZxWHZQJqdLm50C3
# eSP05UF3m+Qjw24Nm6sPjuH7NN+9u0b0+TacJgTChQsZXg8QBlNRtIar8XvgplUG
# O3Ci6KjKeqtUjru9UVFQl1AXxjOGlLt4as0j/gXq91y5G6iO6PJUjIbIXFI76RfL
# LJ3Uk/7C1jszFOcB/Xd6pkrLEEsqRLGXNfKx7uipC80MH9oyUR/4Zenmuhc9DwvM
# nutQmI6fhKYWe7F3iSvJlTUmkbpCHhoW3M1U9a7LELiqBE9LnKMeUBJ+KjVYeH12
# xDlH1AHPjBMMjjVAE+uEiRNOCeIAmL3wtD2l1JNXDB0yT6ORGFbFilO95+BsHB7+
# 86kWgR2oH8Abq5cdIHu4bRqUTUYiBKWilozD/Jyj+KexbZjW2MzPcHY47zNerre5
# 33e9IwkA+VilS4EiCn5AvcXcvHUiKPAqVhb+DFnWHqkqHcr9GVPCsjpJBTqsVxTA
# FaywAhFdsZmSGTBteW8t7pnKXu1MBFlwU03EqhMp3NmOIiukBWR3OvPYn3YcU04M
# 4Yc+bvMCTTa+hZIjtX8E+RvBMDjdM5ppXbZRMeGDyQpj1RzCoaOlFbLXuml6GOqD
# euzztcwdiNzNxqGsZ5CUBcVT2TdZUQt4bbRTGXqL6YR3IPl00w==
# SIG # End signature block
