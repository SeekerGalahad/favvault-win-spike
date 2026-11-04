$ErrorActionPreference = 'Continue'

$importsDir = Join-Path $PSScriptRoot '..\imports'
$rows = @()

Get-ChildItem -Path $importsDir -Filter *.swift | Sort-Object Name | ForEach-Object {
    $module = $_.BaseName
    $output = & swiftc -typecheck $_.FullName 2>&1
    $exit = $LASTEXITCODE
    $ok = ($exit -eq 0)
    $firstError = ($output | Select-String -Pattern 'error:' | Select-Object -First 1)
    $note = 'none'
    if ($null -ne $firstError) {
        $note = $firstError.Line.Trim()
        if ($note.Length -gt 160) { $note = $note.Substring(0, 160) }
    }
    $rows += [pscustomobject]@{ Module = $module; Status = $(if ($ok) { 'OK' } else { 'FAIL' }); Note = $note }
    Write-Output ("IMPORT|{0}|{1}|{2}" -f $module, $(if ($ok) { 'OK' } else { 'FAIL' }), $note)
}

$okCount = ($rows | Where-Object { $_.Status -eq 'OK' }).Count
Write-Output ("IMPORT-SUMMARY|total={0}|ok={1}|fail={2}" -f $rows.Count, $okCount, ($rows.Count - $okCount))

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @('## Module import matrix', '', '| Module | Result | First diagnostic |', '|---|---|---|')
    foreach ($row in $rows) {
        $lines += ("| {0} | {1} | {2} |" -f $row.Module, $row.Status, ($row.Note -replace '\|', '\|'))
    }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n")
}

# Informational only: the pass/fail gate of this job is `swift build` + `swift test`.
exit 0
