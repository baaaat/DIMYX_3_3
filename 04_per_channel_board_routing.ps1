$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ReplaceRegexOnce([string]$Text,[string]$Pattern,[string]$New,[string]$Label) {
  $rx = New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  $m = $rx.Matches($Text)
  if ($m.Count -ne 1) { throw "STOP: $Label matches=$($m.Count)" }
  return $rx.Replace($Text,[System.Text.RegularExpressions.MatchEvaluator]{param($x) $New},1)
}
function ReplaceOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "STOP: $Label matches=$count" }
  return $Text.Replace($Old,$New)
}

if ((& git branch --show-current).Trim() -ne "fix/fx-layout-deferred") { throw "STOP: wrong branch" }
$pdePath = Join-Path $Root "DIMYX_3_3.pde"
$todoPath = Join-Path $Root "TODO.md"
$pde = [System.IO.File]::ReadAllText($pdePath)
$todo = [System.IO.File]::ReadAllText($todoPath)
$nl = if ($pde.Contains("`r`n")) { "`r`n" } else { "`n" }

if (-not $pde.Contains("class Esp32Target")) { throw "STOP: apply patch 03 first" }
if (-not $pde.Contains("boolean sendEsp32Command(String boardId, String command)")) { throw "STOP: ESP32 sender missing" }
if ($pde.Contains("String outputBoardId;")) { throw "STOP: per-channel board routing already installed" }

# Channel routing field/default.
$pde = ReplaceRegexOnce $pde `
  '  int pinMono, pinR, pinG, pinB;\r?\n  color baseColor;' `
  ('  int pinMono, pinR, pinG, pinB;' + $nl + '  String outputBoardId;' + $nl + '  color baseColor;') `
  "channel board field"

$pde = ReplaceRegexOnce $pde `
  '    pinB = 6;\r?\n    baseColor = color\(255\);' `
  ('    pinB = 6;' + $nl + '    outputBoardId = "USB";' + $nl + '    baseColor = color(255);') `
  "channel board default"

# Routing helpers.
$routingHelpers = @'
boolean channelUsesUsb(Channel ch) {
  return ch.outputBoardId == null || trim(ch.outputBoardId).length() == 0 || trim(ch.outputBoardId).equalsIgnoreCase("USB");
}

boolean sendChannelValue(Channel ch, int pin, int value) {
  String command = "P," + pin + "," + value + "\n";
  if (channelUsesUsb(ch)) {
    if (!serialConnected || myPort == null) return false;
    try {
      myPort.write(command);
      return true;
    } catch (Exception e) {
      handleConnectionLoss();
      return false;
    }
  }
  return sendEsp32Command(ch.outputBoardId, command);
}

void sendAllBlackouts() {
  if (serialConnected && myPort != null) {
    try { myPort.write("X\n"); } catch (Exception e) { handleConnectionLoss(); }
  }
  for (Esp32Target target : esp32Targets.values()) sendEsp32Command(target.id, "X\n");
}

'@.Replace("`r`n","`n").Replace("`n",$nl)
$pde = ReplaceOnce $pde 'boolean physicalOutputEnabled() {' ($routingHelpers + 'boolean physicalOutputEnabled() {') "routing helpers"

# UI field.
$pde = ReplaceOnce $pde `
  '    new CapsuleTextfield("pinMono_" + i).setText(str(allChannels.get(i).pinMono)).setAutoClear(false).setLabel("");' `
  ('    new CapsuleTextfield("board_" + i).setText(allChannels.get(i).outputBoardId).setAutoClear(false).setLabel("");' + $nl +
   '    new CapsuleTextfield("pinMono_" + i).setText(str(allChannels.get(i).pinMono)).setAutoClear(false).setLabel("");') `
  "board UI field"

$pde = ReplaceOnce $pde `
  '    place("pinMono_" + i, x, 210, w, 32, visible && outputsView);' `
  ('    place("board_" + i, x, 172, w, 28, visible && outputsView);' + $nl +
   '    place("pinMono_" + i, x, 210, w, 32, visible && outputsView);') `
  "board UI layout"

# Show what the field means in SORTIES.
$pde = ReplaceOnce $pde `
  '      fill(197, 212, 229);' `
  ('      fill(197, 212, 229);' + $nl + '      text("CARTE : USB ou ID ESP32", x, 168);') `
  "board output label"

# Sync field from model.
$pde = ReplaceOnce $pde `
  '    cp5.get(Textfield.class, "pinMono_" + i).setText(str(ch.pinMono));' `
  ('    cp5.get(Textfield.class, "board_" + i).setText(ch.outputBoardId);' + $nl +
   '    cp5.get(Textfield.class, "pinMono_" + i).setText(str(ch.pinMono));') `
  "board GUI sync"

# Focus/visibility.
$pde = ReplaceOnce $pde `
  '  cp5.get(Textfield.class, "pinMono_" + i).setVisible(visible && !rgb);' `
  ('  cp5.get(Textfield.class, "board_" + i).setVisible(visible);' + $nl +
   '  cp5.get(Textfield.class, "pinMono_" + i).setVisible(visible && !rgb);') `
  "board visibility"

$pde = ReplaceOnce $pde `
  '  String[] fields = {"pinMono_", "pinR_", "pinG_", "pinB_"};' `
  '  String[] fields = {"board_", "pinMono_", "pinR_", "pinG_", "pinB_"};' `
  "board focus list"

# Load/save config. Old configs default to USB.
$pde = ReplaceOnce $pde `
  '      ch.pinB = savedChannel.getInt("pb");' `
  ('      ch.pinB = savedChannel.getInt("pb");' + $nl +
   '      ch.outputBoardId = savedChannel.hasKey("board") ? trim(savedChannel.getString("board")).toUpperCase() : "USB";') `
  "board config load"

$pde = ReplaceOnce $pde `
  '    savedChannel.setInt("pb", ch.pinB);' `
  ('    savedChannel.setInt("pb", ch.pinB);' + $nl +
   '    savedChannel.setString("board", ch.outputBoardId);') `
  "board config save"

# Callbacks + setter.
$boardCallbacks = @'
public void board_0(String s) { setChannelBoard(0, s); }
public void board_1(String s) { setChannelBoard(1, s); }
public void board_2(String s) { setChannelBoard(2, s); }
public void board_3(String s) { setChannelBoard(3, s); }
public void board_4(String s) { setChannelBoard(4, s); }
public void board_5(String s) { setChannelBoard(5, s); }
public void board_6(String s) { setChannelBoard(6, s); }
public void board_7(String s) { setChannelBoard(7, s); }
public void board_8(String s) { setChannelBoard(8, s); }
public void board_9(String s) { setChannelBoard(9, s); }

void setChannelBoard(int i, String value) {
  String board = trim(value).toUpperCase();
  if (board.length() == 0) board = "USB";
  allChannels.get(i).outputBoardId = board;
  invalidateChannelOutputCache(allChannels.get(i));
  saveChannelConfig();
  if (!board.equals("USB") && !esp32Targets.containsKey(board)) {
    println("Attention: carte ESP32 inconnue pour tranche " + (i + 1) + " : " + board);
  }
}

'@.Replace("`r`n","`n").Replace("`n",$nl)
$pde = ReplaceOnce $pde 'public void name_0(String s) { setChannelName(0, s); }' ($boardCallbacks + 'public void name_0(String s) { setChannelName(0, s); }') "board callbacks"

# Allow ESP32 GPIO range while preserving USB's 0..15 range.
$pinOld = @'
    int p = int(s);
    if (p >= 0 && p <= 15) {
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pinNew = @'
    int p = int(s);
    int maxPin = channelUsesUsb(allChannels.get(i)) ? 15 : 48;
    if (p >= 0 && p <= maxPin) {
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceOnce $pde $pinOld $pinNew "board-aware pin range"

# Output loop can run when either USB or at least one ESP32 target exists.
$pde = ReplaceRegexOnce $pde `
  '  drawConsoleInterface\(\);\r?\n  \r?\n  if \(serialConnected && myPort != null\) \{' `
  ('  drawConsoleInterface();' + $nl + '  ' + $nl + '  if ((serialConnected && myPort != null) || !esp32Targets.isEmpty()) {') `
  "output transport availability"

$pde = ReplaceOnce $pde `
  '    if (now - lastHeartbeatTime > heartbeatInterval) {' `
  '    if (serialConnected && myPort != null && now - lastHeartbeatTime > heartbeatInterval) {' `
  "USB heartbeat guard"

$pde = ReplaceOnce $pde `
  '    if (serialConnected && myPort != null && physicalOutputEnabled() && now - lastSendTime > sendInterval) {' `
  '    if (physicalOutputEnabled() && now - lastSendTime > sendInterval) {' `
  "mixed transport output gate"

$pde = ReplaceRegexOnce $pde `
  '          if \(ch\.valR != vr\) \{\r?\n            myPort\.write\("P," \+ ch\.pinR \+ "," \+ vr \+ "\\n"\);\r?\n            ch\.valR = vr;\r?\n          \}' `
  ('          if (ch.valR != vr && sendChannelValue(ch, ch.pinR, vr)) ch.valR = vr;') `
  "route red"

$pde = ReplaceRegexOnce $pde `
  '          if \(ch\.valG != vg\) \{\r?\n            myPort\.write\("P," \+ ch\.pinG \+ "," \+ vg \+ "\\n"\);\r?\n            ch\.valG = vg;\r?\n          \}' `
  ('          if (ch.valG != vg && sendChannelValue(ch, ch.pinG, vg)) ch.valG = vg;') `
  "route green"

$pde = ReplaceRegexOnce $pde `
  '          if \(ch\.valB != vb\) \{\r?\n            myPort\.write\("P," \+ ch\.pinB \+ "," \+ vb \+ "\\n"\);\r?\n            ch\.valB = vb;\r?\n          \}' `
  ('          if (ch.valB != vb && sendChannelValue(ch, ch.pinB, vb)) ch.valB = vb;') `
  "route blue"

$pde = ReplaceRegexOnce $pde `
  '          if \(ch\.value != fv\) \{\r?\n            myPort\.write\("P," \+ ch\.pinMono \+ "," \+ fv \+ "\\n"\);\r?\n            ch\.value = fv;\r?\n          \}' `
  ('          if (ch.value != fv && sendChannelValue(ch, ch.pinMono, fv)) ch.value = fv;') `
  "route mono"

# Blackout both transports.
$pde = ReplaceRegexOnce $pde `
  '  if \(sendCommand && serialConnected && myPort != null\) \{\r?\n    myPort\.write\("X\\n"\);\r?\n  \}' `
  ('  if (sendCommand) sendAllBlackouts();') `
  "mixed blackout"

if (-not $pde.Contains('new CapsuleTextfield("board_" + i)')) { throw "STOP: board UI validation failed" }
if (-not $pde.Contains("sendChannelValue(ch, ch.pinMono, fv)")) { throw "STOP: routing validation failed" }

$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] En plus des pins, il faut pouvoir adresser une carte . une tranche\s*$',
  '- [ ] Valider l''affectation CARTE par tranche: USB ou ID ESP32, avec routage des pins vers la bonne carte'
)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $Root ("backups\before-board-routing-" + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item $pdePath (Join-Path $backup "DIMYX_3_3.pde")
Copy-Item $todoPath (Join-Path $backup "TODO.md")

[System.IO.File]::WriteAllText($pdePath,$pde,$Utf8NoBom)
[System.IO.File]::WriteAllText($todoPath,$todo,$Utf8NoBom)

Write-Host "Applied: per-channel USB/ESP32 board routing." -ForegroundColor Green
Write-Host "In SORTIES, set CARTE to USB or an ID from esp32Boards.json."
Write-Host "Run: .\tests\run-interface.ps1 -Render"
