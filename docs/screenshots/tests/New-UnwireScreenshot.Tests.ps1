# NOTE:
#   Requires: Pester 5+. Edge is mocked, no browser starts.
#
#   Invoke-Pester -Path ./docs/screenshots

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# ===========================   TAKE SCREENSHOT   ===========================
# ===========================================================================
#
#   edge_arguments     Starts Edge headless with size, scale and a fresh profile.
#   returns_file       Returns the PNG Edge wrote.
#   stale_png          Fails when Edge writes nothing, also with an old PNG there.
#   missing_edge       Fails early on a missing msedge.exe.
#   missing_page       Fails early on a missing page.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../New-UnwireScreenshot.ps1'
    # '--screenshot="C:\...\api html.png"' => 'C:\...\api html.png'
    $SCREENSHOT_PATTERN = '^--screenshot="(?<path>.+)"$'
}

Describe 'New-UnwireScreenshot' {
    BeforeEach {
        $EdgeFile = Join-Path -Path $TestDrive -ChildPath 'msedge.exe'
        $PageFile = Join-Path -Path $TestDrive -ChildPath 'API.html'
        $OutFile  = Join-Path -Path $TestDrive -ChildPath 'out dir/api html.png'
        Set-Content -Path $EdgeFile -Value 'not a browser'
        Set-Content -Path $PageFile -Value '<!doctype html><title>Router</title>'

        # Edge stand-in: writes a file to the screenshot path like Edge does, returns a process.
        Mock Start-Process {
            $target = [System.Text.RegularExpressions.Regex]::Match(($ArgumentList -match '^--screenshot='), $SCREENSHOT_PATTERN).Groups['path'].Value
            Set-Content -Path $target -Value 'png'
            return [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { } -PassThru
        }
    }

    It 'edge_arguments: starts Edge headless with size, scale and a fresh profile' {
        $null = & $SCRIPT_PATH -Path $PageFile -OutputFile $OutFile -Width 1000 -Height 700 -Scale 1.5 -EdgePath $EdgeFile

        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -EQ $EdgeFile -AND $PassThru -AND
            $ArgumentList -contains '--headless=new' -AND
            $ArgumentList -contains '--window-size=1000,700' -AND
            $ArgumentList -contains '--force-device-scale-factor=1.5' -AND
            @($ArgumentList -like '--user-data-dir="*unwire-screenshot-*"').Count -EQ 1 -AND
            $ArgumentList -contains "`"$(([System.Uri] $PageFile).AbsoluteUri)`""
        }
    }

    It 'returns_file: returns the PNG Edge wrote' {
        $result = & $SCRIPT_PATH -Path $PageFile -OutputFile $OutFile -EdgePath $EdgeFile

        $result.FullName | Should -Be ([System.IO.Path]::GetFullPath($OutFile))
        $result          | Should -Exist
    }

    It 'stale_png: fails when Edge writes nothing, also with an old PNG there' {
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $OutFile -Parent) -Force
        Set-Content -Path $OutFile -Value 'old png'
        Mock Start-Process { [PSCustomObject]@{} | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { } -PassThru }

        { & $SCRIPT_PATH -Path $PageFile -OutputFile $OutFile -EdgePath $EdgeFile } | Should -Throw '*must write the screenshot*'
    }

    It 'missing_edge: fails early on a missing msedge.exe' {
        { & $SCRIPT_PATH -Path $PageFile -OutputFile $OutFile -EdgePath (Join-Path -Path $TestDrive -ChildPath 'none.exe') } | Should -Throw '*EdgePath must point to msedge.exe*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'missing_page: fails early on a missing page' {
        { & $SCRIPT_PATH -Path (Join-Path -Path $TestDrive -ChildPath 'none.html') -OutputFile $OutFile -EdgePath $EdgeFile } | Should -Throw '*must be an existing HTML page*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
