# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks and mocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helpers only build objects and write fixtures into TestDrive.')]
param ()

# ===========================================================================
# ===========================   TEST SAFE GETS   ============================
# ===========================================================================
#
#   plan_only               Lists planned and skipped operations, sends and writes nothing.
#   read_get_only           Plans only GET with impact read, never a write operation.
#   denylist                Never plans a path or a value on the denylist.
#   live_denylist           Never plans a GET that may create a token or return a credential.
#   path_values             Needs a value for every path parameter, escapes it in the URI.
#   required_query          Needs a value for a required query, sends given query values.
#   anonymous_pass          Sends every planned GET once without a session, no redirect.
#   session_pass            Sends a second time with the session, never writes its value.
#   verified_and_shape      Marks 2xx as verified and fills an empty schema with the shape.
#   target_written          Writes the target into a spec without x-unwire-target.
#   no_values_written       Writes keys and types only, no value of a body reaches a file.
#   data_keys               Turns an object with data keys into additionalProperties.
#   published_schema_kept   Never replaces a schema that is not empty.
#   security_hint           Notes an answer that contradicts the security of the operation.
#   live_note_replaced      Replaces its own open point on a second run.
#   max_requests            Stops at MaxRequests and reports the rest as skipped.
#   results_file            Writes live-get.json with status and media type per pass.
#   progress                Shows each request as path template, never the session.
#   window_done             Ends with the done line only in a window.
#   server_origin           Fails before any request when the server leaves the origin.
#   bad_value               Fails early on a value that is not name=value.
#   untrusted_certificate   Stops at the first request and names SkipCertificateCheck.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Test-UnwireGet.ps1'
    $TARGET_URI  = 'http://router.test'

    function New-TestResponse {
        param ([System.Int32] $StatusCode = 200, [System.String] $Content = '', [System.String] $ContentType = 'application/json; charset=utf-8')
        return [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content; Headers = @{ 'Content-Type' = @($ContentType) } }
    }

    # A derived operation with every x-unwire-* set, each test changes only what it checks.
    function New-TestOperation {
        param ([System.String] $OperationId, [System.String] $Impact = 'read', [System.Object[]] $Security = @(), [System.Object[]] $Parameters = @())
        return [ordered]@{
            operationId           = $OperationId
            parameters            = $Parameters
            responses             = [ordered]@{ '200' = [ordered]@{ description = 'OK'; content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{} } } } }
            security              = $Security
            'x-unwire-source'     = 'assets/app.js:1'
            'x-unwire-confidence' = 'high'
            'x-unwire-verified'   = $false
            'x-unwire-impact'     = $Impact
        }
    }

    function New-TestSpec {
        param ([System.Collections.IDictionary] $Paths, [System.String] $Server = '/api')
        return [ordered]@{
            openapi    = '3.1.0'
            info       = @{ title = 'Router API'; version = '1.0.0' }
            servers    = @(@{ url = $Server })
            components = @{ securitySchemes = @{ cookieAuth = @{ type = 'apiKey'; in = 'cookie'; name = 'sid' } } }
            paths      = $Paths
        }
    }

    # Writes a spec into its own folder in TestDrive and returns its path.
    function Set-TestSpec {
        param ([System.Collections.IDictionary] $Spec)
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        $file   = Join-Path -Path $folder -ChildPath 'openapi.json'
        $Spec | ConvertTo-Json -Depth 30 | Set-Content -Path $file
        return $file
    }

    function Get-TestSpec {
        param ([System.String] $File)
        return Get-Content -Path $File -Raw | ConvertFrom-Json -AsHashtable
    }
}

Describe 'Test-UnwireGet' {
    BeforeEach {
        # The fake device: absolute URI => response, everything else answers 404.
        $Site = @{}
        Mock Invoke-WebRequest {
            $response = $Site[$Uri.AbsoluteUri]
            if ($null -EQ $response) { return New-TestResponse -StatusCode 404 -ContentType 'text/plain' }
            # Mirrors pwsh 7.4+: a 3xx under MaximumRedirection 0 also writes this error.
            if ($response.StatusCode -GE 300 -AND $response.StatusCode -LT 400) {
                Write-Error -Message 'The maximum redirection count has been exceeded.' -ErrorId 'MaximumRedirectExceeded'
            }
            $response
        }
        Mock Start-Sleep { }
    }

    It 'plan_only: lists planned and skipped operations, sends and writes nothing' {
        $file   = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } })
        $before = Get-Content -Path $file -Raw

        $plan = @(& $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Plan)

        $plan.OperationId | Should -Be @('getStatus')
        $plan.Status      | Should -Be @('planned')
        $plan.Uri         | Should -Be @([System.Uri] 'http://router.test/api/status')
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Get-Content -Path $file -Raw                                         | Should -Be $before
        Join-Path -Path (Split-Path -Path $file -Parent) -ChildPath 'live-get.json' | Should -Not -Exist
    }

    It 'read_get_only: plans only GET with impact read, never a write operation' {
        $paths = @{
            '/status'       = @{ get = (New-TestOperation -OperationId 'getStatus'); post = (New-TestOperation -OperationId 'setStatus' -Impact 'write') }
            '/wlan/refresh' = @{ get = (New-TestOperation -OperationId 'refreshWlan' -Impact 'write') }
        }

        $plan = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)) -Uri $TARGET_URI -Plan)

        ($plan | Where-Object Status -EQ 'planned').OperationId | Should -Be @('getStatus')
        ($plan | Where-Object OperationId -EQ 'refreshWlan').Reason | Should -Be "x-unwire-impact is 'write', not read"
        $plan.OperationId | Should -Not -Contain 'setStatus'
    }

    It 'denylist: never plans a path or a value on the denylist' {
        $paths = @{
            '/logout'         = @{ get = (New-TestOperation -OperationId 'logout') }
            '/config/{name}'  = @{ get = (New-TestOperation -OperationId 'getConfig' -Parameters @(@{ name = 'name'; in = 'path'; required = $true })) }
        }

        $plan = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)) -Uri $TARGET_URI -Value 'name=factory-reset' -Plan)

        $plan.Status | Should -Be @('skipped', 'skipped')
        $plan.Reason | Should -Be @('on the denylist (logout, reboot, delete, ...)', 'on the denylist (logout, reboot, delete, ...)')
    }

    It 'live_denylist: never plans a GET that may create a token or return a credential' {
        $paths = @{
            '/runners/registration-token' = @{ get = (New-TestOperation -OperationId 'getRunnerToken') }
            '/config/backup'              = @{ get = (New-TestOperation -OperationId 'getBackup') }
        }

        $plan = @(& $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)) -Uri $TARGET_URI -Plan)

        $plan.Status | Should -Be @('skipped', 'skipped')
        $plan.Reason | Should -Be @('may create a token or return a credential (token, secret, backup, ...)', 'may create a token or return a credential (token, secret, backup, ...)')
    }

    It 'path_values: needs a value for every path parameter, escapes it in the URI' {
        $operation = New-TestOperation -OperationId 'getRepo' -Parameters @(@{ name = 'owner'; in = 'path'; required = $true }, @{ name = 'repo'; in = 'path'; required = $true })
        $file      = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/repos/{owner}/{repo}' = @{ get = $operation } })

        $without = @(& $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Value 'owner=me' -Plan)
        $with    = @(& $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Value 'owner=me,repo=my notes' -Plan)

        $without.Reason          | Should -Be @("needs a value for 'repo'")
        $with.Status             | Should -Be @('planned')
        $with[0].Uri.AbsoluteUri | Should -Be 'http://router.test/api/repos/me/my%20notes'
    }

    It 'required_query: needs a value for a required query, sends given query values' {
        $operation = New-TestOperation -OperationId 'search' -Parameters @(@{ name = 'q'; in = 'query'; required = $true }, @{ name = 'limit'; in = 'query' })
        $file      = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/search' = @{ get = $operation } })

        $without = @(& $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Plan)
        $with    = @(& $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Value 'q=lamp', 'limit=5' -Plan)

        $without.Reason          | Should -Be @("needs a value for the query 'q'")
        $with[0].Uri.AbsoluteUri | Should -Be 'http://router.test/api/search?q=lamp&limit=5'
    }

    It 'anonymous_pass: sends every planned GET once without a session, no redirect' {
        $Site['http://router.test/api/status'] = New-TestResponse -StatusCode 302 -ContentType 'text/html'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } })

        $summary = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $summary.Requests | Should -Be 1
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -EQ 'Get' -AND $MaximumRedirection -EQ 0 -AND -NOT $Headers.ContainsKey('Cookie') }
        (Get-TestSpec -File $file)['paths']['/status']['get']['x-unwire-open'] | Should -Be @('Live GET ' + (Get-Date -Format 'yyyy-MM-dd') + ': without session HTTP 302 text/html, with session not sent.')
    }

    It 'session_pass: sends a second time with the session, never writes its value' {
        $Site['http://router.test/api/status'] = New-TestResponse -Content '{"uptime":12}'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus' -Security @(@{ cookieAuth = @() })) } })
        $env:UNWIRE_TEST_COOKIE = 'sid=TOP-SECRET-VALUE'

        try {
            $summary = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI -UseSession -SessionVariable UNWIRE_TEST_COOKIE
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_COOKIE
        }

        $summary.Requests | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'sid=TOP-SECRET-VALUE' }
        Get-ChildItem -Path (Split-Path -Path $file -Parent) -File | Get-Content -Raw | Should -Not -Match 'TOP-SECRET-VALUE'
    }

    It 'verified_and_shape: marks 2xx as verified and fills an empty schema with the shape' {
        $Site['http://router.test/api/devices'] = New-TestResponse -Content '[{"name":"lamp","online":true,"rssi":-61,"load":0.5}]'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/devices' = @{ get = (New-TestOperation -OperationId 'getDevices') } })

        $summary = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $operation = (Get-TestSpec -File $file)['paths']['/devices']['get']
        $schema    = $operation['responses']['200']['content']['application/json']['schema']
        $summary.Verified                         | Should -Be 1
        $operation['x-unwire-verified']           | Should -BeTrue
        $schema['type']                           | Should -Be 'array'
        $schema['items']['properties']['name']['type']    | Should -Be 'string'
        $schema['items']['properties']['online']['type']  | Should -Be 'boolean'
        $schema['items']['properties']['rssi']['type']    | Should -Be 'integer'
        $schema['items']['properties']['load']['type']    | Should -Be 'number'
        $operation['x-unwire-open'][-1]           | Should -Match 'Response schema from the live answer'
    }

    It 'target_written: writes the target into a spec without x-unwire-target, keeps an existing one' {
        $Site['http://router.test/api/devices'] = New-TestResponse -Content '[]'
        $file  = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/devices' = @{ get = (New-TestOperation -OperationId 'getDevices') } })
        $kept  = New-TestSpec -Paths @{ '/devices' = @{ get = (New-TestOperation -OperationId 'getDevices') } }
        $kept['x-unwire-target'] = 'http://router.test/start/'
        $keptFile = Set-TestSpec -Spec $kept

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI
        $null = & $SCRIPT_PATH -Path $keptFile -Uri $TARGET_URI

        (Get-TestSpec -File $file)['x-unwire-target']     | Should -Be ([System.Uri] $TARGET_URI).AbsoluteUri
        (Get-TestSpec -File $keptFile)['x-unwire-target'] | Should -Be 'http://router.test/start/'
    }

    It 'no_values_written: writes keys and types only, no value of a body reaches a file' {
        $Site['http://router.test/api/wlan'] = New-TestResponse -Content '{"ssid":"HomeNet-4711","key":"WLAN-PASSPHRASE"}'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/wlan' = @{ get = (New-TestOperation -OperationId 'getWlan') } })

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $written = Get-ChildItem -Path (Split-Path -Path $file -Parent) -File | Get-Content -Raw
        $written | Should -Not -Match 'HomeNet-4711'
        $written | Should -Not -Match 'WLAN-PASSPHRASE'
        (Get-TestSpec -File $file)['paths']['/wlan']['get']['responses']['200']['content']['application/json']['schema']['properties'].Keys | Should -Be @('ssid', 'key')
    }

    It 'data_keys: turns an object with data keys into additionalProperties' {
        $Site['http://router.test/api/stats'] = New-TestResponse -Content '{"user@home.test":{"commits":3},"guest@home.test":{"commits":1}}'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/stats' = @{ get = (New-TestOperation -OperationId 'getStats') } })

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $schema = (Get-TestSpec -File $file)['paths']['/stats']['get']['responses']['200']['content']['application/json']['schema']
        $schema['additionalProperties']['properties']['commits']['type'] | Should -Be 'integer'
        $schema.Contains('properties')                           | Should -BeFalse
        Get-Content -Path $file -Raw                             | Should -Not -Match 'home\.test'
    }

    It 'published_schema_kept: never replaces a schema that is not empty' {
        $Site['http://router.test/api/devices'] = New-TestResponse -Content '{"other":1}'
        $operation = New-TestOperation -OperationId 'getDevices'
        $operation['responses']['200']['content']['application/json']['schema'] = @{ '$ref' = '#/components/schemas/Devices' }
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/devices' = @{ get = $operation } })

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        (Get-TestSpec -File $file)['paths']['/devices']['get']['responses']['200']['content']['application/json']['schema']['$ref'] | Should -Be '#/components/schemas/Devices'
    }

    It 'security_hint: notes an answer that contradicts the security of the operation' {
        $Site['http://router.test/api/open']   = New-TestResponse -Content '{}'
        $Site['http://router.test/api/closed'] = New-TestResponse -StatusCode 401 -ContentType 'text/plain'
        $paths = @{
            '/open'   = @{ get = (New-TestOperation -OperationId 'getOpen' -Security @(@{ cookieAuth = @() })) }
            '/closed' = @{ get = (New-TestOperation -OperationId 'getClosed') }
        }
        $file = Set-TestSpec -Spec (New-TestSpec -Paths $paths)

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $spec = Get-TestSpec -File $file
        $spec['paths']['/open']['get']['x-unwire-open'][-1]   | Should -Match 'answered without a session, security may be \[\]'
        $spec['paths']['/closed']['get']['x-unwire-open'][-1] | Should -Match 'refused without a session although security is \[\]'
    }

    It 'live_note_replaced: replaces its own open point on a second run' {
        $Site['http://router.test/api/status'] = New-TestResponse -Content '{}'
        $operation = New-TestOperation -OperationId 'getStatus'
        $operation['x-unwire-open'] = @('auth unclear: no guard found.', 'Live GET 2020-01-01: without session HTTP 500, with session not sent.')
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = $operation } })

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $open = (Get-TestSpec -File $file)['paths']['/status']['get']['x-unwire-open']
        $open.Count | Should -Be 2
        $open[0]    | Should -Be 'auth unclear: no guard found.'
        $open[1]    | Should -Match 'without session HTTP 200 application/json'
    }

    It 'max_requests: stops at MaxRequests and reports the rest as skipped' {
        $paths = @{
            '/a' = @{ get = (New-TestOperation -OperationId 'getA') }
            '/b' = @{ get = (New-TestOperation -OperationId 'getB') }
            '/c' = @{ get = (New-TestOperation -OperationId 'getC') }
        }

        $summary = & $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)) -Uri $TARGET_URI -MaxRequests 2

        $summary.Requests | Should -Be 2
        $summary.Tested   | Should -Be 2
        $summary.Skipped  | Should -Be 1
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
    }

    It 'results_file: writes live-get.json with status and media type per pass' {
        $Site['http://router.test/api/status'] = New-TestResponse -Content '{"uptime":12}'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } })

        $summary = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI

        $results = Get-Content -Path $summary.OutputFile -Raw | ConvertFrom-Json -AsHashtable
        $results['target']                                    | Should -Be 'http://router.test'
        $results['operations'][0]['uri']                      | Should -Be 'http://router.test/api/status'
        $results['operations'][0]['anonymous']['status']      | Should -Be 200
        $results['operations'][0]['anonymous']['mediaType']   | Should -Be 'application/json'
        $results['operations'][0]['session']                  | Should -BeNullOrEmpty
    }

    It 'progress: shows each request as path template, never the session, then completes' {
        Mock Write-Progress { }
        $Site['http://router.test/api/devices/lamp'] = New-TestResponse -Content '{}'
        $operation = New-TestOperation -OperationId 'getDevice' -Parameters @(@{ name = 'id'; in = 'path'; required = $true })
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/devices/{id}' = @{ get = $operation } })
        $env:UNWIRE_TEST_COOKIE = 'sid=TOP-SECRET-VALUE'

        try {
            $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Value 'id=lamp' -UseSession -SessionVariable UNWIRE_TEST_COOKIE
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_COOKIE
        }

        Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter { $Status -EQ '1 / 2: GET /devices/{id} (without session)' -AND $PercentComplete -EQ 50 }
        Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter { $Status -EQ '2 / 2: GET /devices/{id} (with session)' -AND $PercentComplete -EQ 100 }
        Should -Invoke Write-Progress -Times 0 -Exactly -ParameterFilter { "$Status" -MATCH 'TOP-SECRET-VALUE' }
        Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter { $Completed }
    }

    It 'window_done: ends with the done line only in a window' {
        Mock Write-Host { }
        $Site['http://router.test/api/status'] = New-TestResponse -Content '{}'
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } })

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI
        Should -Invoke Write-Host -Times 0 -Exactly

        $null = & $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Window -Language de
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -LIKE 'Fertig. Lies die Warnungen oben*' }
    }

    It 'server_origin: fails before any request when the server leaves the origin' {
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } } -Server 'https://cloud.example.test/api')

        { & $SCRIPT_PATH -Path $file -Uri $TARGET_URI } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*must be on the origin of Uri*"
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'bad_value: fails early on a value that is not name=value' {
        $file = Set-TestSpec -Spec (New-TestSpec -Paths @{ '/status' = @{ get = (New-TestOperation -OperationId 'getStatus') } })

        { & $SCRIPT_PATH -Path $file -Uri $TARGET_URI -Value 'justavalue' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Value must be 'name=value'*"
    }

    It 'untrusted_certificate: stops at the first request and names SkipCertificateCheck' {
        $inner = [System.Security.Authentication.AuthenticationException]::new('The remote certificate is invalid because of errors in the certificate chain: UntrustedRoot')
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('The SSL connection could not be established, see inner exception.', $inner) }
        $paths = @{ '/a' = @{ get = (New-TestOperation -OperationId 'getA') }; '/b' = @{ get = (New-TestOperation -OperationId 'getB') } }

        { & $SCRIPT_PATH -Path (Set-TestSpec -Spec (New-TestSpec -Paths $paths)) -Uri 'https://router.test' } | Should -Throw -ExceptionType ([System.Security.Authentication.AuthenticationException]) -ExpectedMessage '*-SkipCertificateCheck*'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
}
