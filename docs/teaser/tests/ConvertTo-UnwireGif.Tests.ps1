# NOTE:
#   Requires: Pester 5+, Windows (System.Drawing decodes the GIF for the checks).
#
#   Invoke-Pester -Path ./docs/teaser/tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only writes into TestDrive.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Every pixel callback gets x and y, some only need y.')]
param ()

# ===========================================================================
# ===========================   ENCODE A GIF   ==============================
# ===========================================================================
#
#   decodes_exactly      Random pixels of 200 colors come back exactly, LZW table resets.
#   merges_identical     Identical frames in a row become one frame with the summed delay.
#   changed_rows_only    A later frame keeps the unchanged rows of the frame before.
#   loops_endlessly      Writes GIF89a with the NETSCAPE loop extension.
#   size_mismatch        Fails on frames of different sizes.
#

BeforeAll {
    . $PSScriptRoot/../ConvertTo-UnwireGif.ps1
    Add-Type -AssemblyName System.Drawing

    # Writes a PNG whose pixel (x, y) gets the color $Pixel returns.
    function New-TestFrame {
        param ([System.String] $Path, [System.Int32] $Width, [System.Int32] $Height, [System.Management.Automation.ScriptBlock] $Pixel)
        $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
        for ($y = 0; $y -LT $Height; $y++) {
            for ($x = 0; $x -LT $Width; $x++) {
                $bitmap.SetPixel($x, $y, (& $Pixel $x $y))
            }
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        return $Path
    }

    $RED   = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $GREEN = [System.Drawing.Color]::FromArgb(40, 200, 80)
    $BLUE  = [System.Drawing.Color]::FromArgb(40, 80, 200)
}

Describe 'ConvertTo-UnwireGif' {
    It 'decodes_exactly: random pixels of 200 colors come back exactly, LZW table resets' {
        # Channels in steps of 8 keep every color alone in its bucket, so nothing is rounded.
        $random = [System.Random]::new(42)
        $colors = @(1..200 | ForEach-Object { [System.Drawing.Color]::FromArgb($random.Next(32) * 8, $random.Next(32) * 8, $random.Next(32) * 8) })
        $frame  = New-TestFrame -Path "$TestDrive/noise.png" -Width 96 -Height 96 -Pixel { $colors[$random.Next($colors.Count)] }
        $source = [System.Drawing.Bitmap]::new($frame)

        $result = ConvertTo-UnwireGif -Frame $frame -DelayMs 100 -OutputFile "$TestDrive/noise.gif"
        $gif    = [System.Drawing.Bitmap]::new($result.OutputFile)

        $mismatches = 0
        for ($y = 0; $y -LT 96; $y++) {
            for ($x = 0; $x -LT 96; $x++) {
                if ($gif.GetPixel($x, $y).ToArgb() -NE $source.GetPixel($x, $y).ToArgb()) { $mismatches++ }
            }
        }
        $gif.Dispose()
        $source.Dispose()
        $mismatches | Should -Be 0
    }

    It 'merges_identical: identical frames in a row become one frame with the summed delay' {
        $first  = New-TestFrame -Path "$TestDrive/a.png" -Width 8 -Height 8 -Pixel { $RED }
        $second = New-TestFrame -Path "$TestDrive/b.png" -Width 8 -Height 8 -Pixel { param ($x, $y) if ($y -EQ 3) { $GREEN } else { $RED } }

        $result = ConvertTo-UnwireGif -Frame $first, $first, $first, $second -DelayMs 100 -OutputFile "$TestDrive/merge.gif"
        $gif    = [System.Drawing.Image]::FromFile($result.OutputFile)
        $frames = $gif.GetFrameCount([System.Drawing.Imaging.FrameDimension]::Time)
        # PropertyTagFrameDelay (0x5100): one 4 byte delay in 1/100 s per frame
        $delays = $gif.GetPropertyItem(0x5100).Value
        $gif.Dispose()

        $result.Frames                       | Should -Be 2
        $frames                              | Should -Be 2
        [System.BitConverter]::ToInt32($delays, 0) | Should -Be 30
        [System.BitConverter]::ToInt32($delays, 4) | Should -Be 10
    }

    It 'changed_rows_only: a later frame keeps the unchanged rows of the frame before' {
        $first  = New-TestFrame -Path "$TestDrive/c.png" -Width 8 -Height 8 -Pixel { param ($x, $y) if ($y -LT 4) { $RED } else { $BLUE } }
        $second = New-TestFrame -Path "$TestDrive/d.png" -Width 8 -Height 8 -Pixel { param ($x, $y) if ($y -EQ 5) { $GREEN } elseif ($y -LT 4) { $RED } else { $BLUE } }

        $result = ConvertTo-UnwireGif -Frame $first, $second -DelayMs 100 -OutputFile "$TestDrive/rows.gif"
        $gif    = [System.Drawing.Bitmap]::new($result.OutputFile)
        $null   = $gif.SelectActiveFrame([System.Drawing.Imaging.FrameDimension]::Time, 1)

        $gif.GetPixel(2, 1).ToArgb() | Should -Be $RED.ToArgb()
        $gif.GetPixel(2, 5).ToArgb() | Should -Be $GREEN.ToArgb()
        $gif.GetPixel(2, 7).ToArgb() | Should -Be $BLUE.ToArgb()
        $gif.Dispose()
    }

    It 'loops_endlessly: writes GIF89a with the NETSCAPE loop extension' {
        $frame  = New-TestFrame -Path "$TestDrive/e.png" -Width 4 -Height 4 -Pixel { $BLUE }

        $result = ConvertTo-UnwireGif -Frame $frame -DelayMs 100 -OutputFile "$TestDrive/loop.gif"
        $text   = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($result.OutputFile))

        $text.Substring(0, 6) | Should -Be 'GIF89a'
        $text                 | Should -BeLike '*NETSCAPE2.0*'
    }

    It 'size_mismatch: fails on frames of different sizes' {
        $small = New-TestFrame -Path "$TestDrive/f.png" -Width 4 -Height 4 -Pixel { $RED }
        $large = New-TestFrame -Path "$TestDrive/g.png" -Width 6 -Height 4 -Pixel { $RED }

        { ConvertTo-UnwireGif -Frame $small, $large -DelayMs 100 -OutputFile "$TestDrive/bad.gif" } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'Every frame must be 4x4*'
    }
}
