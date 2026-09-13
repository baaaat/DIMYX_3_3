$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function GitHash([string]$Path) {
  $h = (& git hash-object -- $Path 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($h)) {
    throw "Cannot hash: $Path"
  }
  return $h.Trim()
}

function RequireHash([string]$Path, [string]$Expected) {
  if (-not (Test-Path $Path)) { throw "Missing file: $Path" }
  $actual = GitHash $Path
  if ($actual -ne $Expected) {
    throw "STOP: $Path changed. Got $actual ; expected $Expected"
  }
}

function ReadText([string]$Path) {
  return [System.IO.File]::ReadAllText((Join-Path $Root $Path))
}

function WriteText([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText((Join-Path $Root $Path), $Text, $Utf8NoBom)
}

function ReplaceLiteralOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "STOP: $Label matches=$count" }
  return $Text.Replace($Old, $New)
}

function ReplaceRegexOnce([string]$Text, [string]$Pattern, [string]$New, [string]$Label) {
  $rx = New-Object System.Text.RegularExpressions.Regex(
    $Pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  $matches = $rx.Matches($Text)
  if ($matches.Count -ne 1) { throw "STOP: $Label matches=$($matches.Count)" }
  return $rx.Replace(
    $Text,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $New },
    1
  )
}

$branch = (& git branch --show-current).Trim()
if ($branch -ne "fix/fx-layout-deferred") {
  throw "STOP: wrong branch: $branch"
}

RequireHash "DIMYX_3_3.pde" "d7bb974ed49062b69c26a31189c6d1a405d07199"
RequireHash "tests\InterfaceCheck.java" "a878a046d0b78057fb7d47554df1a50bfe789d9b"
RequireHash "TODO.md" "f507bda0097c6b9ec121338c8acf2cf9711c109b"

Write-Host "Preflight OK: exact current branch files." -ForegroundColor Green

$pde = ReadText "DIMYX_3_3.pde"

# 1) Mono output helpers: test the final computed value, not only channelMaster().
$helperPattern = 'float channelMaster\(Channel ch\) \{\r?\n  return \(ch\.sequencer\.active \? ch\.sequencer\.getCurrentIntensity\(\) : ch\.manualVal\) / 4095\.0;\r?\n\}\r?\n'
$helperNew = @'
float channelMaster(Channel ch) {
  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;
}

int computeMonoOutput(Channel ch, float eff) {
  return constrain(round(4095.0 * eff * channelMaster(ch)), 0, 4095);
}

void invalidateChannelOutputCache(Channel ch) {
  ch.valR = -1;
  ch.valG = -1;
  ch.valB = -1;
  ch.value = -1;
}

'@.Replace("`r`n","`n")
$pde = ReplaceRegexOnce $pde $helperPattern $helperNew "mono helpers"

$pde = ReplaceLiteralOnce $pde `
  '          int fv = int(4095 * fin);' `
  '          int fv = computeMonoOutput(ch, eff);' `
  "mono physical output"

# 2) New steps use the current fader level. This is the key mono usability fix.
$pde = ReplaceLiteralOnce $pde `
  '        ch.sequencer.steps.add(new Step(2048, red(col), green(col), blue(col)));' `
  '        ch.sequencer.steps.add(new Step(constrain(ch.manualVal, 0, 4095), red(col), green(col), blue(col)));' `
  "new step intensity"

# 3) Mode changes must force the first physical value to be emitted.
$toggleRgbPattern = 'void toggleRGB\(int i, boolean v\) \{\r?\n  allChannels\.get\(i\)\.isRGB = v;\r?\n  syncPinControls\(i\);\r?\n\}'
$toggleRgbNew = @'
void toggleRGB(int i, boolean v) {
  Channel ch = allChannels.get(i);
  if (ch.isRGB != v) {
    ch.isRGB = v;
    invalidateChannelOutputCache(ch);
  }
  syncPinControls(i);
}
'@.Replace("`r`n","`n").TrimEnd("`n")
$pde = ReplaceRegexOnce $pde $toggleRgbPattern $toggleRgbNew "toggle RGB cache"

$pde = ReplaceLiteralOnce $pde `
  '  ch.sequencer.active = v;' `
  ('  ch.sequencer.active = v;' + "`n" + '  invalidateChannelOutputCache(ch);') `
  "toggle SEQ cache"

# 4) A real ControlP5 dropdown, with no dynamic layout mutation while clicking.
$effectPlace = @'
void placeEffectList(String name, int x, int y, int w, boolean visible) {
  ScrollableList list = cp5.get(ScrollableList.class, name);
  if (list == null) return;
  list.setPosition(x, y);
  list.setSize(w, 140);
  list.setBarHeight(28);
  list.setItemHeight(28);
  list.setVisible(visible);
  if (!visible) list.close();
}

'@.Replace("`r`n","`n")
$pde = ReplaceLiteralOnce $pde `
  'void layoutInterface() {' `
  ($effectPlace + 'void layoutInterface() {') `
  "effect list layout helper"

$pde = ReplaceLiteralOnce $pde `
  '    place("effect_" + i, x, 120, w, 28, live);' `
  '    placeEffectList("effect_" + i, x, 120, w, live);' `
  "effect list placement"

$pde = ReplaceLiteralOnce $pde `
  '    capsuleButton("effect_" + i, "FX  MAN  >", color(60, 83, 109));' `
  '' `
  "remove cyclic FX button"

$fxCreate = @'
  for (int i = 0; i < nbChannels; i++) {
    ScrollableList fx = cp5.addScrollableList("effect_" + i);
    fx.setBarHeight(28);
    fx.setItemHeight(28);
    fx.setItems(new String[]{"MAN", "STR", "FEU", "PUL"});
    fx.setColorBackground(color(60, 83, 109));
    fx.setColorForeground(color(74, 99, 132));
    fx.setColorActive(color(92, 124, 165));
    fx.getCaptionLabel().setText("FX  MAN  v");
    fx.close();
    fx.bringToFront();
  }
'@.Replace("`r`n","`n").TrimEnd("`n")

$pde = ReplaceLiteralOnce $pde `
  '  capsuleButton("outputsView", "SORTIES", color(58, 77, 102));' `
  ($fxCreate + "`n" + '  capsuleButton("outputsView", "SORTIES", color(58, 77, 102));') `
  "create FX dropdowns"

$updateFxPattern = 'void updateEffectButton\(int i\) \{\r?\n  String\[\] labels = \{"MAN", "STR", "FEU", "PUL"\};\r?\n  int mode = constrain\(allChannels\.get\(i\)\.fxMode, 0, 3\);\r?\n  cp5\.get\(Button\.class, "effect_" \+ i\)\.setLabel\("FX  " \+ labels\[mode\] \+ "  >"\);\r?\n\}'
$updateFxNew = @'
void updateEffectButton(int i) {
  String[] labels = {"MAN", "STR", "FEU", "PUL"};
  int mode = constrain(allChannels.get(i).fxMode, 0, 3);
  ScrollableList fx = cp5.get(ScrollableList.class, "effect_" + i);
  if (fx == null) return;
  fx.changeValue(mode);
  fx.getCaptionLabel().setText("FX  " + labels[mode] + "  v");
}
'@.Replace("`r`n","`n").TrimEnd("`n")
$pde = ReplaceRegexOnce $pde $updateFxPattern $updateFxNew "update FX dropdown"

$eventPattern = '  if \(e\.isController\(\) && e\.getName\(\)\.startsWith\("effect_"\)\) \{\r?\n    int i = int\(e\.getName\(\)\.substring\(7\)\);\r?\n    Channel ch = allChannels\.get\(i\);\r?\n    ch\.fxMode = \(ch\.fxMode \+ 1\) % 4;\r?\n    updateEffectButton\(i\);\r?\n    updateChannelControls\(i\);\r?\n    return;\r?\n  \}'
$eventNew = @'
  if (e.isController() && e.getName().startsWith("effect_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.fxMode = constrain(round(e.getValue()), 0, 3);
    updateEffectButton(i);
    updateChannelControls(i);
    cp5.get(ScrollableList.class, "effect_" + i).close();
    return;
  }
'@.Replace("`r`n","`n").TrimEnd("`n")
$pde = ReplaceRegexOnce $pde $eventPattern $eventNew "FX dropdown event"

# Tests.
$test = ReadText "tests\InterfaceCheck.java"

$clickAnchor = @'
  public static void main(String[] args) {
'@.Replace("`r`n","`n")
$selectFx = @'
  static void selectFx(int channel, int mode) {
    var list = app.cp5.get(ScrollableList.class, "effect_"+channel);
    if (!list.isOpen()) click("effect_"+channel);
    check(list.isOpen(),"FX dropdown opens");
    float[] p = list.getPosition();
    int x = (int)p[0] + list.getWidth()/2;
    int y = (int)p[1] + 28 + mode*28 + 14;
    app.mousePressed=false;
    app.cp5.getWindow().mouseEvent(x,y,false);
    app.mousePressed=true;
    app.cp5.getWindow().mouseEvent(x,y,true);
    app.mousePressed=false;
    app.cp5.getWindow().mouseEvent(x,y,false);
  }

'@.Replace("`r`n","`n")
$test = ReplaceLiteralOnce $test $clickAnchor ($selectFx + $clickAnchor) "FX test helper"

$fxTestPattern = '      app\.allChannels\.get\(first\)\.fxMode=app\.FX_MANUAL;.*?      check\(app\.allChannels\.get\(first\)\.fxMode==app\.FX_STROBE,"FX still clickable after full cycle"\);\r?\n'
$fxTestNew = @'
      app.allChannels.get(first).fxMode=app.FX_MANUAL;
      app.updateEffectButton(first);
      app.updateChannelControls(first);
      var fxList=app.cp5.get(ScrollableList.class,"effect_"+first);
      int modeBefore=app.allChannels.get(first).fxMode;
      click("effect_"+first);
      check(fxList.isOpen(),"FX dropdown opens from bar");
      check(app.allChannels.get(first).fxMode==modeBefore,"opening FX dropdown preserves mode");
      fxList.close();
      if (!app.allChannels.get(first).sequencer.active) click("seq_"+first);
      check(app.allChannels.get(first).sequencer.active,"sequencer active before FX menu");
      for (int fx : new int[]{1,2,3,0}) {
        selectFx(first,fx);
        check(app.allChannels.get(first).fxMode==fx,"direct FX selection "+fx);
        check(!fxList.isOpen(),"FX dropdown closes after selection");
        check(app.allChannels.get(first).sequencer.active,"SEQ stays active with FX "+fx);
      }
'@.Replace("`r`n","`n")
$test = ReplaceRegexOnce $test $fxTestPattern $fxTestNew "replace cyclic FX tests"

$monoPattern = '      var mono=app\.allChannels\.get\(first\);.*?      check\(Math\.abs\(app\.channelMaster\(mono\)-\(1536f/4095f\)\)<0\.0001f,"mono sequencer intensity"\);\r?\n'
$monoNew = @'
      var mono=app.allChannels.get(first);
      mono.isRGB=false;
      mono.fxMode=app.FX_MANUAL;
      mono.sequencer.active=false;
      mono.sequencer.steps.clear();
      mono.manualVal=512;
      app.mouseX=app.stepsX(first)+5;
      app.mouseY=app.stepsY()+5;
      app.mouseButton=PApplet.LEFT;
      app.mousePressed();
      check(mono.sequencer.steps.size()==1 && mono.sequencer.steps.get(0).intensity==512,"new mono step uses fader level");
      mono.manualVal=3072;
      app.mouseX=app.stepsX(first)+app.stepSize+app.stepGap+5;
      app.mouseY=app.stepsY()+5;
      app.mousePressed();
      check(mono.sequencer.steps.size()==2 && mono.sequencer.steps.get(1).intensity==3072,"second mono step uses new fader level");
      mono.sequencer.active=true;
      mono.sequencer.currentStep=0;
      int monoLow=app.computeMonoOutput(mono,1.0f);
      mono.sequencer.currentStep=1;
      int monoHigh=app.computeMonoOutput(mono,1.0f);
      check(monoLow==512 && monoHigh==3072,"mono sequencer reaches physical output values");
'@.Replace("`r`n","`n")
$test = ReplaceRegexOnce $test $monoPattern $monoNew "mono output tests"

$test = $test.Replace(
  'PASS: resolutions, FX cycle, BLIND, mono sequencer, routing RGB, paging, scenes, clone, text fields and blackout',
  'PASS: resolutions, FX dropdown, BLIND, mono sequencer output, routing RGB, paging, scenes, clone, text fields and blackout'
)

# TODO: keep both tasks open until the user validates them on the real UI/hardware.
$todo = ReadText "TODO.md"
$todo = $todo.Replace(
  "- [ ] Le sequenceur agit aussi sur le mode mono; Actuellement, l'animation UI est ok mais rien en sortie",
  "- [ ] Valider sur materiel le sequenceur mono apres correctif : chaque nouveau pas prend le niveau du fader et la sortie mono suit l'intensite du pas"
)
$todo = $todo.Replace(
  '- [ ] retabllir un menu deroulant fonctionnel pour les fx',
  '- [ ] Valider le menu deroulant FX ControlP5 : MAN / STR / FEU / PUL, sans gel de l UI'
)

# Static validation before any write.
if (([regex]::Matches($pde, [regex]::Escape('computeMonoOutput(Channel ch, float eff)'))).Count -ne 1) {
  throw "STOP: computeMonoOutput validation failed"
}
if (([regex]::Matches($pde, [regex]::Escape('cp5.addScrollableList("effect_" + i)'))).Count -ne 1) {
  throw "STOP: FX dropdown creation validation failed"
}
if ($pde.Contains('ch.fxMode = (ch.fxMode + 1) % 4;')) {
  throw "STOP: cyclic FX handler still present"
}
if ($pde.Contains('new Step(2048, red(col), green(col), blue(col))')) {
  throw "STOP: fixed 2048 step creation still present"
}
if (-not $test.Contains('mono sequencer reaches physical output values')) {
  throw "STOP: mono output test missing"
}
if (-not $test.Contains('FX dropdown opens from bar')) {
  throw "STOP: FX dropdown test missing"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $Root ("backups\before-mono-fx-menu-" + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item "DIMYX_3_3.pde" (Join-Path $backup "DIMYX_3_3.pde")
Copy-Item "tests\InterfaceCheck.java" (Join-Path $backup "InterfaceCheck.java")
Copy-Item "TODO.md" (Join-Path $backup "TODO.md")

WriteText "DIMYX_3_3.pde" $pde
WriteText "tests\InterfaceCheck.java" $test
WriteText "TODO.md" $todo

Write-Host ""
Write-Host "Applied safely." -ForegroundColor Green
Write-Host "Mono: new steps use current fader value; cache forced on RGB/SEQ mode changes."
Write-Host "Mono: final output value is now directly regression-tested."
Write-Host "FX: real ScrollableList dropdown replaces cyclic button."
Write-Host "TODO: both items remain unchecked until your manual validation."
Write-Host ""
Write-Host "Run:"
Write-Host "  git -c core.safecrlf=false --no-pager diff --check"
Write-Host "  .\tests\run-interface.ps1 -Render"
