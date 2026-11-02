#
# Module manifest for module 'ReferenceHard'
#
# Written by unwire:code from openapi.json, draft, AI-derived.
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule        = 'ReferenceHard.psm1'

    # Version number of this module.
    ModuleVersion     = '0.1.0'

    # ID used to uniquely identify this module
    GUID              = '7b0f3c52-9d4e-4a61-8f2b-5c1e6a0d9b34'

    # Author of this module
    Author            = 'unwire:code'

    # Description of the functionality provided by this module
    Description       = 'PowerShell client of ReferenceHard, derived from its web UI by Unwire. Draft, AI-derived.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.2'

    # Functions to export from this module, no wildcards.
    FunctionsToExport = 'Invoke-ReferenceHardRest', 'Connect-ReferenceHard', 'Disconnect-ReferenceHard',
                        'Lock-ReferenceHardAccount', 'Get-ReferenceHardAccount', 'Start-ReferenceHardJob',
                        'Suspend-ReferenceHardDevice', 'Set-ReferenceHardSetting'

    # Cmdlets, variables and aliases to export from this module.
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags = @('unwire', 'draft')
        }
    }
}
