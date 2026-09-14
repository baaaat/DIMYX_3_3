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

if ($pde.Contains("class Esp32Target")) { throw "STOP: ESP32 WiFi foundation already installed" }
if (-not $pde.Contains("import processing.serial.*;")) { throw "STOP: serial import anchor missing" }

$imports = @'
import processing.serial.*;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceOnce $pde 'import processing.serial.*;' $imports "network imports"

$globals = @'
Serial myPort;

class Esp32Target {
  String id;
  String host;
  int port;
  InetAddress address;

  Esp32Target(String id, String host, int port, InetAddress address) {
    this.id = id;
    this.host = host;
    this.port = port;
    this.address = address;
  }
}

DatagramSocket wifiSocket = null;
HashMap<String, Esp32Target> esp32Targets = new HashMap<String, Esp32Target>();
long lastWifiHeartbeatTime = 0;
final int defaultEsp32Port = 4210;
'@.Replace("`r`n","`n").Replace("`n",$nl).TrimEnd("`r","`n")
$pde = ReplaceOnce $pde 'Serial myPort;' $globals "ESP32 globals"

$methods = @'
void loadEsp32Targets() {
  esp32Targets.clear();
  try {
    JSONObject config = loadJSONObject("esp32Boards.json");
    JSONArray boards = config.getJSONArray("boards");
    for (int i = 0; i < boards.size(); i++) {
      JSONObject item = boards.getJSONObject(i);
      boolean enabled = !item.hasKey("enabled") || item.getBoolean("enabled");
      if (!enabled) continue;
      String id = trim(item.getString("id")).toUpperCase();
      String host = trim(item.getString("host"));
      int port = item.hasKey("port") ? item.getInt("port") : defaultEsp32Port;
      if (id.length() == 0 || host.length() == 0) continue;
      InetAddress address = InetAddress.getByName(host);
      esp32Targets.put(id, new Esp32Target(id, host, port, address));
    }
    if (!esp32Targets.isEmpty() && wifiSocket == null) wifiSocket = new DatagramSocket();
    println("ESP32 WiFi: " + esp32Targets.size() + " carte(s) active(s)");
  } catch (Exception e) {
    println("ESP32 WiFi indisponible: " + e.getMessage());
  }
}

boolean sendEsp32Command(String boardId, String command) {
  if (boardId == null || wifiSocket == null) return false;
  Esp32Target target = esp32Targets.get(trim(boardId).toUpperCase());
  if (target == null) return false;
  try {
    byte[] data = command.getBytes(StandardCharsets.UTF_8);
    DatagramPacket packet = new DatagramPacket(data, data.length, target.address, target.port);
    wifiSocket.send(packet);
    return true;
  } catch (Exception e) {
    println("ESP32 " + target.id + " envoi impossible: " + e.getMessage());
    return false;
  }
}

void sendEsp32Heartbeats(long now) {
  if (wifiSocket == null || esp32Targets.isEmpty()) return;
  if (now - lastWifiHeartbeatTime < heartbeatInterval) return;
  for (Esp32Target target : esp32Targets.values()) sendEsp32Command(target.id, "H\n");
  lastWifiHeartbeatTime = now;
}

'@.Replace("`r`n","`n").Replace("`n",$nl)

$pde = ReplaceOnce $pde 'boolean physicalOutputEnabled() {' ($methods + 'boolean physicalOutputEnabled() {') "ESP32 methods"

$pde = ReplaceOnce $pde `
  ('  loadChannelConfig();' + $nl + '  updateGUIFromChannels();') `
  ('  loadChannelConfig();' + $nl + '  loadEsp32Targets();' + $nl + '  updateGUIFromChannels();') `
  "load ESP32 config"

$pde = ReplaceOnce $pde `
  ('  pollSerialResponses();' + $nl) `
  ('  pollSerialResponses();' + $nl + '  sendEsp32Heartbeats(now);' + $nl) `
  "ESP32 heartbeat"

if (-not $pde.Contains("sendEsp32Command(String boardId, String command)")) { throw "STOP: validation failed" }

# Create an empty safe configuration: no packet is emitted until the user adds a board.
$configPath = Join-Path $Root "esp32Boards.json"
if (-not (Test-Path $configPath)) {
  $config = "{`n  `"boards`": []`n}`n"
  [System.IO.File]::WriteAllText($configPath,$config,$Utf8NoBom)
}

$docPath = Join-Path $Root "docs\ESP32_WIFI.md"
if (-not (Test-Path $docPath)) {
  $doc = @'
# ESP32 WiFi

DIMYX peut charger plusieurs cibles ESP32 depuis `esp32Boards.json`.

Exemple :

```json
{
  "boards": [
    {"id":"ESP1","host":"192.168.1.201","port":4210,"enabled":true},
    {"id":"ESP2","host":"192.168.1.202","port":4210,"enabled":true}
  ]
}
```

Le transport utilise UDP. Le contrat reprend les commandes texte du lien serie :

- `H\n` : heartbeat
- `P,<pin>,<valeur>\n` : sortie 0..4095
- `X\n` : blackout

Ce patch prepare le registre et le transport multi-cartes mais ne route encore aucune tranche vers le WiFi. Tant que le patch d'adressage par tranche n'est pas applique, les sorties physiques restent USB.
'@
  [System.IO.File]::WriteAllText($docPath,$doc,$Utf8NoBom)
}

$todo = [regex]::Replace(
  $todo,
  '(?m)^- \[ \] .*support multi-carte wifi ESP32\.\s*$',
  '- [ ] Valider le socle multi-carte ESP32 WiFi: esp32Boards.json, resolution des hotes et heartbeat UDP'
)
[System.IO.File]::WriteAllText($pdePath,$pde,$Utf8NoBom)
[System.IO.File]::WriteAllText($todoPath,$todo,$Utf8NoBom)

Write-Host "Applied: multi-ESP32 WiFi transport foundation." -ForegroundColor Green
Write-Host "No channel routing has changed yet."
Write-Host "Configure esp32Boards.json, then run the interface tests."
