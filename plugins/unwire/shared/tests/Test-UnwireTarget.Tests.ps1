# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./plugins/unwire

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# ===========================   CLASSIFY TARGET   ===========================
# ===========================================================================
#
#   private_ranges      Home network addresses need no confirmation.
#   public_addresses    Public addresses require a confirmation.
#   localhost_name      localhost resolves to loopback and counts as private.
#   unresolvable        A name that does not resolve requires a confirmation.
#   invalid_uri         Fails early on a URI that is not http(s).
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../Test-UnwireTarget.ps1'
}

Describe 'Test-UnwireTarget' {
    It 'private_ranges: <Uri> is a home system' -ForEach @(
        @{ Uri = 'http://192.168.178.1' }
        @{ Uri = 'https://10.0.0.5:8443/ui/' }
        @{ Uri = 'http://172.20.1.1' }
        @{ Uri = 'http://127.0.0.1:3003/' }
        @{ Uri = 'http://169.254.10.1' }
        @{ Uri = 'http://100.101.102.103' }
        @{ Uri = 'http://[::1]:8080' }
        @{ Uri = 'http://[fd00::1]' }
        @{ Uri = 'http://[fe80::1]' }
    ) {
        $result = & $SCRIPT_PATH -Uri $Uri

        $result.Classification       | Should -Be 'Private'
        $result.IsHomeSystem         | Should -BeTrue
        $result.RequiresConfirmation | Should -BeFalse
    }

    It 'public_addresses: <Uri> requires a confirmation' -ForEach @(
        @{ Uri = 'http://8.8.8.8' }
        @{ Uri = 'https://172.32.0.1' }
        @{ Uri = 'http://100.128.0.1' }
        @{ Uri = 'http://[2001:4860:4860::8888]' }
    ) {
        $result = & $SCRIPT_PATH -Uri $Uri

        $result.Classification       | Should -Be 'Public'
        $result.RequiresConfirmation | Should -BeTrue
        $result.Reason               | Should -BeLike '*public address*'
    }

    It 'localhost_name: localhost resolves to loopback and counts as private' {
        $result = & $SCRIPT_PATH -Uri 'http://localhost:3000'

        $result.Classification | Should -Be 'Private'
        $result.Addresses      | Should -Not -BeNullOrEmpty
    }

    It 'unresolvable: a name that does not resolve requires a confirmation' {
        $result = & $SCRIPT_PATH -Uri 'https://unwire-does-not-exist.invalid/'

        $result.Classification       | Should -Be 'Unknown'
        $result.RequiresConfirmation | Should -BeTrue
    }

    It 'invalid_uri: fails early on a URI that is not http(s)' {
        { & $SCRIPT_PATH -Uri 'ftp://192.168.178.1' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*absolute http or https URI*'
    }
}
