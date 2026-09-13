param(
  [string]$ProcessingHome = 'C:/Program Files/Processing',
  [string]$ControlP5Home = "$env:USERPROFILE/Documents/Processing/libraries/controlP5",
  [switch]$Render
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputDirectory = Join-Path $projectRoot 'build/interface-tests'
$java = Join-Path $ProcessingHome 'app/resources/jdk/bin/java.exe'
$javac = Join-Path $ProcessingHome 'app/resources/jdk/bin/javac.exe'
$processingJars = Join-Path $ProcessingHome 'app/*'
$serialJars = Join-Path $ProcessingHome 'app/resources/modes/java/libraries/serial/library/*'
$controlJars = Join-Path $ControlP5Home 'library/*'
foreach ($required in @($java, $javac, (Join-Path $ControlP5Home 'library/controlP5.jar'))) {
  if (!(Test-Path -LiteralPath $required)) { throw "Fichier requis absent : $required" }
}
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$generated = Join-Path $outputDirectory 'DIMYX_3_3.java'
& $java -cp $processingJars (Join-Path $PSScriptRoot 'Preprocess.java') (Join-Path $projectRoot 'DIMYX_3_3.pde') $generated
if ($LASTEXITCODE -ne 0) { throw 'Echec du pretraitement Processing.' }
$classPath = "$outputDirectory;$processingJars;$serialJars;$controlJars"
& $javac -encoding UTF-8 -cp $classPath -d $outputDirectory $generated (Join-Path $PSScriptRoot 'InterfaceCheck.java')
if ($LASTEXITCODE -ne 0) { throw 'Echec de compilation.' }
$renderArguments = @()
if ($Render) { $renderArguments = @($outputDirectory) }
& $java -cp $classPath InterfaceCheck @renderArguments
if ($LASTEXITCODE -ne 0) { throw 'Echec des tests de l interface.' }
