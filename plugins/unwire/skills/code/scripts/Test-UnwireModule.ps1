# NOTE:
#   Checks a PowerShell module of unwire:code against its openapi.json before the hand-over:
#   the layout of the reference module, one function per picked operation with the method
#   and path of the spec, a question before every write, a warning on every unsure
#   operation, the security of the spec, requests only through Invoke-<Name>Rest and no
#   session value written anywhere, chapters and banners of the code style. Returns one
#   finding per problem, nothing when the module passes. Sends no request: the import runs
#   in a child process, no function is called.
#
#   ./plugins/unwire/skills/code/scripts/Test-UnwireModule.ps1 -Path ./unwire/nas/module/Nas -Spec ./unwire/nas/openapi.json -OperationId listShares, createShare
#   ./plugins/unwire/skills/code/scripts/Test-UnwireModule.ps1 -Path ./unwire/nas/module/Nas -Spec ./unwire/nas/openapi.json | Where-Object Severity -EQ Error

#
#   Chapters:
#     HELPERS           Findings, parsing and the operations of the spec.
#     LOAD INPUT        Validates the folder and the spec, parses every file.
#     CHECK MODULE      Layout, manifest, operations, requests and the import.
#     REPORT FINDINGS   Returns the findings, errors first.
#

[CmdletBinding()]
param (
    <#
    [Required]
    Path to the module folder, named after the module, e.g. ./unwire/nas/module/Nas.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Required]
    Path to the openapi.json the module was written from.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Spec,

    <#
    [Optional]
    The operationIds the user picked. Each needs a function; without it only the
    functions present are checked.
    #>
    [Parameter()]
    [System.String[]]
    $OperationId,

    <#
    [Optional]
    Skips the import in a child process, for tests of the static rules.
    #>
    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $SkipImport
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$HTTP_METHODS     = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
$READ_METHODS     = @('get', 'head', 'options')
$UNSURE_LEVELS    = @('low', 'medium')
# 'Operation:  POST /api/v1/accounts/{accountId}/lock (lockAccount)'
$OPERATION_NOTE   = '(?m)^\s*Operation:\s+(?<method>[A-Za-z]+)\s+(?<path>/\S*)\s+\((?<id>[^)\s]+)\)'
# "Security = @('tokenAuth', 'cookieAuth')" => 'tokenAuth', 'cookieAuth'
$SECURITY_LIST    = '(?m)^\s*Security\s*=\s*@\((?<list>[^)]*)\)'
# Only Invoke-<Name>Rest may send: every other way to reach the device is a finding.
$REQUEST_COMMANDS = @('Invoke-WebRequest', 'Invoke-RestMethod', 'iwr', 'irm', 'curl', 'wget', 'Start-BitsTransfer')
$REQUEST_TYPES    = '\b(?:HttpClient|WebClient|HttpWebRequest|TcpClient|WebRequest\]::Create)\b'
# A session value lives in memory only: nothing that writes a file, a variable or a secret store.
$STORAGE_COMMANDS = @('Out-File', 'Set-Content', 'Add-Content', 'Export-Clixml', 'Export-Csv', 'Tee-Object', 'ConvertFrom-SecureString', 'Set-Secret', 'New-ItemProperty', 'Set-ItemProperty')
$STORAGE_TEXT     = '\[(?:System\.)?IO\.File\]::(?:Write|Append)|SetEnvironmentVariable|\$env:\w+\s*=[^=]|\$global:'
$SCHEME_FIELDS    = @('type', 'in', 'name', 'scheme', 'x-unwire-in', 'x-unwire-path-prefix')
# Code style of the module: chapters (=) and sections (-), 75 characters after '# '.
$BANNER_WIDTH     = 75
$BANNER_LINE      = '^\s*# [=-]{3,}'
$CHAPTER_TITLE    = '^\s*# =+   (?<title>[A-Z0-9][A-Z0-9 ,&/-]*?)   =+\s*$'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Add-UnwireFinding        Adds one finding to the result list.
#   Get-UnwireOperation      The operations of the spec by operationId.
#   Get-UnwireBinding        A named argument of [CmdletBinding()] as text.
#   Get-UnwireCommandName    Every command a script block calls.
#

$Findings = [System.Collections.Generic.List[PSCustomObject]]::new()     # returned in REPORT FINDINGS

function Add-UnwireFinding {
    param (
        [ValidateSet('Error', 'Warning')]
        [System.String] $Severity,
        [System.String] $Location,
        [System.String] $Rule,
        [System.String] $Message
    )

    $Findings.Add([PSCustomObject]@{ Severity = $Severity; Location = $Location; Rule = $Rule; Message = $Message })
}

function Get-UnwireOperation {
    param (
        [System.Collections.IDictionary] $Document
    )

    <#
        Security of an operation, the first requirement with schemes:
        > its own security       -> [{ "tokenAuth": [] }] => 'tokenAuth', [] => none
        > no security of its own -> the root security, the same way
    #>
    $rootSecurity = @($Document['security'])
    $operations   = @{}
    foreach ($pathKey in $Document['paths'].Keys) {
        $pathItem = $Document['paths'][$pathKey]
        foreach ($method in $HTTP_METHODS | Where-Object { $pathItem -is [System.Collections.IDictionary] -AND $pathItem.Contains($_) }) {
            $operation = $pathItem[$method]
            if ([System.String]::IsNullOrEmpty($operation['operationId'])) {
                continue
            }
            $security    = $operation.Contains('security') ? @($operation['security']) : $rootSecurity
            $requirement = $security | Where-Object { $_ -is [System.Collections.IDictionary] -AND $_.Count -GT 0 } | Select-Object -First 1
            $operations[$operation['operationId']] = [PSCustomObject]@{
                Method     = $method
                Path       = $pathKey
                IsWrite    = $operation['x-unwire-impact'] -EQ 'write' -OR $method -NOTIN $READ_METHODS
                Confidence = [System.String] $operation['x-unwire-confidence']
                Security   = @($null -EQ $requirement ? @() : $requirement.Keys | Sort-Object)
            }
        }
    }
    return $operations
}

function Get-UnwireBinding {
    param (
        [System.Management.Automation.Language.FunctionDefinitionAst] $Function,
        [System.String]                                               $Name
    )

    # [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')], 'ConfirmImpact' => 'High'
    $binding  = @($Function.Body.ParamBlock?.Attributes) | Where-Object { $_.TypeName.Name -EQ 'CmdletBinding' } | Select-Object -First 1
    $argument = @(${binding}?.NamedArguments) | Where-Object { $_.ArgumentName -EQ $Name } | Select-Object -First 1
    if ($null -EQ $argument) {
        return $null
    }
    return $argument.Argument.Extent.Text.Trim("'", '"')
}

function Get-UnwireCommandName {
    param (
        [System.Management.Automation.Language.Ast] $Ast
    )

    return @(
        $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        | ForEach-Object { $_.GetCommandName() }
        | Where-Object { $null -NE $_ }
    )
}

# ===========================================================================
# =============================   LOAD INPUT   ==============================
# ===========================================================================
#
#   1. Validations   Fails early on a missing folder or spec.
#   2. Spec          Collects the operations and the security schemes.
#   3. Files         Parses every PowerShell file, a syntax error is a finding.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing folder or spec.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $Path -PathType Container)) {
    throw [System.ArgumentException]::new("Path must be an existing module folder, got '$Path'.")
}
if (-NOT (Test-Path -Path $Spec -PathType Leaf)) {
    throw [System.ArgumentException]::new("Spec must be an existing openapi.json file, got '$Spec'.")
}

$ModuleRoot = (Resolve-Path -Path $Path).Path
$ModuleName = Split-Path -Path $ModuleRoot -Leaf
$Wrapper    = "Invoke-$($ModuleName)Rest"

# ---------------------------------------------------------------------------
# Spec
#   Collects the operations and the security schemes.
# ---------------------------------------------------------------------------

$SpecDocument = Get-Content -Path $Spec -Raw | ConvertFrom-Json -AsHashtable -Depth 200
if ($SpecDocument -isnot [System.Collections.IDictionary] -OR $SpecDocument['paths'] -isnot [System.Collections.IDictionary]) {
    throw [System.ArgumentException]::new("Spec must be an OpenAPI spec with a paths object, got '$Spec'.")
}
$Operations    = Get-UnwireOperation -Document $SpecDocument
$SpecSchemes   = $SpecDocument['components']?['securitySchemes'] ?? @{}

# ---------------------------------------------------------------------------
# Files
#   Parses every PowerShell file, a syntax error is a finding.
# ---------------------------------------------------------------------------

$Files = foreach ($file in Get-ChildItem -Path $ModuleRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1') {
    $tokens = $null
    $errors = $null
    $ast    = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
    $relative = [System.IO.Path]::GetRelativePath($ModuleRoot, $file.FullName).Replace('\', '/')
    foreach ($parseError in $errors) {
        Add-UnwireFinding -Severity Error -Location "$($relative):$($parseError.Extent.StartLineNumber)" -Rule 'parse' -Message $parseError.Message
    }
    [PSCustomObject]@{ Relative = $relative; File = $file; Ast = $ast; Text = $ast.Extent.Text; HasErrors = $errors.Count -GT 0 }
}
$Files = @($Files)
Write-Verbose "[Test-UnwireModule] $ModuleName`: $($Files.Count) files, $($Operations.Count) operations in the spec."

# ===========================================================================
# ============================   CHECK MODULE   =============================
# ===========================================================================
#
#   1. Layout       Manifest, root module, meta.json, the wrapper, Connect.
#   2. Functions    One function per file, exports and dot-sources agree.
#   3. Operations   Method, path, selection, writes, warnings and security.
#   4. Requests     Only the wrapper sends, nothing stores a session value.
#   5. Chapters     Sections only inside chapters, every chapter in the table of
#                   contents, banners 75 characters wide.
#   6. Import       Imports in a child process, exports what the manifest says.
#

# ---------------------------------------------------------------------------
# Layout
#   Manifest, root module, meta.json, the wrapper, Connect.
# ---------------------------------------------------------------------------

foreach ($required in "$ModuleName.psd1", "$ModuleName.psm1", 'meta.json', "functions/$Wrapper.ps1", 'data/security.schemes.json') {
    if (-NOT (Test-Path -Path (Join-Path -Path $ModuleRoot -ChildPath $required) -PathType Leaf)) {
        Add-UnwireFinding -Severity Error -Location $required -Rule 'layout' -Message "The module must have '$required', see references/ReferenceHard."
    }
}

$Manifest = $null
$manifestFile = Join-Path -Path $ModuleRoot -ChildPath "$ModuleName.psd1"
if (Test-Path -Path $manifestFile -PathType Leaf) {
    try {
        $Manifest = Import-PowerShellDataFile -Path $manifestFile
    }
    catch {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'manifest' -Message "The manifest must be a valid data file: $($_.Exception.Message)"
    }
}
if ($null -NE $Manifest -AND $Manifest['RootModule'] -NE "$ModuleName.psm1") {
    Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'manifest' -Message "RootModule must be '$ModuleName.psm1', got '$($Manifest['RootModule'])'."
}

# The schemes file is the spec's securitySchemes: the wrapper reads it, a drift sends the wrong header.
$schemesFile = Join-Path -Path $ModuleRoot -ChildPath 'data/security.schemes.json'
if (Test-Path -Path $schemesFile -PathType Leaf) {
    $moduleSchemes = Get-Content -Path $schemesFile -Raw | ConvertFrom-Json -AsHashtable
    $moduleSchemes = $moduleSchemes ?? @{}
    foreach ($name in @($SpecSchemes.Keys) + @($moduleSchemes.Keys) | Sort-Object -Unique) {
        $specScheme   = $SpecSchemes[$name]
        $moduleScheme = $moduleSchemes[$name]
        if ($null -EQ $specScheme -OR $null -EQ $moduleScheme) {
            Add-UnwireFinding -Severity Error -Location 'data/security.schemes.json' -Rule 'schemes' -Message "Scheme '$name' must be in both the spec and data/security.schemes.json, copy components.securitySchemes as it is."
            continue
        }
        foreach ($field in $SCHEME_FIELDS | Where-Object { [System.String] $specScheme[$_] -CNE [System.String] $moduleScheme[$_] }) {
            Add-UnwireFinding -Severity Error -Location 'data/security.schemes.json' -Rule 'schemes' -Message "Scheme '$name' must have $field '$($specScheme[$field])' as in the spec, got '$($moduleScheme[$field])'."
        }
    }
}

# ---------------------------------------------------------------------------
# Functions
#   One function per file, exports and dot-sources agree.
# ---------------------------------------------------------------------------

$FunctionFiles = @($Files | Where-Object { $_.Relative -LIKE 'functions/*' -AND $_.File.Extension -EQ '.ps1' -AND -NOT $_.File.Name.StartsWith('#') })
$Functions     = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($entry in $FunctionFiles | Where-Object { -NOT $_.HasErrors }) {
    $definitions = @($entry.Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
    if ($definitions.Count -NE 1 -OR $definitions[0].Name -NE $entry.File.BaseName) {
        Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'one-function' -Message "The file must define exactly one function named '$($entry.File.BaseName)', got $($definitions.Count): $($definitions.Name -join ', ')."
        continue
    }
    $Functions.Add([PSCustomObject]@{ Name = $definitions[0].Name; Ast = $definitions[0]; Entry = $entry })
}

# Verb-<Name><Noun> with an approved verb: 'Lock-NasAccount', not 'Lock-Account' or 'Do-NasThing'
$approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
foreach ($function in $Functions) {
    $verb, $noun = $function.Name -split '-', 2
    if ($verb -NOTIN $approvedVerbs -OR -NOT ([System.String] $noun).StartsWith($ModuleName, [System.StringComparison]::Ordinal)) {
        Add-UnwireFinding -Severity Error -Location $function.Entry.Relative -Rule 'naming' -Message "'$($function.Name)' must be <approved verb>-$ModuleName<Noun> (Get-Verb lists the verbs)."
    }
}
if ($Functions.Name -NOTCONTAINS "Connect-$ModuleName") {
    Add-UnwireFinding -Severity Error -Location 'functions' -Rule 'layout' -Message "The module must have 'Connect-$ModuleName', it sets the base URL and the session in memory."
}

# FunctionsToExport, the dot-sources of the .psm1 and the function files: three lists, one set
$psm1 = $Files | Where-Object { $_.Relative -EQ "$ModuleName.psm1" } | Select-Object -First 1
if ($null -NE $Manifest -AND $null -NE $psm1) {
    $exported = @($Manifest['FunctionsToExport'])
    if (@($exported | Where-Object { $_ -MATCH '[*?]' }).Count -GT 0) {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'manifest' -Message 'FunctionsToExport must list every function by name, no wildcards.'
    }
    foreach ($name in $Functions.Name | Where-Object { $_ -NOTIN $exported }) {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'manifest' -Message "FunctionsToExport must list '$name'."
    }
    foreach ($name in $exported | Where-Object { $_ -NOTMATCH '[*?]' -AND $_ -NOTIN $Functions.Name }) {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'manifest' -Message "FunctionsToExport names '$name', but no file in functions/ defines it."
    }

    # '. "$PSScriptRoot/functions/accounts/Get-NasAccount.ps1"' => 'functions/accounts/Get-NasAccount.ps1'
    $sourced = @([System.Text.RegularExpressions.Regex]::Matches($psm1.Text, '(?m)^\s*\.\s+["'']\$PSScriptRoot[/\\](?<file>[^"'']+)["'']') | ForEach-Object { $_.Groups['file'].Value.Replace('\', '/') })
    foreach ($entry in $FunctionFiles | Where-Object { $_.Relative -NOTIN $sourced }) {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psm1" -Rule 'manifest' -Message "The .psm1 must dot-source '$($entry.Relative)'."
    }
    foreach ($file in $sourced | Where-Object { -NOT (Test-Path -Path (Join-Path -Path $ModuleRoot -ChildPath $_) -PathType Leaf) }) {
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psm1" -Rule 'manifest' -Message "The .psm1 dot-sources '$file', which does not exist."
    }
}

# ---------------------------------------------------------------------------
# Operations
#   Method, path, selection, writes, warnings and security.
# ---------------------------------------------------------------------------

$Covered = @{}     # operationId => function, for the selection below
foreach ($function in $Functions) {
    $location = $function.Entry.Relative
    $notes    = [System.String] $function.Ast.GetHelpContent()?.Notes
    $note     = [System.Text.RegularExpressions.Regex]::Match($notes, $OPERATION_NOTE)
    if (-NOT $note.Success) {
        # Connect, Disconnect, the wrapper and helpers stand for no operation.
        continue
    }

    $id        = $note.Groups['id'].Value
    $operation = $Operations[$id]
    if ($null -EQ $operation) {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'operation' -Message "Operation '$id' in .NOTES must be an operationId of the spec."
        continue
    }
    if ($Covered.ContainsKey($id)) {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'operation' -Message "Operation '$id' must have one function, '$($Covered[$id])' has it already."
        continue
    }
    $Covered[$id] = $function.Name

    if ($note.Groups['method'].Value -NE $operation.Method -OR $note.Groups['path'].Value -CNE $operation.Path) {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'operation' -Message "Operation '$id' must be '$($operation.Method.ToUpper()) $($operation.Path)' as in the spec, got '$($note.Groups['method'].Value) $($note.Groups['path'].Value)'."
    }
    # The request itself: Method and Path of the splat must be the ones of the spec.
    $sentPath   = [System.Text.RegularExpressions.Regex]::Match($function.Ast.Extent.Text, '(?m)^\s*Path\s*=\s*[''"](?<path>[^''"]+)[''"]').Groups['path'].Value
    $sentMethod = [System.Text.RegularExpressions.Regex]::Match($function.Ast.Extent.Text, '(?m)^\s*Method\s*=\s*[''"](?<method>[A-Za-z]+)[''"]').Groups['method'].Value
    if ($sentPath -CNE $operation.Path -OR $sentMethod -NE $operation.Method) {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'operation' -Message "The request must send '$($operation.Method.ToUpper()) $($operation.Path)' (Method and Path of the splat), got '$sentMethod $sentPath'."
    }

    # A write asks first: ShouldProcess with ConfirmImpact High, so even -Confirm:$false is a decision.
    if ($operation.IsWrite) {
        $hasShouldProcess = (Get-UnwireBinding -Function $function.Ast -Name 'SupportsShouldProcess') -EQ '$true'
        $isHighImpact     = (Get-UnwireBinding -Function $function.Ast -Name 'ConfirmImpact') -EQ 'High'
        $callsCheck       = $null -NE $function.Ast.Find({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -AND $args[0].Member.Extent.Text -EQ 'ShouldProcess' }, $true)
        if (-NOT ($hasShouldProcess -AND $isHighImpact -AND $callsCheck)) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'write' -Message "Operation '$id' changes the device: it must have SupportsShouldProcess, ConfirmImpact 'High' and call `$PSCmdlet.ShouldProcess before sending."
        }
    }

    # An unsure operation says so on every call.
    if ($operation.Confidence -IN $UNSURE_LEVELS -AND (Get-UnwireCommandName -Ast $function.Ast) -NOTCONTAINS 'Write-Warning') {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'warning' -Message "Operation '$id' has confidence $($operation.Confidence): the function must Write-Warning what is unsure."
    }

    $securityMatch = [System.Text.RegularExpressions.Regex]::Match($function.Ast.Extent.Text, $SECURITY_LIST)
    $sentSecurity  = @(
        [System.Text.RegularExpressions.Regex]::Matches($securityMatch.Groups['list'].Value, '[''"](?<name>[^''"]+)[''"]')
        | ForEach-Object { $_.Groups['name'].Value }
        | Sort-Object
    )
    if (($sentSecurity -join ',') -CNE ($operation.Security -join ',')) {
        Add-UnwireFinding -Severity Error -Location $location -Rule 'security' -Message "Operation '$id' must send Security = @($(($operation.Security | ForEach-Object { "'$_'" }) -join ', ')) as in the spec, got @($(($sentSecurity | ForEach-Object { "'$_'" }) -join ', '))."
    }
}

foreach ($id in @($OperationId) | Where-Object { -NOT [System.String]::IsNullOrEmpty($_) }) {
    if (-NOT $Operations.ContainsKey($id)) {
        Add-UnwireFinding -Severity Error -Location 'OperationId' -Rule 'selection' -Message "Picked operation '$id' must be an operationId of the spec."
    }
    elseif (-NOT $Covered.ContainsKey($id)) {
        Add-UnwireFinding -Severity Error -Location 'functions' -Rule 'selection' -Message "Picked operation '$id' ($($Operations[$id].Method.ToUpper()) $($Operations[$id].Path)) must have a function with 'Operation:' in its .NOTES."
    }
}
if ($null -NE $OperationId) {
    foreach ($id in $Covered.Keys | Where-Object { $_ -NOTIN $OperationId }) {
        Add-UnwireFinding -Severity Warning -Location 'functions' -Rule 'selection' -Message "'$($Covered[$id])' stands for '$id', which the user did not pick."
    }
}

# ---------------------------------------------------------------------------
# Requests
#   Only the wrapper sends, nothing stores a session value.
# ---------------------------------------------------------------------------

foreach ($entry in $Files | Where-Object { -NOT $_.HasErrors }) {
    $commands  = Get-UnwireCommandName -Ast $entry.Ast
    $isWrapper = $entry.Relative -EQ "functions/$Wrapper.ps1"

    foreach ($command in $commands | Where-Object { $_ -IN $REQUEST_COMMANDS } | Sort-Object -Unique) {
        if (-NOT $isWrapper -OR $command -NE 'Invoke-WebRequest') {
            Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'request' -Message "'$command' must not be called here: only $Wrapper sends, with Invoke-WebRequest."
        }
    }
    if ($entry.Text -MATCH $REQUEST_TYPES) {
        Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'request' -Message "'$($Matches[0])' must not be used: only $Wrapper sends, with Invoke-WebRequest."
    }
    foreach ($command in $commands | Where-Object { $_ -IN $STORAGE_COMMANDS } | Sort-Object -Unique) {
        Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'storage' -Message "'$command' must not be called: the module keeps the session in memory and writes no file."
    }
    if ($entry.Text -MATCH $STORAGE_TEXT) {
        Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'storage' -Message "'$($Matches[0].Trim())' must not be used: the module keeps the session in memory, no file, environment or global variable."
    }
}

# The wrapper follows no redirect: a 3xx would hand the session headers to the next host.
$wrapperEntry = $Files | Where-Object { $_.Relative -EQ "functions/$Wrapper.ps1" } | Select-Object -First 1
if ($null -NE $wrapperEntry -AND $wrapperEntry.Text -NOTMATCH '(?m)^\s*MaximumRedirection\s*=\s*0\b') {
    Add-UnwireFinding -Severity Error -Location $wrapperEntry.Relative -Rule 'request' -Message "$Wrapper must send with MaximumRedirection = 0, see references/ReferenceHard."
}

# ---------------------------------------------------------------------------
# Chapters
#   Sections only inside chapters, every chapter in the table of
#   contents, banners 75 characters wide.
# ---------------------------------------------------------------------------

foreach ($entry in $Files) {
    $lines        = $entry.Text -split '\r?\n'
    $bannerLines  = @($lines | Where-Object { $_ -MATCH $BANNER_LINE })
    # '# ====   BUILD REQUEST   ====' => 'BUILD REQUEST'
    $chapters     = @($lines | ForEach-Object { [System.Text.RegularExpressions.Regex]::Match($_, $CHAPTER_TITLE) } | Where-Object Success | ForEach-Object { $_.Groups['title'].Value })
    $firstChapter = [System.Array]::FindIndex([System.String[]] $lines, [System.Predicate[System.String]] { param ($line) $line -MATCH $CHAPTER_TITLE })
    $firstSection = [System.Array]::FindIndex([System.String[]] $lines, [System.Predicate[System.String]] { param ($line) $line -MATCH '^\s*# -{3,}\s*$' })

    foreach ($line in $bannerLines | Where-Object { $_.Trim().Length -NE $BANNER_WIDTH + 2 }) {
        Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'chapters' -Message "Banner lines must be $BANNER_WIDTH characters after '# ', got $($line.Trim().Length - 2): '$($line.Trim())'."
    }
    # A section before the first chapter title stands outside any chapter (-1: none found).
    if ($firstSection -GE 0 -AND ($firstChapter -LT 0 -OR $firstSection -LT $firstChapter)) {
        Add-UnwireFinding -Severity Error -Location "$($entry.Relative):$($firstSection + 1)" -Rule 'chapters' -Message 'Sections must stand inside a chapter: add a chapter banner with numbered steps, see Invoke-ReferenceHardRest.ps1 of the reference.'
    }
    if ($chapters.Count -GT 0) {
        # '#     BUILD REQUEST   Validations, ...' below '#   Chapters:'
        $contents = [System.Text.RegularExpressions.Regex]::Match($entry.Text, '(?ms)^#\s+Chapters:\s*$(?<list>.*?)^#\s*$').Groups['list'].Value
        foreach ($title in $chapters | Where-Object { $contents -NOTMATCH "(?m)^#\s+$([System.Text.RegularExpressions.Regex]::Escape($_))\s" }) {
            Add-UnwireFinding -Severity Error -Location $entry.Relative -Rule 'chapters' -Message "Chapter '$title' must be in the 'Chapters:' table of contents at the top of the file."
        }
    }
}

# ---------------------------------------------------------------------------
# Import
#   Imports in a child process, exports what the manifest says.
# ---------------------------------------------------------------------------

$hasBlocker = @($Findings | Where-Object { $_.Severity -EQ 'Error' -AND $_.Rule -IN @('parse', 'request', 'storage') }).Count -GT 0
if ($SkipImport.IsPresent -OR $null -EQ $Manifest -OR $hasBlocker) {
    Write-Verbose "[Test-UnwireModule] Import skipped (SkipImport, no manifest or a parse, request or storage error)."
}
else {
    # Loads the module only: no function runs, nothing is sent. One marked line answers,
    # 'UNWIRE-EXPORTS:["Get-NasShare"]' or 'UNWIRE-ERROR:<message>'.
    $probe = @(
        'try {'
        "    Import-Module -Name '$($manifestFile.Replace("'", "''"))' -ErrorAction Stop"
        "    'UNWIRE-EXPORTS:' + ((Get-Command -Module '$ModuleName').Name | Sort-Object | ConvertTo-Json -Compress -AsArray)"
        '}'
        'catch {'
        "    'UNWIRE-ERROR:' + `$_.Exception.Message"
        '}'
    ) -join "`n"
    $output  = @(& pwsh -NoProfile -NonInteractive -Command $probe 2>&1 | ForEach-Object { [System.String] $_ })
    $answer  = $output | Where-Object { $_ -MATCH '^UNWIRE-(?:EXPORTS|ERROR):' } | Select-Object -Last 1
    if ($null -EQ $answer -OR $answer.StartsWith('UNWIRE-ERROR:')) {
        $reason = $null -EQ $answer ? ($output -join ' ').Trim() : $answer.Substring('UNWIRE-ERROR:'.Length)
        Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'import' -Message "Import-Module must succeed: $reason"
    }
    else {
        $imported = @($answer.Substring('UNWIRE-EXPORTS:'.Length) | ConvertFrom-Json)
        foreach ($name in @($Manifest['FunctionsToExport']) | Where-Object { $_ -NOTIN $imported }) {
            Add-UnwireFinding -Severity Error -Location "$ModuleName.psd1" -Rule 'import' -Message "'$name' must be a command of the imported module."
        }
    }
}

# ===========================================================================
# ===========================   REPORT FINDINGS   ===========================
# ===========================================================================
#
#   1. Report   Returns the findings, errors first.
#

# ---------------------------------------------------------------------------
# Report
#   Returns the findings, errors first.
# ---------------------------------------------------------------------------

Write-Verbose "[Test-UnwireModule] $($Functions.Count) functions, $($Covered.Count) operations, $($Findings.Count) findings."
return $Findings | Sort-Object -Property @{ Expression = { $_.Severity -EQ 'Warning' } }, Location -Stable
