# NOTE:
#   Requires: Windows with Microsoft Edge (headless screenshot), PowerShell 7.
#
#   Takes the README screenshot of an Unwire page in light mode: by default
#   examples/testbed/juiceshop/API.html into api-html.png next to this script.
#   Edge runs with a throwaway profile, so no stored dark theme applies and a
#   running Edge is not touched.
#
#   ./docs/screenshots/New-UnwireScreenshot.ps1
#   ./docs/screenshots/New-UnwireScreenshot.ps1 -Width 1440 -Height 900 -Scale 1.5

#
#   Chapters:
#     TAKE SCREENSHOT   Validates the input and lets Edge write the PNG.
#

[CmdletBinding()]
param (
    <#
    [Optional]
    The page to take. Default is examples/testbed/juiceshop/API.html of this repository.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $Path = (Join-Path -Path $PSScriptRoot -ChildPath '../../examples/testbed/juiceshop/API.html'),

    <#
    [Optional]
    The PNG to write. Default is api-html.png next to this script.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $OutputFile = (Join-Path -Path $PSScriptRoot -ChildPath 'api-html.png'),

    <#
    [Optional]
    Browser window width in CSS pixels. Default is 1280.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(400, 3840)]
    [System.Int32]
    $Width = 1280,

    <#
    [Optional]
    Browser window height in CSS pixels. Default is 860: header, cards, toolbar,
    group tiles and the start of the list.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(300, 2160)]
    [System.Int32]
    $Height = 860,

    <#
    [Optional]
    Pixels per CSS pixel: 2 renders 1280 x 860 as 2560 x 1720, sharp on HiDPI. Default is 2.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1.0, 3.0)]
    [System.Double]
    $Scale = 2,

    <#
    [Optional]
    Path to msedge.exe. Default is the usual install folder.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $EdgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# ===========================================================================
# ===========================   TAKE SCREENSHOT   ===========================
# ===========================================================================
#
#   1. Validations   Fails early without Edge or without the page.
#   2. Screenshot    One headless Edge with its own profile writes the PNG.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early without Edge or without the page.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $EdgePath -PathType Leaf)) {
    throw [System.ArgumentException]::new("EdgePath must point to msedge.exe, '$EdgePath' does not exist.")
}
if (-NOT (Test-Path -Path $Path -PathType Leaf)) {
    throw [System.ArgumentException]::new("Path must be an existing HTML page, '$Path' does not exist.")
}

# ---------------------------------------------------------------------------
# Screenshot
#   One headless Edge with its own profile writes the PNG.
# ---------------------------------------------------------------------------

$PageUri     = ([System.Uri] (Resolve-Path -Path $Path).Path).AbsoluteUri
$TargetFile  = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
$ProfilePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "unwire-screenshot-$([System.Guid]::NewGuid().ToString('N'))"
# '1.5', not '1,5' on a German system
$ScaleText   = $Scale.ToString([System.Globalization.CultureInfo]::InvariantCulture)

$null = New-Item -ItemType Directory -Path (Split-Path -Path $TargetFile -Parent) -Force
# A stale PNG must not pass the check below when Edge fails.
Remove-Item -Path $TargetFile -Force -ErrorAction SilentlyContinue

$EdgeConfig = @{
    FilePath     = $EdgePath
    # Paths in quotes: Start-Process joins the arguments with spaces.
    ArgumentList = @(
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run'
        "--force-device-scale-factor=$ScaleText"
        "--window-size=$Width,$Height"
        "--user-data-dir=`"$ProfilePath`""
        "--screenshot=`"$TargetFile`""
        "`"$PageUri`""
    )
    WindowStyle  = 'Hidden'
    PassThru     = $true
}

try {
    Write-Verbose "[New-UnwireScreenshot] '$PageUri' at ${Width}x$Height, scale $ScaleText -> '$TargetFile'."
    # WaitForExit, not -Wait: -Wait also waits for Edge's background processes, which stay.
    $edge = Start-Process @EdgeConfig
    $edge.WaitForExit()
    if (-NOT (Test-Path -Path $TargetFile -PathType Leaf)) {
        throw [System.InvalidOperationException]::new("Edge must write the screenshot, '$TargetFile' is missing.")
    }
}
finally {
    # The profile is throwaway, also after an error.
    Remove-Item -Path $ProfilePath -Recurse -Force -ErrorAction SilentlyContinue
}

return Get-Item -Path $TargetFile
