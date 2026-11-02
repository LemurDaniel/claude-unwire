# NOTE:
#   Requires: Windows with Microsoft Edge (headless screenshots), PowerShell 7.
#
#   Renders teaser.html frame by frame ('?t=<ms>') and builds teaser.gif next to it.
#   Edge runs with a throwaway profile per frame, a running Edge is not touched.
#
#   ./docs/teaser/New-UnwireTeaser.ps1
#   ./docs/teaser/New-UnwireTeaser.ps1 -FrameMs 50 -ThrottleLimit 8 -Scale 2

#
#   Chapters:
#     RENDER FRAMES   One Edge screenshot per point in time, in parallel.
#     BUILD GIF       Encodes the frames into teaser.gif and cleans up.
#

[CmdletBinding()]
param (
    <#
    [Optional]
    Time between two frames in milliseconds. Default is 100 (10 fps).
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(20, 1000)]
    [System.Int32]
    $FrameMs = 100,

    <#
    [Optional]
    Edge instances at the same time. Default is 6.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 32)]
    [System.Int32]
    $ThrottleLimit = 6,

    <#
    [Optional]
    Pixels per CSS pixel: 1.5 renders the 720x360 page as 1080x540. Default is 1.5.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1.0, 3.0)]
    [System.Double]
    $Scale = 1.5,

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

. $PSScriptRoot/ConvertTo-UnwireGif.ps1

$DURATION_MS = 9000          # one loop, as DURATION_MS in teaser.html
$WIDTH       = 720           # body size in teaser.html
$HEIGHT      = 360

# ===========================================================================
# ============================   RENDER FRAMES   ============================
# ===========================================================================
#
#   1. Validations   Fails early without Edge.
#   2. Screenshots   One headless Edge per frame, each with its own profile.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early without Edge.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $EdgePath -PathType Leaf)) {
    throw [System.ArgumentException]::new("EdgePath must point to msedge.exe, '$EdgePath' does not exist.")
}

# ---------------------------------------------------------------------------
# Screenshots
#   One headless Edge per frame, each with its own profile.
# ---------------------------------------------------------------------------

$WorkPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "unwire-teaser-$([System.Guid]::NewGuid().ToString('N'))"
$null     = New-Item -ItemType Directory -Path $WorkPath
$PageUri  = ([System.Uri] (Join-Path -Path $PSScriptRoot -ChildPath 'teaser.html')).AbsoluteUri
# '1.5', not '1,5' on a German system
$ScaleText = $Scale.ToString([System.Globalization.CultureInfo]::InvariantCulture)

$Times = @(for ($t = 0; $t -LT $DURATION_MS; $t += $FrameMs) { $t })
Write-Verbose "[New-UnwireTeaser] Rendering $($Times.Count) frames into '$WorkPath'."

try {
    $Times | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $frameFile   = Join-Path -Path $using:WorkPath -ChildPath ('frame-{0:D5}.png' -f $_)
        $profilePath = Join-Path -Path $using:WorkPath -ChildPath "profile-$_"
        $arguments   = @(
            '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run'
            "--force-device-scale-factor=$($using:ScaleText)"
            "--window-size=$($using:WIDTH),$($using:HEIGHT)"
            "--user-data-dir=`"$profilePath`""
            "--screenshot=`"$frameFile`""
            "`"$($using:PageUri)?t=$_`""
        )
        # Start-Process: a direct call of the GUI app does not wait inside -Parallel.
        $edge = Start-Process -FilePath $using:EdgePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $edge.WaitForExit()
        if (-NOT (Test-Path -Path $frameFile)) {
            throw [System.InvalidOperationException]::new("Edge must write a screenshot for t=$_, '$frameFile' is missing.")
        }
    }

    # ===========================================================================
    # ==============================   BUILD GIF   ==============================
    # ===========================================================================
    #
    #   1. Encode   Writes teaser.gif from the frames in time order.
    #

    # ---------------------------------------------------------------------------
    # Encode
    #   Writes teaser.gif from the frames in time order.
    # ---------------------------------------------------------------------------

    $FrameFiles = Get-ChildItem -Path $WorkPath -Filter 'frame-*.png' | Sort-Object -Property Name | Select-Object -ExpandProperty FullName
    ConvertTo-UnwireGif -Frame $FrameFiles -DelayMs $FrameMs -OutputFile (Join-Path -Path $PSScriptRoot -ChildPath 'teaser.gif')
}
finally {
    # Frames and Edge profiles are throwaway, also after an error.
    Remove-Item -Path $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
}
