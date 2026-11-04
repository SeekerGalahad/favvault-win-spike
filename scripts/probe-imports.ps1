$ErrorActionPreference = 'Continue'

$importsDir = Join-Path $PSScriptRoot '..\imports'
$swiftc = (Get-Command swiftc -ErrorAction Stop).Source
$rows = @()

Get-ChildItem -Path $importsDir -Filter *.swift | Sort-Object Name | ForEach-Object {
    # Files are prefixed with m_ so that swiftc does not infer a module name
    # equal to the imported one ("file is part of module X; ignoring import").
    $module = $_.BaseName -replace '^m_', ''
    $stderrFile = Join-Path $env:TEMP ("probe-" + $module + ".err.txt")
    $stdoutFile = Join-Path $env:TEMP ("probe-" + $module + ".out.txt")

    # Exit code is taken from the process object; $LASTEXITCODE is unreliable
    # when the toolchain is launched through a shim.
    $process = Start-Process -FilePath $swiftc -ArgumentList @('-typecheck', $_.FullName) `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardError $stderrFile -RedirectStandardOutput $stdoutFile

    $diagnostics = (Get-Content -Path $stderrFile -ErrorAction SilentlyContinue) + `
                  (Get-Content -Path $stdoutFile -ErrorAction SilentlyContinue)
    $firstError = ($diagnostics | Select-String -Pattern 'error:' | Select-Object -First 1)
    $note = 'none'
    if ($null -ne $firstError) {
        $note = $firstError.Line.Trim()
        if ($note.Length -gt 160) { $note = $note.Substring(0, 160) }
    }

    $ok = ($process.ExitCode -eq 0)
    $rawDiag = ($diagnostics | Where-Object { $_ -and $_.Trim().Length -gt 0 })
    $diagHead = ($rawDiag | Select-Object -First 2) -join ' / '
    if ($diagHead.Length -gt 200) { $diagHead = $diagHead.Substring(0, 200) }
    Write-Output ("DIAG|{0}|lines={1}|exit={2}|{3}" -f $module, $rawDiag.Count, $process.ExitCode, $diagHead)
    $rows += [pscustomobject]@{ Module = $module; Exit = $process.ExitCode; Status = $(if ($ok) { 'OK' } else { 'FAIL' }); Note = $note }
    Write-Output ("IMPORT|{0}|{1}|exit={2}|{3}" -f $module, $(if ($ok) { 'OK' } else { 'FAIL' }), $process.ExitCode, $note)
}

$okCount = ($rows | Where-Object { $_.Status -eq 'OK' }).Count
Write-Output ("IMPORT-SUMMARY|total={0}|ok={1}|fail={2}" -f $rows.Count, $okCount, ($rows.Count - $okCount))

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @('## Module import matrix', '', '| Module | Exit | Result | First diagnostic |', '|---|---|---|---|')
    foreach ($row in $rows) {
        $lines += ("| {0} | {1} | {2} | {3} |" -f $row.Module, $row.Exit, $row.Status, ($row.Note -replace '\|', '\|'))
    }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n")
}

# Informational checkpoint only: the gate of this job is `swift build` + `swift test`.
exit 0
