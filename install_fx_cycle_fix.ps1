$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $Root "DIMYX_3_3.pde"
$Temp = Join-Path $env:TEMP "DIMYX_3_3_clean_from_github.pde"
$Url = "https://raw.githubusercontent.com/baaaat/DIMYX_3_3/feature/interface-adaptative/DIMYX_3_3.pde"
$ExpectedBlobSha = "843ba1da073c649c346bb93cc80d8c35446cd3af"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $Target)) {
    throw "DIMYX_3_3.pde introuvable. Place ce script dans le meme dossier."
}

function Git-Blob-Sha1([byte[]]$Bytes) {
    $Header = [System.Text.Encoding]::UTF8.GetBytes("blob $($Bytes.Length)`0")
    $All = New-Object byte[] ($Header.Length + $Bytes.Length)
    [Array]::Copy($Header, 0, $All, 0, $Header.Length)
    [Array]::Copy($Bytes, 0, $All, $Header.Length, $Bytes.Length)
    $Sha1 = [System.Security.Cryptography.SHA1]::Create()
    try { $Hash = $Sha1.ComputeHash($All) } finally { $Sha1.Dispose() }
    return (($Hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Replace-RegexOnce([string]$Text,[string]$Pattern,[string]$Replacement,[string]$Label) {
    $Regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $Matches = $Regex.Matches($Text)
    if ($Matches.Count -ne 1) {
        throw "Bloc '$Label' trouve $($Matches.Count) fois. Rien n'a ete ecrit."
    }
    return $Regex.Replace(
        $Text,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Replacement },
        1
    )
}

Write-Host "Recuperation du PDE propre depuis GitHub..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $Url -OutFile $Temp -UseBasicParsing

$Bytes = [System.IO.File]::ReadAllBytes($Temp)
$Sha = Git-Blob-Sha1 $Bytes
if ($Sha -ne $ExpectedBlobSha) {
    throw "La version GitHub a change ($Sha). Arret sans modification."
}
Write-Host "Version GitHub verifiee." -ForegroundColor Green

$Text = [System.IO.File]::ReadAllText($Temp)
$NL = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }

# 1. Aucun menu superpose : RGB et SEQ restent toujours a leur place,
#    les anciens boutons fxChoice ne sont jamais affiches.
$Layout = @'
    place("name_" + i, x, 88, w, 28, visible);
    place("effect_" + i, x, 120, w, 28, live);
    place("rgb_" + i, x, outputsView ? 136 : 152, w, 28, visible);
    place("seq_" + i, x, 184, w, 28, live);
    for (int mode = 0; mode < 4; mode++) place("fxChoice_" + i + "_" + mode, x, 152 + mode * 32, w, 28, false);
    place("freq_" + i, x, 216, w, 28, live);
'@.Replace("`n",$NL).TrimEnd("`r","`n")

$Text = Replace-RegexOnce `
    $Text `
    '    place\("name_" \+ i, x, 88, w, 28, visible\);\s*place\("effect_" \+ i, x, 120, w, 28, live\);\s*boolean menu = live && effectMenuChannel == i;\s*place\("rgb_" \+ i, x, outputsView \? 136 : 152, w, 28, visible && !menu\);\s*place\("seq_" \+ i, x, 184, w, 28, live && !menu\);\s*for \(int mode = 0; mode < 4; mode\+\+\) place\("fxChoice_" \+ i \+ "_" \+ mode, x, 152 \+ mode \* 32, w, 28, menu\);\s*place\("freq_" \+ i, x, 216, w, 28, live\);' `
    $Layout `
    "layout des effets"

# 2. FREQ/MIN depend uniquement du mode FX, plus de l'etat du menu.
$Text = $Text.Replace(
    "boolean showFX = live && effectMenuChannel != i && ch.fxMode != FX_MANUAL;",
    "boolean showFX = live && ch.fxMode != FX_MANUAL;"
)

# 3. Supprimer toute logique de fermeture du menu dans mousePressed.
$Mouse = @'
void mousePressed() {
  if (outputsView || (narrowLayout && scenesView)) return;
'@.Replace("`n",$NL).TrimEnd("`r","`n")

$Text = Replace-RegexOnce `
    $Text `
    'void mousePressed\(\) \{\s*if \(effectMenuChannel >= 0\) \{\s*int x = channelX\(effectMenuChannel\);\s*if \(mouseX < x \|\| mouseX >= x \+ stripControlWidth \|\| mouseY < 120 \|\| mouseY >= 280\) \{\s*effectMenuChannel = -1;\s*layoutInterface\(\);\s*\}\s*\}\s*if \(outputsView \|\| \(narrowLayout && scenesView\)\) return;' `
    $Mouse `
    "mousePressed"

# 4. Le bouton FX fait simplement defiler les 4 modes. Aucun layoutInterface().
$FxEvent = @'
  if (e.isController() && e.getName().startsWith("effect_")) {
    int i = int(e.getName().substring(7));
    Channel ch = allChannels.get(i);
    ch.fxMode = (ch.fxMode + 1) % 4;
    updateEffectButton(i);
    updateChannelControls(i);
    return;
  }
'@.Replace("`n",$NL)

$Text = Replace-RegexOnce `
    $Text `
    '  if \(e\.isController\(\) && e\.getName\(\)\.startsWith\("effect_"\)\) \{.*?(?=  if \(e\.isController\(\) && e\.getName\(\)\.startsWith\("usbPort_"\)\))' `
    $FxEvent `
    "controlEvent FX"

# 5. Libelle coherent avec un bouton cyclique.
$Text = $Text.Replace(
    'cp5.get(Button.class, "effect_" + i).setLabel("FX  " + labels[mode] + "  v");',
    'cp5.get(Button.class, "effect_" + i).setLabel("FX  " + labels[mode] + "  >");'
)
$Text = $Text.Replace(
    'capsuleButton("effect_" + i, "FX  MAN  v", color(60, 83, 109));',
    'capsuleButton("effect_" + i, "FX  MAN  >", color(60, 83, 109));'
)

# 6. Les anciens fxChoice ne sont meme plus crees.
$Text = Replace-RegexOnce `
    $Text `
    '    String\[\] effects = \{"MAN", "STR", "FEU", "PUL"\};\s*for \(int mode = 0; mode < effects\.length; mode\+\+\) capsuleButton\("fxChoice_" \+ i \+ "_" \+ mode, effects\[mode\], color\(74, 99, 132\)\);\s*' `
    '' `
    "creation fxChoice"

# Validations simples.
if (($Text | Select-String -Pattern 'startsWith\("fxChoice_"\)' -AllMatches).Matches.Count -ne 0) {
    throw "Validation : un callback fxChoice_ subsiste. Rien n'a ete ecrit."
}
if (($Text | Select-String -Pattern 'boolean menu = live && effectMenuChannel == i' -AllMatches).Matches.Count -ne 0) {
    throw "Validation : la logique de menu subsiste. Rien n'a ete ecrit."
}
if (($Text | Select-String -Pattern 'ch.fxMode = \(ch.fxMode \+ 1\) % 4;' -AllMatches).Matches.Count -ne 1) {
    throw "Validation : bouton FX cyclique absent. Rien n'a ete ecrit."
}

$Open = ($Text.ToCharArray() | Where-Object { $_ -eq '{' }).Count
$Close = ($Text.ToCharArray() | Where-Object { $_ -eq '}' }).Count
if ($Open -ne $Close) {
    throw "Accolades desequilibrees : $Open / $Close. Rien n'a ete ecrit."
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = "$Target.before-fx-cycle-$Stamp.bak"
Copy-Item $Target $Backup -Force

[System.IO.File]::WriteAllText($Target,$Text,$Utf8NoBom)

Write-Host ""
Write-Host "OK : PDE propre installe avec bouton FX cyclique." -ForegroundColor Green
Write-Host "FX : MAN -> STR -> FEU -> PUL -> MAN" -ForegroundColor Green
Write-Host "Aucun menu FX superpose n'est encore actif." -ForegroundColor Green
Write-Host "Sauvegarde locale : $Backup"
Write-Host ""
Write-Host "Rouvre Processing et compile."
