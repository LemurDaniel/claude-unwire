function ConvertTo-UnwireGif {
    <#
    .SYNOPSIS
        Builds an endless looping GIF from PNG frames of the same size, without any tool.

    .DESCRIPTION
        One global palette of up to 256 colors from all frames, LZW per frame as GIF89a
        wants it. Identical frames in a row become one frame with the summed delay, every
        other frame only stores the rows that changed, the rest stays from the frame before.

    .EXAMPLE
        PS> ConvertTo-UnwireGif -Frame (Get-ChildItem ./frames/*.png).FullName -DelayMs 100 -OutputFile ./teaser.gif
    #>
    param (
        <#
        [Required]
        The PNG files in playing order, all of the same size.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String[]]
        $Frame,

        <#
        [Required]
        Display time of one frame in milliseconds, rounded to the 10 ms steps of GIF.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(10, 60000)]
        [System.Int32]
        $DelayMs,

        <#
        [Required]
        The GIF file to write.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $OutputFile
    )

    Add-Type -AssemblyName System.Drawing

    $CLEAR_CODE = 256
    $END_CODE   = 257
    $MAX_CODE   = 4096

    # Pixels of every frame as BGR bytes, 3 per pixel, no row padding
    $width  = $null
    $height = $null
    $pixels = @(foreach ($file in $Frame) {
        $bitmap = [System.Drawing.Bitmap]::new($file)
        try {
            if ($null -EQ $width) {
                $width  = $bitmap.Width
                $height = $bitmap.Height
            }
            if ($bitmap.Width -NE $width -OR $bitmap.Height -NE $height) {
                throw [System.ArgumentException]::new("Every frame must be ${width}x$height, '$file' is $($bitmap.Width)x$($bitmap.Height).")
            }
            $rectangle = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
            $locked    = $bitmap.LockBits($rectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $bytes     = [System.Byte[]]::new($width * $height * 3)
            for ($y = 0; $y -LT $height; $y++) {
                [System.Runtime.InteropServices.Marshal]::Copy([System.IntPtr]::Add($locked.Scan0, $y * $locked.Stride), $bytes, $y * $width * 3, $width * 3)
            }
            $bitmap.UnlockBits($locked)
        }
        finally {
            $bitmap.Dispose()
        }
        , $bytes
    })
    $rowBytes = $width * 3

    # Changed rows per frame, identical frames add their delay to the frame before.
    #   [ full frame ] [ rows 40-58 changed ] [ identical -> delay +100 ms ] ...
    $md5    = [System.Security.Cryptography.MD5]::Create()
    $frames = [System.Collections.Generic.List[PSCustomObject]]::new()
    $previousRows = $null
    foreach ($bytes in $pixels) {
        $rows = [System.String[]]::new($height)
        for ($y = 0; $y -LT $height; $y++) {
            $rows[$y] = [System.Convert]::ToBase64String($md5.ComputeHash($bytes, $y * $rowBytes, $rowBytes))
        }
        $top    = 0
        $bottom = $height - 1
        if ($null -NE $previousRows) {
            while ($top -LT $height -AND $rows[$top] -EQ $previousRows[$top]) { $top++ }
            if ($top -EQ $height) {
                $frames[$frames.Count - 1].Delay += $DelayMs
                continue
            }
            while ($rows[$bottom] -EQ $previousRows[$bottom]) { $bottom-- }
        }
        $frames.Add([PSCustomObject]@{ Bytes = $bytes; Top = $top; Bottom = $bottom; Delay = $DelayMs })
        $previousRows = $rows
    }
    $md5.Dispose()

    # Every pixel as bucket of 5 bits per channel: B, G, R (bytes) => 0bRRRRRGGGGGBBBBB
    # Counted per bucket for the palette below: frequency and the color sums.
    $count = [System.Int32[]]::new(32768)
    $sumR  = [System.Int64[]]::new(32768)
    $sumG  = [System.Int64[]]::new(32768)
    $sumB  = [System.Int64[]]::new(32768)
    foreach ($item in $frames) {
        $bytes = $item.Bytes
        $start = $item.Top * $rowBytes
        $keys  = [System.Int32[]]::new(($item.Bottom - $item.Top + 1) * $width)
        for ($k = 0; $k -LT $keys.Length; $k++) {
            $i   = $start + $k * 3
            # Int32 first: -shl on a byte stays a byte and drops the high bits.
            $key = (([System.Int32] $bytes[$i + 2] -shr 3) -shl 10) -bor (([System.Int32] $bytes[$i + 1] -shr 3) -shl 5) -bor ([System.Int32] $bytes[$i] -shr 3)
            $keys[$k] = $key
            $count[$key]++
            $sumR[$key] += $bytes[$i + 2]
            $sumG[$key] += $bytes[$i + 1]
            $sumB[$key] += $bytes[$i]
        }
        $item | Add-Member -NotePropertyName Keys -NotePropertyValue $keys
    }

    # Palette: the 256 most frequent buckets, each with the average color of its pixels
    $usedKeys    = @(0..32767 | Where-Object { $count[$_] -GT 0 })
    $paletteKeys = @($usedKeys | Sort-Object { $count[$_] } -Descending | Select-Object -First 256)
    $palette     = @(foreach ($key in $paletteKeys) {
        , ([System.Double[]] @(($sumR[$key] / $count[$key]), ($sumG[$key] / $count[$key]), ($sumB[$key] / $count[$key])))
    })

    # Lookup bucket => nearest palette color, so the pixel loop below is one array access
    $lookup = [System.Byte[]]::new(32768)
    foreach ($key in $usedKeys) {
        $r = $sumR[$key] / $count[$key]
        $g = $sumG[$key] / $count[$key]
        $b = $sumB[$key] / $count[$key]
        $best = 0
        $bestDistance = [System.Double]::MaxValue
        for ($p = 0; $p -LT $palette.Count; $p++) {
            $dr = $palette[$p][0] - $r; $dg = $palette[$p][1] - $g; $db = $palette[$p][2] - $b
            $distance = $dr * $dr + $dg * $dg + $db * $db
            if ($distance -LT $bestDistance) { $best = $p; $bestDistance = $distance }
        }
        $lookup[$key] = $best
    }

    $out = [System.IO.MemoryStream]::new()
    $writeUInt16 = { param ([System.Int32] $value) $out.WriteByte($value -band 0xFF); $out.WriteByte(($value -shr 8) -band 0xFF) }

    # Header, screen descriptor with a global table of 256 colors, endless loop
    $header = [System.Text.Encoding]::ASCII.GetBytes('GIF89a')
    $out.Write($header, 0, $header.Length)
    & $writeUInt16 $width
    & $writeUInt16 $height
    $out.Write([System.Byte[]] @(0xF7, 0, 0), 0, 3)
    for ($p = 0; $p -LT 256; $p++) {
        $color = if ($p -LT $palette.Count) { $palette[$p] } else { @(0, 0, 0) }
        foreach ($channel in $color) { $out.WriteByte([System.Byte] [System.Math]::Round($channel)) }
    }
    $loop = [System.Byte[]] (@(0x21, 0xFF, 0x0B) + [System.Text.Encoding]::ASCII.GetBytes('NETSCAPE2.0') + @(0x03, 0x01, 0x00, 0x00, 0x00))
    $out.Write($loop, 0, $loop.Length)

    foreach ($item in $frames) {
        # Graphic control: keep the frame below (disposal 1), delay in 1/100 s
        $out.Write([System.Byte[]] @(0x21, 0xF9, 0x04, 0x04), 0, 4)
        & $writeUInt16 ([System.Math]::Max(1, [System.Math]::Round($item.Delay / 10)))
        $out.Write([System.Byte[]] @(0x00, 0x00), 0, 2)

        # Image descriptor: the changed rows over the full width
        $out.WriteByte(0x2C)
        & $writeUInt16 0
        & $writeUInt16 $item.Top
        & $writeUInt16 $width
        & $writeUInt16 ($item.Bottom - $item.Top + 1)
        $out.WriteByte(0x00)

        <#
            LZW with 8 bit colors: codes start at 9 bits and grow up to 12. The decoder adds
            its entries one code later than the encoder, so the size grows once the next free
            entry passed 2^size. A full table (4096) is answered with a clear code.
        #>
        $codeSize  = 9
        $nextCode  = 258
        $table     = [System.Collections.Generic.Dictionary[System.Int32, System.Int32]]::new()
        $data      = [System.Collections.Generic.List[System.Byte]]::new()
        $bitBuffer = $CLEAR_CODE
        $bitCount  = $codeSize
        $keys      = $item.Keys
        $prefix    = [System.Int32] $lookup[$keys[0]]
        $found     = 0

        for ($k = 1; $k -LT $keys.Length; $k++) {
            $color = [System.Int32] $lookup[$keys[$k]]
            $entry = ($prefix -shl 8) -bor $color
            if ($table.TryGetValue($entry, [ref] $found)) {
                $prefix = $found
                continue
            }

            # Unknown sequence: write the prefix, learn prefix + color
            $bitBuffer = $bitBuffer -bor ($prefix -shl $bitCount)
            $bitCount += $codeSize
            while ($bitCount -GE 8) { $data.Add([System.Byte] ($bitBuffer -band 0xFF)); $bitBuffer = $bitBuffer -shr 8; $bitCount -= 8 }

            if ($nextCode -LT $MAX_CODE) {
                $table[$entry] = $nextCode
                $nextCode++
                if ($nextCode -GT (1 -shl $codeSize) -AND $codeSize -LT 12) { $codeSize++ }
            }
            else {
                $bitBuffer = $bitBuffer -bor ($CLEAR_CODE -shl $bitCount)
                $bitCount += $codeSize
                while ($bitCount -GE 8) { $data.Add([System.Byte] ($bitBuffer -band 0xFF)); $bitBuffer = $bitBuffer -shr 8; $bitCount -= 8 }
                $table.Clear()
                $nextCode = 258
                $codeSize = 9
            }
            $prefix = $color
        }

        # Last prefix, end code, the remaining bits
        foreach ($code in @($prefix, $END_CODE)) {
            $bitBuffer = $bitBuffer -bor ($code -shl $bitCount)
            $bitCount += $codeSize
            while ($bitCount -GE 8) { $data.Add([System.Byte] ($bitBuffer -band 0xFF)); $bitBuffer = $bitBuffer -shr 8; $bitCount -= 8 }
        }
        if ($bitCount -GT 0) { $data.Add([System.Byte] ($bitBuffer -band 0xFF)) }

        # Minimum code size, data in blocks of up to 255 bytes, block terminator
        $out.WriteByte(8)
        $dataBytes = $data.ToArray()
        for ($offset = 0; $offset -LT $dataBytes.Length; $offset += 255) {
            $length = [System.Math]::Min(255, $dataBytes.Length - $offset)
            $out.WriteByte($length)
            $out.Write($dataBytes, $offset, $length)
        }
        $out.WriteByte(0x00)
    }

    $out.WriteByte(0x3B)
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
    [System.IO.File]::WriteAllBytes($outputPath, $out.ToArray())
    $out.Dispose()

    return [PSCustomObject]@{
        OutputFile = $outputPath
        Frames     = $frames.Count
        Colors     = $palette.Count
        Bytes      = (Get-Item -Path $outputPath).Length
    }
}
