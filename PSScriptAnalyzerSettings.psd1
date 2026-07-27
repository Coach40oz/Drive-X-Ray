@{
    # DriveX-Ray is an interactive console application, not a module of
    # composable cmdlets. A few default rules do not apply; everything else
    # should stay clean.
    ExcludeRules = @(
        # The entire point of the tool is coloured, formatted terminal output.
        # Write-Output would send the report down the pipeline instead of
        # rendering it, and Write-Host is the supported way to do this since
        # PowerShell 5.0 (it writes to the information stream).
        'PSAvoidUsingWriteHost',

        # Console setup (window size, title, output encoding) is best-effort:
        # ISE, redirected output and remote sessions all throw here, and the
        # correct response is to carry on with the defaults rather than warn.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
