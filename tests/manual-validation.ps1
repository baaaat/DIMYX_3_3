$ErrorActionPreference = "Stop"

$Checks = @(
  "Interface native: all visible controls work on the target screen",
  "Scenes: create, record, recall, delete and reorder",
  "Persistence: restart and confirm scenes, names and routing",
  "Mono output: fader and sequencer drive the expected physical output",
  "RGB output: colors, exact white and white balance are correct",
  "FX: MAN STR FEU PUL work with and without SEQ",
  "BLIND: programming changes do not reach physical outputs",
  "BLACKOUT: USB and every connected output go dark immediately",
  "USB: detection, reconnect and scene recovery work",
  "Responsive UI: 800x540, 1024x600 and 1366x768 remain usable"
)

$results = @()
$failed = 0

Write-Host "DIMYX manual validation" -ForegroundColor Cyan
Write-Host "Answer O for OK, N for failed." -ForegroundColor DarkGray
Write-Host ""

for ($i = 0; $i -lt $Checks.Count; $i++) {
  do {
    $answer = (Read-Host ("[{0}/{1}] {2} [O/N]" -f ($i+1), $Checks.Count, $Checks[$i])).Trim().ToUpper()
  } while ($answer -ne "O" -and $answer -ne "N")

  $ok = $answer -eq "O"
  if (-not $ok) { $failed++ }
  $results += [PSCustomObject]@{
    Check = $Checks[$i]
    Result = $(if ($ok) { "OK" } else { "ECHEC" })
  }
}

$reportDir = Join-Path $PSScriptRoot "..\build\manual-validation"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = Join-Path $reportDir ("validation-" + $stamp + ".txt")

$lines = @(
  "DIMYX manual validation",
  "Date: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
  ""
)
foreach ($r in $results) {
  $lines += ("[{0}] {1}" -f $r.Result, $r.Check)
}
$lines += ""
$lines += ("Failures: " + $failed)

[System.IO.File]::WriteAllLines($report, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host ("Report: " + $report)
if ($failed -gt 0) {
  Write-Host ("Manual validation failed: " + $failed + " item(s).") -ForegroundColor Yellow
  exit 1
}

Write-Host "Manual validation complete: all checks OK." -ForegroundColor Green
Write-Host "You can now mark the global manual-validation TODO item as complete."