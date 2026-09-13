$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Pde = Join-Path $Root "DIMYX_3_3.pde"
if (-not (Test-Path $Pde)) {
  throw "DIMYX_3_3.pde not found"
}

# Get the exact added-line numbers from Git.
$diff = & git --no-pager diff --unified=0 -- DIMYX_3_3.pde
if ($LASTEXITCODE -ne 0) {
  throw "git diff failed"
}

$added = New-Object 'System.Collections.Generic.HashSet[int]'
$currentNewLine = 0

foreach ($line in $diff) {
  if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@') {
    $currentNewLine = [int]$matches[1]
    continue
  }

  if ($line.StartsWith('+++')) {
    continue
  }

  if ($line.StartsWith('+')) {
    [void]$added.Add($currentNewLine)
    $currentNewLine++
    continue
  }

  if ($line.StartsWith('-')) {
    continue
  }

  if ($currentNewLine -gt 0) {
    $currentNewLine++
  }
}

if ($added.Count -eq 0) {
  Write-Host "No added PDE lines found in git diff."
} else {
  Write-Host ("Added PDE lines detected: " + $added.Count)
}

# Read file as raw bytes and preserve every existing line ending except on added lines.
$bytes = [System.IO.File]::ReadAllBytes($Pde)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

# Split while preserving line endings.
$parts = [regex]::Matches($text, '.*?(?:\r\n|\n|\r|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)

$sb = New-Object System.Text.StringBuilder
$lineNo = 1
$changed = 0

foreach ($m in $parts) {
  $segment = $m.Value
  if ($segment.Length -eq 0) { continue }

  $content = $segment
  $ending = ""

  if ($segment.EndsWith("`r`n")) {
    $content = $segment.Substring(0, $segment.Length - 2)
    $ending = "`r`n"
  } elseif ($segment.EndsWith("`n")) {
    $content = $segment.Substring(0, $segment.Length - 1)
    $ending = "`n"
  } elseif ($segment.EndsWith("`r")) {
    $content = $segment.Substring(0, $segment.Length - 1)
    $ending = "`r"
  }

  if ($added.Contains($lineNo)) {
    $trimmed = $content.TrimEnd(" ", "`t", "`r")
    if ($trimmed -ne $content -or $ending -ne "`n") {
      $changed++
    }
    $content = $trimmed
    if ($ending -ne "") {
      $ending = "`n"
    }
  }

  [void]$sb.Append($content)
  [void]$sb.Append($ending)
  $lineNo++
}

[System.IO.File]::WriteAllText(
  $Pde,
  $sb.ToString(),
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ("Adjusted added PDE lines: " + $changed) -ForegroundColor Green
Write-Host ""

$check = & git --no-pager diff --check 2>&1
$code = $LASTEXITCODE

if ($check) {
  $check | ForEach-Object { Write-Host $_ }
}

if ($code -ne 0) {
  Write-Host ""
  Write-Host "git diff --check still reports the lines above." -ForegroundColor Yellow
  exit $code
}

Write-Host "git diff --check: OK" -ForegroundColor Green
Write-Host "Next: .\tests\run-interface.ps1 -Render"
