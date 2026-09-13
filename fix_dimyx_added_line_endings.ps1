$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Pde = Join-Path $Root "DIMYX_3_3.pde"

if (-not (Test-Path $Pde)) {
  throw "DIMYX_3_3.pde not found"
}

# Work on bytes so the rest of the mixed-EOL PDE stays byte-for-byte unchanged.
$bytes = [System.IO.File]::ReadAllBytes($Pde)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

$lines = @(
  'boolean blindActive = false;',
  '  cp5.get(Button.class, "outputsView").setLabel(outputsView ? "< CONSOLE" : "SORTIES");',
  '  place("blindMode", 356, 16, 94, 32, true);',
  '    place("rgb_" + i, x, 136, w, 28, visible && outputsView);',
  'public void outputsView() { effectMenuChannel = -1; outputsView = !outputsView; layoutInterface(); }',
  'public void blindMode(boolean v) {',
  '  blindActive = v;',
  '  invalidateOutputCache();',
  '  println("BLIND " + (v ? "ON" : "OFF"));',
  '}',
  '  if (!(narrowLayout && scenesView)) text((firstChannel() + 1) + "-" + min(nbChannels, firstChannel() + channelsPerPage) + "/" + nbChannels, 458, 37);',
  'float channelMaster(Channel ch) {',
  '  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;',
  'boolean physicalOutputEnabled() {',
  '  return !blindActive;',
  '    if (serialConnected && myPort != null && physicalOutputEnabled() && now - lastSendTime > sendInterval) {',
  '        float master = channelMaster(ch);',
  '    cp5.addToggle("rgb_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("RGB", color(0, 200, 255)));',
  '  capsuleButton("outputsView", "SORTIES", color(58, 77, 102));',
  '  cp5.addToggle("blindMode").setValue(false).setLabel("").setView(new ChipView("BLIND", color(191, 139, 48)));'
)

$changed = 0
foreach ($line in $lines) {
  $old = $line + "`r`n"
  $new = $line + "`n"
  if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
    $changed++
  }
}

# Also normalize blank CRLF lines only inside the two newly-added helper blocks.
$text = $text.Replace(
  "float channelMaster(Channel ch) {`n  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;`n}`r`n`r`nboolean physicalOutputEnabled() {",
  "float channelMaster(Channel ch) {`n  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;`n}`n`nboolean physicalOutputEnabled() {"
)

[System.IO.File]::WriteAllText($Pde, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Targeted EOL cleanup done. Lines adjusted: $changed" -ForegroundColor Green

Set-Location $Root
& git --no-pager diff --check
if ($LASTEXITCODE -ne 0) {
  throw "git diff --check still reports an issue"
}

Write-Host "git diff --check: OK" -ForegroundColor Green
Write-Host "Next: .\tests\run-interface.ps1 -Render"
