# NOTE:
#   Pre-filters the frontend code of a web UI for endpoint candidates (fetch, axios, jQuery,
#   XMLHttpRequest, HTTP clients, template URLs like '${base}/user/...', URL strings like
#   '/api/...' or 'data.lua'), so unwire:analyze only has to read the code around each hit.
#   Reads local files only, executes nothing.
#
#   Scans *.js, *.mjs, *.cjs, *.html, *.htm and the sourcesContent of *.js.map. A bundle with
#   a source map next to it is skipped, the map holds the same code with real names.
#
#   ./plugins/unwire/skills/analyze/scripts/Get-UnwireJsCandidate.ps1 -Path ./unwire/router/assets
#   ./plugins/unwire/skills/analyze/scripts/Get-UnwireJsCandidate.ps1 -Path ./unwire/router/assets -OutputFile ./unwire/router/candidates.json

#
#   Chapters:
#     HELPERS           Line lookup, method resolution and the scan of one text.
#     COLLECT SOURCES   Validates the input, loads the patterns and every source text.
#     FIND CANDIDATES   Scans every source text with every pattern.
#     WRITE RESULT      Writes candidates.json or returns the candidates.
#

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    Folder with the downloaded or saved assets of the web UI, or a single file.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Optional]
    JSON file to write the candidates into. Then only a summary is returned.
    Default is returning the candidates.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $OutputFile,

    <#
    [Optional]
    Characters of code before and after a hit in the snippet. Default is 120.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(0, 2000)]
    [System.Int32]
    $SnippetChars = 120,

    <#
    [Optional]
    Also scans third-party sources in source maps (node_modules, webpack runtime).
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $IncludeVendor
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$PATTERNS_FILE      = Join-Path -Path $PSScriptRoot -ChildPath '../data/js-patterns.json'
$SOURCE_EXTENSIONS  = @('*.js', '*.mjs', '*.cjs', '*.html', '*.htm', '*.map')
# 'webpack:///node_modules/axios/index.js', 'webpack/bootstrap', '(webpack)/buildin'
$VENDOR_PATTERN     = 'node_modules|webpack/bootstrap|\(webpack\)'
# First argument of a call: a string, a template literal or an expression like 'this.baseUrl'
$ARG_PATTERN        = '(?<target>''[^''\r\n]{0,300}''|"[^"\r\n]{0,300}"|`[^`]{0,300}`|[\w$.\[\]]{1,100})'
# "method: 'POST'" or "type: 'post'" in the options of a call
$METHOD_OPTION      = '\b(?:method|type)\s*:\s*[''"](?<method>get|post|put|patch|delete|head)[''"]'
$METHOD_LOOKAHEAD   = 300                                   # chars after a call searched for METHOD_OPTION
$REGEX_TIMEOUT      = [System.TimeSpan]::FromSeconds(5)     # per pattern and source
$REGEX_OPTIONS      = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Get-UnwireLineStart        Offsets of every line start of a text.
#   Resolve-UnwireMethod       HTTP method of a hit, from the call or its options.
#   Find-UnwireCandidate       Scans one text with every pattern.
#

function Get-UnwireLineStart {
    param (
        [System.String] $Text
    )

    $lineStarts = [System.Collections.Generic.List[System.Int32]]::new()
    $lineStarts.Add(0)
    foreach ($newline in [System.Text.RegularExpressions.Regex]::Matches($Text, "`n")) {
        $lineStarts.Add($newline.Index + 1)
    }
    return , $lineStarts.ToArray()
}

function Resolve-UnwireMethod {
    param (
        [System.String] $CallMethod,
        [System.String] $Text,
        [System.Int32]  $AfterIndex
    )

    <#
        > Method in the call itself (axios.post, $.getJSON, xhr.open('GET'))  -> that method
        > Generic call (fetch, axios(), $.ajax, axios.request)                -> method option
                                                                                within the lookahead
        > No method option found                                              -> unknown ($null)
    #>

    # Method in the call itself
    switch ($CallMethod) {
        { $_ -IN @('get', 'getjson') } { return 'GET' }
        { $_ -IN @('post', 'put', 'patch', 'delete', 'head') } { return $_.ToUpper() }
    }

    # Generic call
    $length      = [System.Math]::Min($METHOD_LOOKAHEAD, $Text.Length - $AfterIndex)
    $optionMatch = [System.Text.RegularExpressions.Regex]::Match($Text.Substring($AfterIndex, $length), $METHOD_OPTION, $REGEX_OPTIONS)
    if ($optionMatch.Success) {
        return $optionMatch.Groups['method'].Value.ToUpper()
    }

    # No method option found
    return $null
}

function Find-UnwireCandidate {
    param (
        [System.String]   $Name,
        [System.String]   $Text,
        [System.Object[]] $Patterns,
        [System.Int32]    $SnippetChars
    )

    $lineStarts = Get-UnwireLineStart -Text $Text
    $hits       = [System.Collections.Generic.List[PSCustomObject]]::new()
    # Offsets of targets already found, so 'axios.get' is not reported again as 'http-client'.
    $takenTargets = [System.Collections.Generic.HashSet[System.Int32]]::new()

    :SCAN_PATTERNS foreach ($pattern in $Patterns) {
        try {
            $patternMatches = @($pattern.Regex.Matches($Text))
        }
        catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
            Write-Warning "[Find-UnwireCandidate] Pattern '$($pattern.Kind)' timed out on '$Name' -> skipping this pattern."
            continue SCAN_PATTERNS
        }

        foreach ($match in $patternMatches) {
            $targetGroup = $match.Groups['target']
            if (-NOT $takenTargets.Add($targetGroup.Index)) {
                continue
            }

            # "'/api/devices'" => '/api/devices' (literal), 'this.baseUrl' stays as it is
            $rawTarget       = $targetGroup.Value
            $isLiteralTarget = $rawTarget -MATCH '^[''"`]'
            $target          = if ($isLiteralTarget) { $rawTarget.Substring(1, $rawTarget.Length - 2) } else { $rawTarget }

            # Line and column of the match, 1-based
            $lineIndex = [System.Array]::BinarySearch($lineStarts, $match.Index)
            $lineIndex = if ($lineIndex -GE 0) { $lineIndex } else { (-BNOT $lineIndex) - 1 }

            # Snippet around the match, whitespace collapsed to one line
            $snippetStart = [System.Math]::Max(0, $match.Index - $SnippetChars)
            $snippetEnd   = [System.Math]::Min($Text.Length, $match.Index + $match.Length + $SnippetChars)
            $snippet      = $Text.Substring($snippetStart, $snippetEnd - $snippetStart) -REPLACE '\s+', ' '

            $hits.Add([PSCustomObject]@{
                    File            = $Name
                    Line            = $lineIndex + 1
                    Column          = $match.Index - $lineStarts[$lineIndex] + 1
                    Kind            = $pattern.Kind
                    Method          = Resolve-UnwireMethod -CallMethod $match.Groups['method'].Value.ToLower() -Text $Text -AfterIndex ($match.Index + $match.Length)
                    Target          = $target
                    IsLiteralTarget = $isLiteralTarget
                    Snippet         = $snippet.Trim()
                })
        }
    }

    return $hits | Sort-Object -Property Line, Column
}

# ===========================================================================
# ===========================   COLLECT SOURCES   ===========================
# ===========================================================================
#
#   1. Validations   Fails early on a missing path.
#   2. Patterns      Compiles the patterns of data/js-patterns.json.
#   3. Sources       Loads every source text, maps before their bundles.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing path.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $Path)) {
    throw [System.ArgumentException]::new("Path must be an existing folder or file with the assets of the web UI, got '$Path'.")
}

# ---------------------------------------------------------------------------
# Patterns
#   Compiles the patterns of data/js-patterns.json.
# ---------------------------------------------------------------------------

$Patterns = @(
    (Get-Content -Path $PATTERNS_FILE -Raw | ConvertFrom-Json).patterns
    | ForEach-Object {
        [PSCustomObject]@{
            Kind  = $_.kind
            Regex = [System.Text.RegularExpressions.Regex]::new($_.pattern.Replace('{ARG}', $ARG_PATTERN), $REGEX_OPTIONS, $REGEX_TIMEOUT)
        }
    }
)
Write-Verbose "[Get-UnwireJsCandidate] Loaded $($Patterns.Count) patterns."

# ---------------------------------------------------------------------------
# Sources
#   Loads every source text, maps before their bundles.
# ---------------------------------------------------------------------------

$RootPath = (Resolve-Path -Path $Path).Path
$RootDir  = if (Test-Path -Path $RootPath -PathType Container) { $RootPath } else { Split-Path -Path $RootPath -Parent }
$Files    = @(Get-ChildItem -Path $RootPath -Include $SOURCE_EXTENSIONS -File -Recurse)
$Sources  = [System.Collections.Generic.List[PSCustomObject]]::new()

# Bundles whose map holds the code, skipped in the second loop.
$CoveredBundles = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Source maps
foreach ($mapFile in $Files | Where-Object -Property Extension -EQ -Value '.map') {
    $mapName = [System.IO.Path]::GetRelativePath($RootDir, $mapFile.FullName).Replace('\', '/')
    $map     = Get-Content -Path $mapFile.FullName -Raw | ConvertFrom-Json -Depth 10

    if ($null -EQ $map.sourcesContent) {
        Write-Verbose "[Get-UnwireJsCandidate] '$mapName' has no sourcesContent -> scanning its bundle instead."
        continue
    }
    $null = $CoveredBundles.Add(($mapFile.FullName -REPLACE '\.map$', ''))

    for ($index = 0; $index -LT $map.sources.Count; $index++) {
        $sourceName = $map.sources[$index]
        $sourceText = $map.sourcesContent[$index]

        if ([System.String]::IsNullOrEmpty($sourceText)) {
            continue
        }
        if (-NOT $IncludeVendor -AND $sourceName -MATCH $VENDOR_PATTERN) {
            Write-Verbose "[Get-UnwireJsCandidate] '$mapName::$sourceName' is vendor code -> skipping."
            continue
        }
        # 'webpack:///./src/api.ts' => 'src/api.ts'
        $cleanName = $sourceName -REPLACE '^[\w-]+:///?', '' -REPLACE '^\./', ''
        $Sources.Add([PSCustomObject]@{ Name = "${mapName}::$cleanName"; Text = $sourceText })
    }
}

# Bundles and pages
foreach ($file in $Files | Where-Object -Property Extension -NE -Value '.map') {
    $fileName = [System.IO.Path]::GetRelativePath($RootDir, $file.FullName).Replace('\', '/')
    if ($CoveredBundles.Contains($file.FullName)) {
        Write-Verbose "[Get-UnwireJsCandidate] '$fileName' is covered by its source map -> skipping."
        continue
    }
    $Sources.Add([PSCustomObject]@{ Name = $fileName; Text = Get-Content -Path $file.FullName -Raw })
}
Write-Verbose "[Get-UnwireJsCandidate] Scanning $($Sources.Count) sources from $($Files.Count) files."

# ===========================================================================
# ===========================   FIND CANDIDATES   ===========================
# ===========================================================================
#
#   1. Scan   Scans every source text with every pattern.
#

# ---------------------------------------------------------------------------
# Scan
#   Scans every source text with every pattern.
# ---------------------------------------------------------------------------

$Candidates = @(
    foreach ($source in $Sources) {
        if ([System.String]::IsNullOrEmpty($source.Text)) {
            continue
        }
        Find-UnwireCandidate -Name $source.Name -Text $source.Text -Patterns $Patterns -SnippetChars $SnippetChars
    }
)
Write-Verbose "[Get-UnwireJsCandidate] Found $($Candidates.Count) candidates."

# ===========================================================================
# ============================   WRITE RESULT   =============================
# ===========================================================================
#
#   1. Report   Writes candidates.json and returns a summary, or returns the candidates.
#

# ---------------------------------------------------------------------------
# Report
#   Writes candidates.json and returns a summary, or returns the candidates.
# ---------------------------------------------------------------------------

if ([System.String]::IsNullOrEmpty($OutputFile)) {
    return $Candidates
}

$Summary = [PSCustomObject]@{
    OutputFile     = $OutputFile
    SourceCount    = $Sources.Count
    CandidateCount = $Candidates.Count
    ByKind         = [ordered]@{}
}
foreach ($group in $Candidates | Group-Object -Property Kind | Sort-Object -Property Name) {
    $Summary.ByKind[$group.Name] = $group.Count
}

if ($PSCmdlet.ShouldProcess($OutputFile, 'Write candidates')) {
    $outputDirectory = Split-Path -Path $OutputFile -Parent
    if (-NOT [System.String]::IsNullOrEmpty($outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }
    [PSCustomObject]@{
        sources    = @($Sources.Name)
        candidates = $Candidates
    }
    | ConvertTo-Json -Depth 5
    | Set-Content -Path $OutputFile -Encoding utf8NoBOM
}

return $Summary
