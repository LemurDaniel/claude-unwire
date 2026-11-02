# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helpers only build objects and write fixtures into TestDrive.')]
param ()

# ===========================================================================
# ========================   VALIDATE UNWIRE SPEC   =========================
# ===========================================================================
#
#   valid_spec              Returns nothing for a valid spec.
#   invalid_json            Reports invalid JSON as the only finding.
#   openapi_version         Rejects a Swagger 2.0 spec.
#   missing_extensions      Reports missing x-unwire-* extensions as errors.
#   discovered_spec         Reports missing x-unwire-* only as warnings for discover specs.
#   bad_confidence          Rejects a confidence outside high, medium, low.
#   write_without_impact    Requires x-unwire-impact: write on a POST.
#   path_parameter          Requires every path parameter to be declared and required.
#   path_parameter_ref      Resolves a path parameter declared via $ref.
#   duplicate_operation_id  Rejects an operationId used twice.
#   broken_ref              Rejects a $ref to a missing target.
#   low_without_open        Warns on low confidence without open points.
#   root_open_points        Rejects root x-unwire-open that is no list of strings.
#   example_spec            Returns nothing for examples/grafana/openapi.json.
#   errors_first            Returns errors before warnings.
#   missing_file            Fails early on a missing file.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../Test-UnwireSpec.ps1'

    # A valid operation, every test changes only what it checks.
    function New-TestOperation {
        param ([System.String] $OperationId = 'getDevices')
        return [ordered]@{
            operationId           = $OperationId
            responses             = @{ '200' = @{ description = 'OK' } }
            'x-unwire-source'     = 'assets/app.js:12'
            'x-unwire-confidence' = 'high'
            'x-unwire-verified'   = $false
        }
    }

    function New-TestSpec {
        param ([System.Collections.IDictionary] $Paths = @{ '/api/devices' = @{ get = (New-TestOperation) } })
        return [ordered]@{
            openapi = '3.1.0'
            info    = @{ title = 'Router API'; version = '1.0.0' }
            paths   = $Paths
        }
    }

    # Writes a spec into TestDrive and returns its path.
    function Set-TestSpec {
        param ([System.Object] $Spec)
        $file = Join-Path -Path $TestDrive -ChildPath "$([System.Guid]::NewGuid().ToString('N')).json"
        $text = if ($Spec -is [System.String]) { $Spec } else { $Spec | ConvertTo-Json -Depth 20 }
        Set-Content -Path $file -Value $text
        return $file
    }
}

Describe 'Test-UnwireSpec' {
    It 'valid_spec: returns nothing for a valid spec' {
        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec)))

        $findings.Count | Should -Be 0
    }

    It 'invalid_json: reports invalid JSON as the only finding' {
        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec '{ "openapi": '))

        $findings.Count       | Should -Be 1
        $findings[0].Rule     | Should -Be 'json'
        $findings[0].Severity | Should -Be 'Error'
    }

    It 'openapi_version: rejects a Swagger 2.0 spec' {
        $spec = New-TestSpec
        $spec.Remove('openapi')
        $spec['swagger'] = '2.0'

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec $spec))

        $findings.Rule | Should -Be @('openapi-version')
    }

    It 'missing_extensions: reports missing x-unwire-* extensions as errors' {
        $operation = New-TestOperation
        'x-unwire-source', 'x-unwire-confidence', 'x-unwire-verified' | ForEach-Object { $operation.Remove($_) }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths @{ '/api/devices' = @{ get = $operation } })))

        $findings.Rule     | Sort-Object | Should -Be @('x-unwire-confidence', 'x-unwire-source', 'x-unwire-verified')
        $findings.Severity | Sort-Object -Unique | Should -Be 'Error'
    }

    It 'discovered_spec: reports missing x-unwire-* only as warnings for discover specs' {
        $operation = New-TestOperation
        'x-unwire-source', 'x-unwire-confidence', 'x-unwire-verified' | ForEach-Object { $operation.Remove($_) }
        $spec = New-TestSpec -Paths @{ '/api/devices' = @{ get = $operation } }
        $spec['x-unwire-source'] = 'discover:openapi.json'

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec $spec))

        $findings.Count    | Should -Be 3
        $findings.Severity | Sort-Object -Unique | Should -Be 'Warning'
    }

    It 'bad_confidence: rejects a confidence outside high, medium, low' {
        $operation = New-TestOperation
        $operation['x-unwire-confidence'] = 'sure'

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths @{ '/api/devices' = @{ get = $operation } })))

        $findings.Rule       | Should -Be @('x-unwire-confidence')
        $findings[0].Message | Should -BeLike "*got 'sure'*"
    }

    It 'write_without_impact: requires x-unwire-impact: write on a POST' {
        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths @{ '/api/wlan' = @{ post = (New-TestOperation -OperationId 'setWlan') } })))

        $findings.Rule        | Should -Be @('x-unwire-impact')
        $findings[0].Location | Should -Be "paths['/api/wlan'].post"
    }

    It 'path_parameter: requires every path parameter to be declared and required' {
        $missing  = New-TestOperation -OperationId 'getDevice'
        $optional = New-TestOperation -OperationId 'getPort'
        $optional['parameters'] = @(@{ name = 'port'; in = 'path'; required = $false })
        $paths = [ordered]@{
            '/api/devices/{id}'   = @{ get = $missing }
            '/api/ports/{port}'   = @{ get = $optional }
        }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)))

        $findings.Message | Should -Be @(
            "Path parameter 'id' must be declared with in: path."
            "Path parameter 'port' must have required: true."
        )
    }

    It 'path_parameter_ref: resolves a path parameter declared via $ref' {
        $spec = New-TestSpec -Paths @{ '/api/devices/{id}' = @{ parameters = @(@{ '$ref' = '#/components/parameters/DeviceId' }); get = (New-TestOperation) } }
        $spec['components'] = @{ parameters = @{ DeviceId = @{ name = 'id'; in = 'path'; required = $true } } }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec $spec))

        $findings.Count | Should -Be 0
    }

    It 'duplicate_operation_id: rejects an operationId used twice' {
        $paths = [ordered]@{
            '/api/a' = @{ get = (New-TestOperation -OperationId 'getThing') }
            '/api/b' = @{ get = (New-TestOperation -OperationId 'getThing') }
        }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)))

        $findings.Rule       | Should -Be @('operation-id')
        $findings[0].Message | Should -Be "operationId 'getThing' must be unique, already used at paths['/api/a'].get."
    }

    It 'broken_ref: rejects a $ref to a missing target' {
        $operation = New-TestOperation
        $operation['responses'] = @{ '200' = @{ description = 'OK'; content = @{ 'application/json' = @{ schema = @{ '$ref' = '#/components/schemas/Device' } } } } }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths @{ '/api/devices' = @{ get = $operation } })))

        $findings.Rule       | Should -Be @('ref')
        $findings[0].Message | Should -Be "`$ref '#/components/schemas/Device' must point to an existing target."
    }

    It 'low_without_open: warns on low confidence without open points' {
        $operation = New-TestOperation
        $operation['x-unwire-confidence'] = 'low'

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths @{ '/api/devices' = @{ get = $operation } })))

        $findings.Rule        | Should -Be @('x-unwire-open')
        $findings[0].Severity | Should -Be 'Warning'
    }

    It 'root_open_points: rejects root x-unwire-open that is no list of strings' {
        $spec = New-TestSpec
        $spec['x-unwire-open'] = 'Auth unclear'

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec $spec))

        $findings.Location | Should -Be @('x-unwire-open')
    }

    It 'example_spec: returns nothing for examples/grafana/openapi.json' {
        $findings = @(& $SCRIPT_PATH -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../../examples/grafana/openapi.json'))

        $findings.Count | Should -Be 0
    }

    It 'errors_first: returns errors before warnings' {
        $low = New-TestOperation -OperationId 'getA'
        $low['x-unwire-confidence'] = 'low'
        $paths = [ordered]@{
            '/api/a' = @{ get = $low }
            '/api/b' = @{ post = (New-TestOperation -OperationId 'setB') }
        }

        $findings = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)))

        $findings.Severity | Should -Be @('Error', 'Warning')
    }

    It 'missing_file: fails early on a missing file' {
        { & $SCRIPT_PATH -Path (Join-Path -Path $TestDrive -ChildPath 'nope.json') } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must be an existing openapi.json file*'
    }
}
