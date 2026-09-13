$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function GitHash([string]$Path) {
  $h = (& git hash-object -- $Path 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($h)) {
    throw "Cannot hash file: $Path"
  }
  return $h.Trim()
}

function RequireHash([string]$Path, [string]$Expected) {
  if (-not (Test-Path $Path)) { throw "Missing file: $Path" }
  $actual = GitHash $Path
  if ($actual -ne $Expected) {
    throw "File changed: $Path ; got $actual ; expected $Expected"
  }
}

function ReadText([string]$Path) {
  return [System.IO.File]::ReadAllText((Join-Path $Root $Path))
}

function WriteText([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText((Join-Path $Root $Path), $Text, $Utf8NoBom)
}

function Eol([string]$Text) {
  if ($Text.Contains("`r`n")) { return "`r`n" }
  return "`n"
}

function ReplaceOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  $n = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
  if ($n -ne 1) { throw "Replace failed: $Label ; matches=$n" }
  return $Text.Replace($Old, $New)
}

function ReplaceRegexOnce([string]$Text, [string]$Pattern, [string]$New, [string]$Label) {
  $rx = New-Object System.Text.RegularExpressions.Regex(
    $Pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  $m = $rx.Matches($Text)
  if ($m.Count -ne 1) { throw "Regex replace failed: $Label ; matches=$($m.Count)" }
  return $rx.Replace(
    $Text,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $New },
    1
  )
}

$branch = (& git branch --show-current).Trim()
if ($branch -ne "fix/fx-layout-deferred") {
  throw "Wrong branch: $branch"
}

$TodoPath = $null
if (Test-Path "TODO.md") { $TodoPath = "TODO.md" }
elseif (Test-Path "TODO.md.md") { $TodoPath = "TODO.md.md" }
else { throw "TODO file not found" }

RequireHash "DIMYX_3_3.pde" "20c61445b4056d89e767b7b04bcaa3e808cdb835"
RequireHash "tests\InterfaceCheck.java" "7765b49e738ffaa230eca230390a583810b07f61"
RequireHash "README.md" "ee9b9f8f8126a2d16b9f133acc6fa612fd473211"
RequireHash "docs\ARCHITECTURE.md" "61bf5911dad1a379ba99e212bb8e720db916dfe2"
RequireHash "CONTRIBUTING.md" "4872565c3a4a816348dec1efd1f977c57803646d"
RequireHash $TodoPath "8cc7d49cb2ad13f5d1ab2183aa5e40958dc01ce3"

Write-Host "Preflight OK." -ForegroundColor Green

# Build all edited contents in memory first.
$pde = ReadText "DIMYX_3_3.pde"
$nl = Eol $pde

$pde = ReplaceOnce $pde `
  'boolean outputsView = false, scenesView = false, narrowLayout = false;' `
  ('boolean outputsView = false, scenesView = false, narrowLayout = false;' + $nl + 'boolean blindActive = false;') `
  "blind state"

$pde = ReplaceOnce $pde `
  'cp5.get(Button.class, "outputsView").setLabel(outputsView ? "< CONSOLE" : "SORTIES / USB");' `
  'cp5.get(Button.class, "outputsView").setLabel(outputsView ? "< CONSOLE" : "SORTIES");' `
  "outputs label"

$pde = ReplaceOnce $pde `
  '  place("channelNext", 316, 16, 34, 32, !(narrowLayout && scenesView));' `
  ('  place("channelNext", 316, 16, 34, 32, !(narrowLayout && scenesView));' + $nl +
   '  place("blindMode", 356, 16, 94, 32, true);') `
  "blind layout"

$pde = ReplaceOnce $pde `
  '    place("rgb_" + i, x, outputsView ? 136 : 152, w, 28, visible);' `
  '    place("rgb_" + i, x, 136, w, 28, visible && outputsView);' `
  "rgb routing only"

$pde = ReplaceOnce $pde `
  '  if (!(narrowLayout && scenesView)) text((firstChannel() + 1) + "-" + min(nbChannels, firstChannel() + channelsPerPage) + " / " + nbChannels, 364, 37);' `
  '  if (!(narrowLayout && scenesView)) text((firstChannel() + 1) + "-" + min(nbChannels, firstChannel() + channelsPerPage) + "/" + nbChannels, 458, 37);' `
  "page counter"

$helpers = @'
final int LEGACY_FX_SEQUENCER = 4;

float channelMaster(Channel ch) {
  return (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;
}

boolean physicalOutputEnabled() {
  return !blindActive;
}
'@
$helpers = $helpers.Replace("`r`n", "`n").Replace("`n", $nl).TrimEnd("`r","`n")
$pde = ReplaceOnce $pde 'final int LEGACY_FX_SEQUENCER = 4;' $helpers "output helpers"

$pde = ReplaceOnce $pde `
  '    if (serialConnected && myPort != null && now - lastSendTime > sendInterval) {' `
  '    if (serialConnected && myPort != null && physicalOutputEnabled() && now - lastSendTime > sendInterval) {' `
  "blind output gate"

$pde = ReplaceOnce $pde `
  '        float master = (ch.sequencer.active ? ch.sequencer.getCurrentIntensity() : ch.manualVal) / 4095.0;' `
  '        float master = channelMaster(ch);' `
  "mono sequencer master"

$pde = ReplaceOnce $pde `
  '  capsuleButton("outputsView", "SORTIES / USB", color(58, 77, 102));' `
  ('  capsuleButton("outputsView", "SORTIES", color(58, 77, 102));' + $nl +
   '  cp5.addToggle("blindMode").setValue(false).setLabel("").setView(new ChipView("BLIND", color(191, 139, 48)));') `
  "blind gui"

$blindCallback = @'
public void outputsView() { effectMenuChannel = -1; outputsView = !outputsView; layoutInterface(); }
public void blindMode(boolean v) {
  blindActive = v;
  invalidateOutputCache();
  println("BLIND " + (v ? "ON" : "OFF"));
}
'@
$blindCallback = $blindCallback.Replace("`r`n", "`n").Replace("`n", $nl).TrimEnd("`r","`n")
$pde = ReplaceOnce $pde `
  'public void outputsView() { effectMenuChannel = -1; outputsView = !outputsView; layoutInterface(); }' `
  $blindCallback `
  "blind callback"

$pde = ReplaceOnce $pde `
  'cp5.addToggle("rgb_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("RGB", color(0, 200, 255)));' `
  '    cp5.addToggle("rgb_" + i).setSize(128, 28).setValue(false).setLabel("").setView(new ChipView("RGB", color(0, 200, 255)));' `
  "rgb indent"

$pde = ReplaceOnce $pde `
  '  }  if (e.isController() && e.getName().startsWith("usbPort_")) {' `
  ('  }' + $nl + '  if (e.isController() && e.getName().startsWith("usbPort_")) {') `
  "control event spacing"

# Tests: remove stale deferred-menu hooks and validate current FX cycle.
$test = ReadText "tests\InterfaceCheck.java"
$tnl = Eol $test

$test = $test.Replace('    app.applyPendingLayout();' + $tnl, '')
$test = $test.Replace('      sequencerEffectsRegression(first);' + $tnl, '')

$fxTests = @'
      boolean originalRgb=app.allChannels.get(first).isRGB;
      check(!app.cp5.getController("rgb_"+first).isVisible(),"RGB hidden in console");
      app.allChannels.get(first).fxMode=app.FX_MANUAL;
      app.updateEffectButton(first);
      app.updateChannelControls(first);
      if (!app.allChannels.get(first).sequencer.active) click("seq_"+first);
      check(app.allChannels.get(first).sequencer.active,"sequencer active before FX cycle");
      for (int fx : new int[]{1,2,3}) {
        click("effect_"+first);
        check(app.allChannels.get(first).fxMode==fx,"FX cycle mode "+fx);
        check(app.allChannels.get(first).sequencer.active,"SEQ stays active with FX "+fx);
        check(app.cp5.getController("bpm_"+first).isVisible(),"BPM visible with SEQ+FX "+fx);
        check(app.cp5.getController("freq_"+first).isVisible(),"FREQ visible with FX "+fx);
        check(app.cp5.getController("min_"+first).isVisible(),"MIN visible with FX "+fx);
      }
      click("effect_"+first);
      check(app.allChannels.get(first).fxMode==app.FX_MANUAL,"FX cycle back to MAN");
      click("effect_"+first);
      check(app.allChannels.get(first).fxMode==app.FX_STROBE,"FX still clickable after full cycle");
'@
$fxTests = $fxTests.Replace("`r`n","`n").Replace("`n",$tnl).TrimEnd("`r","`n") + $tnl

$test = ReplaceRegexOnce $test `
  '      boolean rgb=app\.allChannels\.get\(first\)\.isRGB;.*?(?=      float oldBpm=app\.allChannels\.get\(first\)\.sequencer\.bpm;)' `
  $fxTests `
  "old FX menu tests"

$monoBlind = @'
      var mono=app.allChannels.get(first);
      mono.isRGB=false;
      mono.sequencer.active=true;
      mono.sequencer.currentStep=0;
      mono.sequencer.steps.get(0).intensity=1536;
      check(Math.abs(app.channelMaster(mono)-(1536f/4095f))<0.0001f,"mono sequencer intensity");
      mono.isRGB=originalRgb;
      check(app.physicalOutputEnabled(),"output live by default");
      click("blindMode");
      check(app.blindActive && !app.physicalOutputEnabled(),"BLIND blocks physical output");
      click("blindMode");
      check(!app.blindActive && app.physicalOutputEnabled(),"leaving BLIND restores output");
'@
$monoBlind = $monoBlind.Replace("`r`n","`n").Replace("`n",$tnl).TrimEnd("`r","`n")

$test = ReplaceOnce $test `
  '      check(app.allChannels.get(first).fxFreq!=oldFreq,"FREQ reacts after SEQ+FX");' `
  ('      check(app.allChannels.get(first).fxFreq!=oldFreq,"FREQ reacts after SEQ+FX");' + $tnl + $monoBlind) `
  "mono and blind tests"

$routingOld = @'
      click("outputsView"); check(app.outputsView,"routing view button"); bounds();
      check(!app.cp5.getController("fader_"+app.firstChannel()).isVisible(),"routing hides live controls");
'@
$routingOld = $routingOld.Replace("`r`n","`n").Replace("`n",$tnl).TrimEnd("`r","`n")
$routingNew = @'
      click("outputsView"); check(app.outputsView,"routing view button"); bounds();
      check(!app.cp5.getController("fader_"+app.firstChannel()).isVisible(),"routing hides live controls");
      check(app.cp5.getController("rgb_"+app.firstChannel()).isVisible(),"routing shows RGB selector");
      boolean routingRgb=app.allChannels.get(app.firstChannel()).isRGB;
      click("rgb_"+app.firstChannel());
      check(app.allChannels.get(app.firstChannel()).isRGB!=routingRgb,"RGB changes in routing view");
      click("rgb_"+app.firstChannel());
'@
$routingNew = $routingNew.Replace("`r`n","`n").Replace("`n",$tnl).TrimEnd("`r","`n")
$test = ReplaceOnce $test $routingOld $routingNew "routing RGB test"

$test = ReplaceOnce $test `
  '      click("outputsView"); check(!app.outputsView,"console return");' `
  ('      click("outputsView"); check(!app.outputsView,"console return");' + $tnl +
   '      check(!app.cp5.getController("rgb_"+app.firstChannel()).isVisible(),"RGB hidden after console return");') `
  "console RGB hidden test"

$test = $test.Replace(
  'PASS: five resolutions, bounds, mouse hit areas, sliders, SEQ+FX, paging, routing, scenes, clone, text fields and blackout',
  'PASS: resolutions, FX cycle, BLIND, mono sequencer, routing RGB, paging, scenes, clone, text fields and blackout'
)

# README: append a compact ASCII-only section. This avoids parser/quote issues.
$readme = ReadText "README.md"
$rnl = Eol $readme
$readmeExtra = @'

## BLIND, SORTIES et sequenceur mono

Le bouton **SORTIES** ouvre la configuration materielle. Le selecteur **RGB** est visible uniquement dans cette vue et n'apparait plus dans la console.

Le mode **BLIND** permet de programmer niveaux, couleurs, effets, sequenceurs et scenes sans envoyer les commandes de niveau au materiel. Le heartbeat USB reste actif. En quittant BLIND, l'etat programme est renvoye vers les sorties. **BLACKOUT** reste prioritaire et continue d'agir sur le materiel pendant BLIND.

Le sequenceur pilote aussi une tranche mono : dans ce cas, seule l'intensite du pas courant est utilisee. Sur une tranche RGB, le pas fournit aussi sa couleur.

Le bouton **FX** est cyclique : MAN -> STR -> FEU -> PUL -> MAN.
'@
$readmeExtra = $readmeExtra.Replace("`r`n","`n").Replace("`n",$rnl)
if (-not $readme.Contains("## BLIND, SORTIES et sequenceur mono")) {
  $readme = $readme.TrimEnd("`r","`n") + $readmeExtra + $rnl
}

# Architecture: append maintenance notes.
$arch = ReadText "docs\ARCHITECTURE.md"
$anl = Eol $arch
$archExtra = @'

## Evolutions console / sorties

`blindActive` suspend uniquement l'envoi periodique des commandes `P,...`. Le heartbeat serie reste actif. La bascule BLIND invalide le cache de sortie afin de forcer une reemission complete quand on revient en live. Le BLACKOUT conserve son envoi direct `X`.

`channelMaster` centralise la source de niveau : fader manuel ou intensite du pas courant lorsque le sequenceur est actif. Cette logique est identique en mono et en RGB ; la couleur du pas n'est utilisee qu'en RGB.

Le controle `rgb_` n'est visible que dans la vue SORTIES. Le bouton `effect_` reste cyclique et ne cree aucun controle superpose.
'@
$archExtra = $archExtra.Replace("`r`n","`n").Replace("`n",$anl)
if (-not $arch.Contains("## Evolutions console / sorties")) {
  $arch = $arch.TrimEnd("`r","`n") + $archExtra + $anl
}

# Contributing: append explicit manual validation.
$contrib = ReadText "CONTRIBUTING.md"
$cnl = Eol $contrib
$contribExtra = @'

### Validation BLIND / SORTIES / mono

- Verifier que RGB est cache dans la console et disponible dans SORTIES.
- En mono, activer SEQ avec plusieurs intensites et verifier que seule l'intensite varie.
- Activer BLIND, modifier faders, FX, sequenceurs et scenes : le materiel ne doit pas changer.
- Verifier que le heartbeat reste actif en BLIND.
- Quitter BLIND : l'etat programme doit etre envoye.
- Verifier que BLACKOUT coupe toujours les sorties meme avec BLIND actif.
'@
$contribExtra = $contribExtra.Replace("`r`n","`n").Replace("`n",$cnl)
if (-not $contrib.Contains("### Validation BLIND / SORTIES / mono")) {
  $contrib = $contrib.TrimEnd("`r","`n") + $contribExtra + $cnl
}

# TODO: update the four requested entries. Patterns avoid non-ASCII source text.
$todo = ReadText $TodoPath
$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] Supprimer le chip rgb on/off.*$',
  '- [x] Supprimer le chip rgb on/off sur la vue console, il est visible uniquement en vue SORTIES'
)
$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] Retablir le mode "blind".*$',
  '- [x] Retablir le mode "blind" : programmation sans agir sur les sorties'
)
$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] Le sequenceur doit aussi agir sur le mode mono\..*$',
  '- [x] Le sequenceur agit aussi sur le mode mono ; seule l intensite varie'
)
$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] Renommer "Sortie/USB" en "Sorties".*$',
  '- [x] Renommer "Sortie/USB" en "Sorties"'
)

# Validate in-memory result before writing.
if (([regex]::Matches($pde, [regex]::Escape('boolean blindActive = false;'))).Count -ne 1) {
  throw "Validation failed: blind state"
}
if (([regex]::Matches($pde, [regex]::Escape('float channelMaster(Channel ch)'))).Count -ne 1) {
  throw "Validation failed: channelMaster"
}
if ($pde.Contains('"SORTIES / USB"')) {
  throw "Validation failed: old outputs label remains in PDE"
}
if ($test.Contains("fxChoice_") -or $test.Contains("applyPendingLayout") -or $test.Contains("sequencerEffectsRegression")) {
  throw "Validation failed: stale FX tests remain"
}

# Backup, then write.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $Root ("backups\before-blind-routing-" + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null

foreach ($f in @("DIMYX_3_3.pde","tests\InterfaceCheck.java","README.md","docs\ARCHITECTURE.md","CONTRIBUTING.md",$TodoPath)) {
  $dst = Join-Path $backup ($f -replace '[\\/]', '__')
  Copy-Item (Join-Path $Root $f) $dst
}

WriteText "DIMYX_3_3.pde" $pde
WriteText "tests\InterfaceCheck.java" $test
WriteText "README.md" $readme
WriteText "docs\ARCHITECTURE.md" $arch
WriteText "CONTRIBUTING.md" $contrib
WriteText $TodoPath $todo

Write-Host ""
Write-Host "Changes applied." -ForegroundColor Cyan
Write-Host "RGB: routing view only"
Write-Host "BLIND: physical P commands suspended, heartbeat kept"
Write-Host "Mono SEQ: step intensity drives output"
Write-Host "SORTIES: renamed"
Write-Host "Tests and docs updated"
Write-Host ""

& git diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed" }

Write-Host "git diff --check: OK" -ForegroundColor Green
Write-Host "Next: .\tests\run-interface.ps1 -Render"
