$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ReplaceRegexOnce([string]$Text, [string]$Pattern, [string]$New, [string]$Label) {
  $rx = New-Object System.Text.RegularExpressions.Regex($Pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  $m = $rx.Matches($Text)
  if ($m.Count -ne 1) { throw "STOP: $Label matches=$($m.Count)" }
  return $rx.Replace($Text,[System.Text.RegularExpressions.MatchEvaluator]{param($x) $New},1)
}

if ((& git branch --show-current).Trim() -ne "fix/fx-layout-deferred") { throw "STOP: wrong branch" }
$pdePath = Join-Path $Root "DIMYX_3_3.pde"
$testPath = Join-Path $Root "tests\InterfaceCheck.java"
$todoPath = Join-Path $Root "TODO.md"
$pde = [System.IO.File]::ReadAllText($pdePath)
$test = [System.IO.File]::ReadAllText($testPath)
$todo = [System.IO.File]::ReadAllText($todoPath)
$nl = if ($pde.Contains("`r`n")) { "`r`n" } else { "`n" }

if (-not $pde.Contains("void startStepEditing(int channelIndex, int stepIndex)")) { throw "STOP: step editor helper missing" }
if (-not $pde.Contains("boolean doubleClick = lastClickedStepChannel")) { throw "STOP: expected double-click step logic missing" }
if ($pde.Contains("single click edits the step")) { throw "STOP: step-edit patch already installed" }

$leftPattern = '        if \(mouseButton == LEFT\) \{\r?\n          selectedStepChannel = i;\r?\n          selectedStepIndex = j;\r?\n          boolean doubleClick = lastClickedStepChannel == i && lastClickedStepIndex == j && millis\(\) - lastStepClickTime < 350;\r?\n          if \(doubleClick\) startStepEditing\(i, j\);\r?\n          else stepEditMode = false;\r?\n          lastStepClickTime = millis\(\);\r?\n          lastClickedStepChannel = i;\r?\n          lastClickedStepIndex = j;\r?\n        \}'
$leftNew = @'
        if (mouseButton == LEFT) {
          // A single click edits the step: fader = intensity, wheel = RGB color.
          startStepEditing(i, j);
          lastStepClickTime = millis();
          lastClickedStepChannel = i;
          lastClickedStepIndex = j;
        }
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceRegexOnce $pde $leftPattern $leftNew "single-click step edit"

$newStepPattern = '        ch\.sequencer\.steps\.add\(new Step\(constrain\(ch\.manualVal, 0, 4095\), red\(col\), green\(col\), blue\(col\)\)\);\r?\n        selectedStepChannel = i;\r?\n        selectedStepIndex = j;\r?\n        stepEditMode = false;'
$newStepNew = @'
        ch.sequencer.steps.add(new Step(constrain(ch.manualVal, 0, 4095), red(col), green(col), blue(col)));
        startStepEditing(i, j);
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceRegexOnce $pde $newStepPattern $newStepNew "new step enters edit mode"

# Add a small edit indicator above the step grid.
$drawAnchor = '  fill\(ch\.sequencer\.active \? color\(0, 255, 0\) : color\(100\)\);\r?\n  ellipse\(x \+ perRow \* \(sz \+ gap\) - 10, y - 10, 8, 8\);'
$drawNew = @'
  fill(ch.sequencer.active ? color(0, 255, 0) : color(100));
  ellipse(x + perRow * (sz + gap) - 10, y - 10, 8, 8);

  if (stepEditMode && i == selectedStepChannel && hasSelectedStep()) {
    fill(0, 200, 255);
    textAlign(LEFT, BASELINE);
    textSize(10);
    text("EDIT " + (selectedStepIndex + 1), x, y - 7);
  }
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceRegexOnce $pde $drawAnchor $drawNew "step edit indicator"

# Strengthen the existing interface regression around a step click.
$testNl = if ($test.Contains("`r`n")) { "`r`n" } else { "`n" }
$testOld = '      app\.mousePressed\(\); check\(app\.selectedStepChannel==app\.firstChannel\(\),"step hit after paging"\);'
$testNew = @'
      app.mousePressed(); check(app.selectedStepChannel==app.firstChannel(),"step hit after paging");
      check(app.stepEditMode,"single click enters step edit mode");
      int editChannel=app.firstChannel();
      int editStep=app.selectedStepIndex;
      app.setFaderValue(editChannel,1777);
      check(app.allChannels.get(editChannel).sequencer.steps.get(editStep).intensity==1777,"step intensity editable from fader");
'@.Replace("`r`n","`n").Replace("`n",$testNl).TrimEnd("`r","`n")
$test = ReplaceRegexOnce $test $testOld $testNew "step edit regression"

$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] rendre les steps du sequencer .*ditables, couleur et intensit.*$',
  '- [ ] Valider l''edition des steps: clic simple, intensite au fader et couleur a la roue RGB'
)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $Root ("backups\before-step-edit-" + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item $pdePath (Join-Path $backup "DIMYX_3_3.pde")
Copy-Item $testPath (Join-Path $backup "InterfaceCheck.java")
Copy-Item $todoPath (Join-Path $backup "TODO.md")

[System.IO.File]::WriteAllText($pdePath,$pde,$Utf8NoBom)
[System.IO.File]::WriteAllText($testPath,$test,$Utf8NoBom)
[System.IO.File]::WriteAllText($todoPath,$todo,$Utf8NoBom)

Write-Host "Applied: sequencer steps are directly editable." -ForegroundColor Green
Write-Host "Run: .\tests\run-interface.ps1 -Render"
