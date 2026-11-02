function Start-ReferenceHardJob {
    <#
    .SYNOPSIS
    Starts a maintenance job.

    .DESCRIPTION
    A GET that starts something: treated as a change of the device, asks before it sends.
    The job names are guessed from the code, the device may know others.

    .NOTES
    Operation:  GET /api/v1/jobs/{kind}/start (startJob)
    Confidence: low, not verified
    Source:     assets/js/main.js:96
    Open:       Path built at runtime: '/api/v1/jobs/' + kind + '/start', the values of kind are guessed.
    Open:       A GET that starts something: marked write, so the live GET never sends it.

    .EXAMPLE

    Start a scrub:

    PS> Start-ReferenceHardJob -Kind scrub
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param (
        <#
        [Required]
        The kind of the job. 'scrub' and 'smart' stand next to the call, guessed, not a fixed list.
        #>
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ArgumentCompleter({
            # $args: command name, parameter name, the word to complete
            $wordToComplete = $args[2]
            @('scrub', 'smart') | Where-Object { $_ -LIKE "$wordToComplete*" }
        })]
        [System.String]
        $Kind
    )

    Write-Warning '[Start-ReferenceHardJob] Confidence low, not verified: the path is built at runtime and the job names are guessed.'

    $Request = @{
        Method         = 'GET'
        Path           = '/api/v1/jobs/{kind}/start'
        PathParameters = @{ kind = $Kind }
        Security       = @('tokenAuth')
    }

    if ($PSCmdlet.ShouldProcess("job '$Kind'", 'GET /api/v1/jobs/{kind}/start')) {
        return Invoke-ReferenceHardRest @Request -Confirm:$false
    }
}
