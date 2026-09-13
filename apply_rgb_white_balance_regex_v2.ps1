$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ReadText([string]$Path) {
  return [System.IO.File]::ReadAllText((Join-Path $Root $Path))
}

function WriteText([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText((Join-Path $Root $Path), $Text, $Utf8NoBom)
}

function ReplaceRegexOnce([string]$Text, [string]$Pattern, [string]$New, [string]$Label) {
  $rx = New-Object System.Text.RegularExpressions.Regex(
    $Pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  $matches = $rx.Matches($Text)
  if ($matches.Count -ne 1) {
    throw "STOP: $Label matches=$($matches.Count)"
  }
  return $rx.Replace(
    $Text,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $New },
    1
  )
}

function ReplaceOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
  if ($count -ne 1) {
    throw "STOP: $Label matches=$count"
  }
  return $Text.Replace($Old, $New)
}

$branch = (& git branch --show-current).Trim()
if ($branch -ne "fix/fx-layout-deferred") {
  throw "STOP: wrong branch: $branch"
}

$pdePath = "DIMYX_3_3.pde"
$pde = ReadText $pdePath
$nl = "`n"
if ($pde.Contains("`r`n")) { $nl = "`r`n" }

# The exact-white wheel patch is local and not yet on GitHub, so use exact
# feature markers instead of a remote SHA that would intentionally fail.
if (-not $pde.Contains("float whiteRadius = 5.0;")) {
  throw "STOP: exact-white wheel patch is not present"
}
if (-not $pde.Contains("float wheelDistance = dist(mouseX, mouseY, cx, cy);")) {
  throw "STOP: exact-white click patch is not present"
}
if ($pde.Contains("whiteBalanceR")) {
  throw "STOP: white-balance calibration already appears to be installed"
}

Write-Host "Preflight OK: exact-white patch found, calibration not installed." -ForegroundColor Green

# Global delayed-save state.
$pde = ReplaceOnce $pde `
  'boolean blindActive = false;' `
  ('boolean blindActive = false;' + $nl +
   'boolean whiteBalanceDirty = false;' + $nl +
   'long whiteBalanceSaveAt = 0;') `
  "white balance save state"

# Per-channel calibration values.
$pde = ReplaceRegexOnce $pde `
  '  float fxFreq;\r?\n  StepSequencer sequencer;' `
  ('  float fxFreq;' + $nl +
   '  float whiteBalanceR, whiteBalanceG, whiteBalanceB;' + $nl +
   '  StepSequencer sequencer;') `
  "channel calibration fields"

$pde = ReplaceRegexOnce $pde `
  '    fxFreq = 1\.0;\r?\n    sequencer = new StepSequencer\(\);' `
  ('    fxFreq = 1.0;' + $nl +
   '    whiteBalanceR = 1.0;' + $nl +
   '    whiteBalanceG = 1.0;' + $nl +
   '    whiteBalanceB = 1.0;' + $nl +
   '    sequencer = new StepSequencer();') `
  "channel calibration defaults"

# Save calibration after a short idle period instead of on every slider event.
$saveHelper = @'
void markWhiteBalanceDirty() {
  whiteBalanceDirty = true;
  whiteBalanceSaveAt = millis() + 400;
}

'@.Replace("`r`n","`n").Replace("`n",$nl)

$pde = ReplaceOnce $pde `
  'boolean physicalOutputEnabled() {' `
  ($saveHelper + 'boolean physicalOutputEnabled() {') `
  "white balance save helper"

$drawNowPattern = 'void draw\(\) \{\r?\n  if \(width != layoutWidth \|\| height != layoutHeight\) \{\r?\n    effectMenuChannel = -1;\r?\n    layoutInterface\(\);\r?\n  \}\r?\n  long now = millis\(\);'

$drawNowNew = @'
void draw() {
  if (width != layoutWidth || height != layoutHeight) {
    effectMenuChannel = -1;
    layoutInterface();
  }
  long now = millis();
  if (whiteBalanceDirty && now >= whiteBalanceSaveAt) {
    whiteBalanceDirty = false;
    saveChannelConfig();
  }
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceRegexOnce $pde $drawNowPattern $drawNowNew "delayed calibration save in draw"

# Apply calibration only to the common white component. Pure saturated colors
# remain at full value.
$oldRgbCalc = @'
          color col = (ch.sequencer.active) ? ch.sequencer.getCurrentColor() : ch.baseColor;
          int vr = int((red(col) / 255.0) * 4095 * fin);
          int vg = int((green(col) / 255.0) * 4095 * fin);
          int vb = int((blue(col) / 255.0) * 4095 * fin);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$newRgbCalc = @'
          color col = (ch.sequencer.active) ? ch.sequencer.getCurrentColor() : ch.baseColor;
          float nr = red(col) / 255.0;
          float ng = green(col) / 255.0;
          float nb = blue(col) / 255.0;
          float whitePart = min(nr, min(ng, nb));
          nr = constrain((nr - whitePart) + whitePart * ch.whiteBalanceR, 0, 1);
          ng = constrain((ng - whitePart) + whitePart * ch.whiteBalanceG, 0, 1);
          nb = constrain((nb - whitePart) + whitePart * ch.whiteBalanceB, 0, 1);
          int vr = int(nr * 4095 * fin);
          int vg = int(ng * 4095 * fin);
          int vb = int(nb * 4095 * fin);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $oldRgbCalc $newRgbCalc "RGB calibrated output"

# Create three calibration sliders per channel.
$sliderAnchor = '    cp5.addToggle("seq_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("SEQ", color(255, 200, 0)));'
$sliderNew = @'
    cp5.addToggle("seq_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("SEQ", color(255, 200, 0)));
    capsuleSlider("whiteR_" + i, "BLANC R %", 0, 100, 100, color(145, 80, 80));
    capsuleSlider("whiteG_" + i, "BLANC V %", 0, 100, 100, color(80, 145, 95));
    capsuleSlider("whiteB_" + i, "BLANC B %", 0, 100, 100, color(80, 105, 155));
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $sliderAnchor $sliderNew "calibration slider creation"

# Place them only in SORTIES for RGB channels.
$layoutAnchor = '    place("pinB_" + i, x, 346, w, 32, visible && outputsView);'
$layoutNew = @'
    place("pinB_" + i, x, 346, w, 32, visible && outputsView);
    boolean showWhiteBalance = visible && outputsView && allChannels.get(i).isRGB;
    place("whiteR_" + i, x, 402, w, 28, showWhiteBalance);
    place("whiteG_" + i, x, 434, w, 28, showWhiteBalance);
    place("whiteB_" + i, x, 466, w, 28, showWhiteBalance);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $layoutAnchor $layoutNew "calibration slider layout"

# Keep slider visibility correct immediately after RGB/mono switch.
$syncAnchor = '  cp5.get(Textfield.class, "pinB_" + i).setVisible(visible && rgb);'
$syncNew = @'
  cp5.get(Textfield.class, "pinB_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteR_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteG_" + i).setVisible(visible && rgb);
  cp5.get(Slider.class, "whiteB_" + i).setVisible(visible && rgb);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $syncAnchor $syncNew "calibration visibility"

# Sync UI after config load / scene updates.
$guiAnchor = '    cp5.get(Slider.class, "bpm_" + i).setValue(ch.sequencer.bpm);'
$guiNew = @'
    cp5.get(Slider.class, "bpm_" + i).setValue(ch.sequencer.bpm);
    cp5.get(Slider.class, "whiteR_" + i).setValue(ch.whiteBalanceR * 100.0);
    cp5.get(Slider.class, "whiteG_" + i).setValue(ch.whiteBalanceG * 100.0);
    cp5.get(Slider.class, "whiteB_" + i).setValue(ch.whiteBalanceB * 100.0);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $guiAnchor $guiNew "calibration GUI sync"

# Load optional calibration values; old configs remain compatible.
$loadAnchor = '      ch.pinB = savedChannel.getInt("pb");'
$loadNew = @'
      ch.pinB = savedChannel.getInt("pb");
      ch.whiteBalanceR = savedChannel.hasKey("wr") ? constrain(savedChannel.getFloat("wr"), 0, 1) : 1.0;
      ch.whiteBalanceG = savedChannel.hasKey("wg") ? constrain(savedChannel.getFloat("wg"), 0, 1) : 1.0;
      ch.whiteBalanceB = savedChannel.hasKey("wb") ? constrain(savedChannel.getFloat("wb"), 0, 1) : 1.0;
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $loadAnchor $loadNew "calibration config load"

# Save calibration values.
$saveAnchor = '    savedChannel.setInt("pb", ch.pinB);'
$saveNew = @'
    savedChannel.setInt("pb", ch.pinB);
    savedChannel.setFloat("wr", ch.whiteBalanceR);
    savedChannel.setFloat("wg", ch.whiteBalanceG);
    savedChannel.setFloat("wb", ch.whiteBalanceB);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $saveAnchor $saveNew "calibration config save"

# Handle slider events generically.
$eventAnchor = @'
  if (e.isController() && e.getName().startsWith("usbPort_")) {
'@.Replace("`r`n","`n").Replace("`n",$nl)

$eventNew = @'
  if (e.isController() && e.getName().startsWith("whiteR_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceR = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("whiteG_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceG = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("whiteB_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.whiteBalanceB = constrain(e.getValue() / 100.0, 0, 1);
    invalidateChannelOutputCache(ch);
    markWhiteBalanceDirty();
    return;
  }
  if (e.isController() && e.getName().startsWith("usbPort_")) {
'@.Replace("`r`n","`n").Replace("`n",$nl)

$pde = ReplaceOnce $pde $eventAnchor $eventNew "calibration events"

# Label the calibration area and move the Enter hint below it.
$oldOutputText = @'
      text("Valider avec Entree", x, 410);
      continue;
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$newOutputText = @'
      if (allChannels.get(i).isRGB) text("BALANCE BLANC", x, 396);
      text("Valider avec Entree", x, height - 22);
      continue;
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")

$pde = ReplaceOnce $pde $oldOutputText $newOutputText "calibration output label"

# Validate before writing.
foreach ($marker in @(
  "whiteBalanceR, whiteBalanceG, whiteBalanceB",
  'capsuleSlider("whiteR_" + i',
  'float whitePart = min(nr, min(ng, nb));',
  'savedChannel.setFloat("wr", ch.whiteBalanceR);',
  'e.getName().startsWith("whiteR_")'
)) {
  if (-not $pde.Contains($marker)) {
    throw "STOP: validation marker missing: $marker"
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir ("DIMYX_3_3.before-white-balance-" + $stamp + ".pde")
Copy-Item $pdePath $backup

WriteText $pdePath $pde

Write-Host ""
Write-Host "Applied." -ForegroundColor Green
Write-Host "SORTIES now has BLANC R / V / B calibration for RGB channels."
Write-Host "Calibration affects only the common white component; pure colors stay full."
Write-Host "Values are saved to channelConfig.json as wr / wg / wb."
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Start at 100 / 100 / 100, select white in the wheel, then reduce the dominant colors until the strip looks neutral."
