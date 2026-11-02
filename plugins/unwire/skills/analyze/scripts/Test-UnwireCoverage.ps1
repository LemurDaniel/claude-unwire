# NOTE:
#   Checks that the spec accounts for every candidate of Get-UnwireJsCandidate: nothing of
#   candidates.json may vanish between the code and the spec without a word.
#   A candidate counts as accounted for when
#     > an operation names its position in x-unwire-source        -> operation
#     > its path matches a path of the spec (whole, a base string  -> path
#       as its start, the part after 'base +' as its end)
#     > an open point (x-unwire-open) names its position           -> note
#     > it points to another origin                                -> external
#   Everything else is returned as missing: add the operation, or say in the root
#   x-unwire-open why it is left out, with its position ('assets/main.js:1:2042', a list
#   'assets/app.js:210, 388' or a range 'assets/main.js:1:20000-60000').
#
#   ./plugins/unwire/skills/analyze/scripts/Test-UnwireCoverage.ps1 -Path ./unwire/router/openapi.json -CandidateFile ./unwire/router/candidates.json
#   (./plugins/unwire/skills/analyze/scripts/Test-UnwireCoverage.ps1 -Path ./unwire/router/openapi.json -CandidateFile ./unwire/router/candidates.json).Missing

#
#   Chapters:
#     HELPERS          Path segments, citation parsing and the match of one candidate.
#     LOAD INPUT       Validates both files, collects the spec's paths and citations.
#     CHECK COVERAGE   Sorts every candidate into a status and returns the summary.
#

[CmdletBinding()]
param (
    <#
    [Required]
    Path to the openapi.json to check.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Required]
    Path to the candidates.json of Get-UnwireJsCandidate.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $CandidateFile,

    <#
    [Optional]
    Characters a cited column may be off from the candidate's column. Default is 10: a
    minified bundle is one long line, a wider window would cover the next call too.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(0, 1000)]
    [System.Int32]
    $ColumnTolerance = 10
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$HTTP_METHODS = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
# 'assets/main.js:1:2042', 'assets/app.js:210, 388', 'main.js:1:20000-60000', 'b.js.map::src/api.ts:12'
$CITATION     = '(?<file>[\w@~.-]+(?:/[\w@~.-]+)*\.(?:m?js|cjs|html?|map)(?:::[\w@~./-]+)?):(?<line>\d+)(?::(?<col>\d+)(?:-(?<col2>\d+))?)?(?<more>(?:,\s*\d+(?::\d+)?)*)'
# 'https://cdn.test/x.js' => another origin, '//cdn.test/x' too
$OTHER_ORIGIN = '^(?:https?:)?//'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   ConvertTo-UnwirePathSegment    Path segments with '*' for a template part.
#   Get-UnwireTargetPath           The path part of a target and how it may match.
#   Test-UnwirePathMatch           Whether target segments match a spec path: whole, start or end.
#   Get-UnwireCitation             Every file position named in a text.
#   Test-UnwireCited               Whether a citation names the candidate's position.
#

function ConvertTo-UnwirePathSegment {
    param (
        [System.String] $PathText
    )

    # '/api/devices/{mac}/block' => api, devices, *, block
    # '${this.host}/x/${id}?d=1' => *, x, *     (query and fragment cut, empty segments dropped)
    $pathOnly = ($PathText -SPLIT '[?#]')[0]
    return @(
        $pathOnly.Split('/')
        | Where-Object { $_ -NE '' }
        | ForEach-Object { if ($_ -MATCH '\{|\$') { '*' } else { $_ } }
    )
}

function Get-UnwireTargetPath {
    param (
        [PSCustomObject] $Candidate
    )

    <#
        > template '${this.host}/rest/x/${id}'     -> '/rest/x/${id}', end of a path (base unknown)
        > url-string '/api/Products'               -> a base: the start of a path
        > literal '/api/status'                    -> '/api/status', whole path
        > 'this.host + "/rest/login"'              -> '/rest/login', end of a path
        > 'this.host + "/apply/"' (+ more)         -> '/apply/*', the trailing '/' takes a segment
        > anything else ('api.url', 'z')           -> nothing to match, it needs a citation
    #>
    $target = [System.String] $Candidate.Target
    if ($Candidate.IsLiteralTarget -AND $target -MATCH '^\$\{[^}]+\}(?<rest>.*)$') {
        return [PSCustomObject]@{ Path = $Matches['rest']; Mode = 'suffix' }
    }
    if ($Candidate.IsLiteralTarget -AND $Candidate.Kind -EQ 'url-string') {
        return [PSCustomObject]@{ Path = $target; Mode = 'prefix' }
    }
    if ($Candidate.IsLiteralTarget) {
        return [PSCustomObject]@{ Path = $target; Mode = 'whole' }
    }
    if ($target -MATCH '^[\w$.]+\s*\+\s*[''"`](?<rest>[^''"`]*)[''"`]$') {
        $rest = $Matches['rest']
        return [PSCustomObject]@{ Path = $(if ($rest.EndsWith('/') -AND $rest.Length -GT 1) { "$rest*" } else { $rest }); Mode = 'suffix' }
    }
    return $null
}

function Test-UnwirePathMatch {
    param (
        [System.String[]] $Segments,
        [System.String[]] $SpecPath,
        [ValidateSet('whole', 'prefix', 'suffix')]
        [System.String]   $Mode
    )

    # A part of a path needs one fixed segment: '${this.host}/${id}' would match every path.
    if ($Segments.Count -EQ 0 -OR $Segments.Count -GT $SpecPath.Count) {
        return $false
    }
    if ($Mode -NE 'whole' -AND @($Segments | Where-Object { $_ -NE '*' }).Count -EQ 0) {
        return $false
    }
    if ($Mode -EQ 'whole' -AND $Segments.Count -NE $SpecPath.Count) {
        return $false
    }
    # '/rest/x/*' against '/api/rest/x/{id}' from the end, '/api/x' against '/api/x/{id}' from the start
    $offset = if ($Mode -EQ 'suffix') { $SpecPath.Count - $Segments.Count } else { 0 }
    for ($index = 0; $index -LT $Segments.Count; $index++) {
        $specSegment = $SpecPath[$offset + $index]
        if ($Segments[$index] -NE '*' -AND $specSegment -NE '*' -AND $Segments[$index] -NE $specSegment) {
            return $false
        }
    }
    return $true
}

function Get-UnwireCitation {
    param (
        [System.String] $Text
    )

    foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($Text, $CITATION)) {
        $file = $match.Groups['file'].Value
        [PSCustomObject]@{
            File = $file; Line = [System.Int32] $match.Groups['line'].Value
            Column  = if ($match.Groups['col'].Success) { [System.Int32] $match.Groups['col'].Value } else { $null }
            Column2 = if ($match.Groups['col2'].Success) { [System.Int32] $match.Groups['col2'].Value } else { $null }
        }
        # ', 388, 902' after a citation: more lines (or line:column) of the same file
        foreach ($extra in [System.Text.RegularExpressions.Regex]::Matches($match.Groups['more'].Value, '(?<line>\d+)(?::(?<col>\d+))?')) {
            [PSCustomObject]@{
                File = $file; Line = [System.Int32] $extra.Groups['line'].Value
                Column  = if ($extra.Groups['col'].Success) { [System.Int32] $extra.Groups['col'].Value } else { $null }
                Column2 = $null
            }
        }
    }
}

function Test-UnwireCited {
    param (
        [PSCustomObject] $Citation,
        [PSCustomObject] $Candidate,
        [System.Int32]   $Tolerance
    )

    <#
        > another file                 -> no ('assets/js/app.js' names 'js/app.js', not 'app.js' of another folder)
        > another line                  -> no
        > no column                     -> yes, the whole line
        > a column range                -> yes when the candidate lies inside
        > a column                      -> yes within Tolerance
    #>
    $isSameFile = $Citation.File -EQ $Candidate.File -OR $Citation.File.EndsWith("/$($Candidate.File)", [System.StringComparison]::OrdinalIgnoreCase)
    if (-NOT $isSameFile -OR $Citation.Line -NE $Candidate.Line) {
        return $false
    }
    if ($null -EQ $Citation.Column) {
        return $true
    }
    if ($null -NE $Citation.Column2) {
        return $Candidate.Column -GE $Citation.Column -AND $Candidate.Column -LE $Citation.Column2
    }
    return [System.Math]::Abs($Candidate.Column - $Citation.Column) -LE $Tolerance
}

# ===========================================================================
# =============================   LOAD INPUT   ==============================
# ===========================================================================
#
#   1. Validations   Fails early on a missing or invalid file.
#   2. Spec          Collects the full paths and every citation of the spec.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing or invalid file.
# ---------------------------------------------------------------------------

foreach ($file in $Path, $CandidateFile) {
    if (-NOT (Test-Path -Path $file -PathType Leaf)) {
        throw [System.ArgumentException]::new("Path and CandidateFile must be existing files, got '$file'.")
    }
}
$Spec       = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
$Candidates = @((Get-Content -Path $CandidateFile -Raw | ConvertFrom-Json -Depth 10).candidates)
if ($Spec['paths'] -isnot [System.Collections.IDictionary]) {
    throw [System.ArgumentException]::new("Path must be an OpenAPI spec with a paths object, got '$Path'.")
}

# ---------------------------------------------------------------------------
# Spec
#   Collects the full paths and every citation of the spec.
# ---------------------------------------------------------------------------

# Server prefix: '/api/v1' or 'http://router.test/api/v1' => '/api/v1', '/' => ''
$serverUrl    = [System.String] (@($Spec['servers'])[0] ?? @{})['url']
$serverPath   = ($serverUrl -REPLACE '^(?:https?:)?//[^/]+', '').TrimEnd('/')
$SpecSegments = @($Spec['paths'].Keys | ForEach-Object { , @(ConvertTo-UnwirePathSegment -PathText "$serverPath$_") })

# Citations: x-unwire-source of the operations, every x-unwire-open (root and operations)
$SourceCitations = [System.Collections.Generic.List[PSCustomObject]]::new()
$NoteCitations   = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($note in @($Spec['x-unwire-open'])) {
    if ($note -is [System.String]) { Get-UnwireCitation -Text $note | ForEach-Object { $NoteCitations.Add($_) } }
}
foreach ($pathItem in $Spec['paths'].Values) {
    foreach ($method in @($pathItem.Keys | Where-Object { $_ -IN $HTTP_METHODS })) {
        $operation = $pathItem[$method]
        Get-UnwireCitation -Text ([System.String] $operation['x-unwire-source']) | ForEach-Object { $SourceCitations.Add($_) }
        foreach ($note in @($operation['x-unwire-open'])) {
            if ($note -is [System.String]) { Get-UnwireCitation -Text $note | ForEach-Object { $NoteCitations.Add($_) } }
        }
    }
}
Write-Verbose "[Test-UnwireCoverage] $($Candidates.Count) candidates, $($SpecSegments.Count) paths, $($SourceCitations.Count) source and $($NoteCitations.Count) note citations."

# ===========================================================================
# ============================   CHECK COVERAGE   ===========================
# ===========================================================================
#
#   1. Match     Sorts every candidate into operation, path, note, external or missing.
#   2. Report    Returns the counts and the missing candidates.
#

# ---------------------------------------------------------------------------
# Match
#   Sorts every candidate into operation, path, note, external or missing.
# ---------------------------------------------------------------------------

$Results = foreach ($candidate in $Candidates) {
    <#
        Order of precedence:
        - operation   an x-unwire-source names the position
        - path        the literal target matches a spec path (segments, '*' matches any)
        - note        an open point names the position
        - external    the target is on another origin
        - missing     nothing of the above
    #>
    $status = 'missing'
    if (@($SourceCitations | Where-Object { Test-UnwireCited -Citation $_ -Candidate $candidate -Tolerance $ColumnTolerance }).Count -GT 0) {
        $status = 'operation'
    }
    elseif ([System.String] $candidate.Target -NOTMATCH $OTHER_ORIGIN) {
        $targetPath = Get-UnwireTargetPath -Candidate $candidate
        if ($null -NE $targetPath) {
            $segments = @(ConvertTo-UnwirePathSegment -PathText $targetPath.Path)
            if (@($SpecSegments | Where-Object { Test-UnwirePathMatch -Segments $segments -SpecPath $_ -Mode $targetPath.Mode }).Count -GT 0) {
                $status = 'path'
            }
        }
    }
    if ($status -EQ 'missing' -AND @($NoteCitations | Where-Object { Test-UnwireCited -Citation $_ -Candidate $candidate -Tolerance $ColumnTolerance }).Count -GT 0) {
        $status = 'note'
    }
    if ($status -EQ 'missing' -AND [System.String] $candidate.Target -MATCH $OTHER_ORIGIN) {
        $status = 'external'
    }
    Write-Verbose "[Test-UnwireCoverage] $($candidate.File):$($candidate.Line):$($candidate.Column) '$($candidate.Target)' -> $status."
    [PSCustomObject]@{
        Status = $status; File = $candidate.File; Line = $candidate.Line; Column = $candidate.Column
        Kind   = $candidate.Kind; Method = $candidate.Method; Target = $candidate.Target
    }
}

# ---------------------------------------------------------------------------
# Report
#   Returns the counts and the missing candidates.
# ---------------------------------------------------------------------------

$Results = @($Results)
return [PSCustomObject]@{
    Candidates = $Results.Count
    Operation  = @($Results | Where-Object -Property Status -EQ -Value 'operation').Count
    Path       = @($Results | Where-Object -Property Status -EQ -Value 'path').Count
    Note       = @($Results | Where-Object -Property Status -EQ -Value 'note').Count
    External   = @($Results | Where-Object -Property Status -EQ -Value 'external').Count
    Missing    = @($Results | Where-Object -Property Status -EQ -Value 'missing')
}
