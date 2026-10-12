/* DIMYX - recepteur ESP32-C3 pour ruban LED analogique 5 V.
 * Le module peut etre le point d'acces maitre ou un client Wi-Fi esclave.
 * H ; P,<GPIO>,<0..4095> ; X. Les lignes sont terminees par '\n'.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>

enum DeviceRole { ROLE_ACCESS_POINT, ROLE_STATION };

// Une seule carte doit rester en ROLE_ACCESS_POINT. Pour chaque autre carte,
// choisir ROLE_STATION et une adresse IP fixe differente.
const DeviceRole DEVICE_ROLE = ROLE_ACCESS_POINT;
const char *WIFI_SSID = "DIMYX-ESP32-C3";
const char *WIFI_PASSWORD = "dimyx-led-5v";
const uint16_t UDP_PORT = 4210;
const IPAddress AP_IP(192, 168, 4, 1);
const IPAddress AP_GATEWAY(192, 168, 4, 1);
const IPAddress AP_SUBNET(255, 255, 255, 0);
const IPAddress STATION_IP(192, 168, 4, 11); // changer pour chaque esclave
const uint8_t AP_MAX_CONNECTIONS = 8;

// A confirmer avec le pinout de la carte achetee.
const uint8_t PWM_PINS[] = {4, 5, 6};
const uint8_t PWM_CHANNEL_COUNT = sizeof(PWM_PINS) / sizeof(PWM_PINS[0]);
const uint32_t PWM_FREQUENCY = 1000;
const uint8_t PWM_RESOLUTION = 12;
const uint32_t HEARTBEAT_TIMEOUT_MS = 2000;

WiFiUDP udp;
char packetBuffer[96];
uint32_t lastHeartbeat = 0;
bool outputsEnabled = false;

void allOff() {
  for (uint8_t i = 0; i < PWM_CHANNEL_COUNT; ++i) ledcWrite(PWM_PINS[i], 0);
  outputsEnabled = false;
}

bool allowedPin(uint8_t pin) {
  for (uint8_t i = 0; i < PWM_CHANNEL_COUNT; ++i) {
    if (PWM_PINS[i] == pin) return true;
  }
  return false;
}

void reply(const char *message) {
  udp.beginPacket(udp.remoteIP(), udp.remotePort());
  udp.write(reinterpret_cast<const uint8_t *>(message), strlen(message));
  udp.endPacket();
}

void handleCommand(char *command) {
  while (*command == ' ' || *command == '\t') ++command;
  if (strcmp(command, "H") == 0) {
    lastHeartbeat = millis();
    reply("H\n");
    return;
  }
  if (strcmp(command, "X") == 0) {
    allOff();
    lastHeartbeat = millis();
    return;
  }
  int pin = -1;
  long value = -1;
  if (sscanf(command, "P,%d,%ld", &pin, &value) == 2 && pin >= 0 &&
      pin <= 255 && value >= 0 && value <= 4095 &&
      allowedPin(static_cast<uint8_t>(pin))) {
    ledcWrite(static_cast<uint8_t>(pin), static_cast<uint32_t>(value));
    outputsEnabled = true;
    lastHeartbeat = millis();
  }
}

void setup() {
  Serial.begin(115200);
  delay(100);
  for (uint8_t i = 0; i < PWM_CHANNEL_COUNT; ++i)
    ledcAttach(PWM_PINS[i], PWM_FREQUENCY, PWM_RESOLUTION);
  allOff();

  WiFi.setHostname(DEVICE_ROLE == ROLE_ACCESS_POINT ? "dimyx-master" : "dimyx-node");
  bool networkReady = false;
  if (DEVICE_ROLE == ROLE_ACCESS_POINT) {
    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(AP_IP, AP_GATEWAY, AP_SUBNET);
    networkReady = WiFi.softAP(WIFI_SSID, WIFI_PASSWORD, 6, false, AP_MAX_CONNECTIONS);
  } else {
    WiFi.mode(WIFI_STA);
    WiFi.config(STATION_IP, AP_GATEWAY, AP_SUBNET);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    uint32_t startedAt = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 15000) {
      delay(250);
    }
    networkReady = WiFi.status() == WL_CONNECTED;
  }
  if (!networkReady) {
    Serial.println("DIMYX_WIFI_ERROR");
    allOff();
    return;
  }
  udp.begin(UDP_PORT);
  lastHeartbeat = millis();
  Serial.println("THEATRE_CONSOLE");
  Serial.print("BOARD_ID:");
  Serial.println(DEVICE_ROLE == ROLE_ACCESS_POINT ? "ESP32-C3-MASTER" : "ESP32-C3-NODE");
  Serial.print("ROLE:");
  Serial.println(DEVICE_ROLE == ROLE_ACCESS_POINT ? "AP" : "STA");
  Serial.print("IP:");
  Serial.println(DEVICE_ROLE == ROLE_ACCESS_POINT ? WiFi.softAPIP() : WiFi.localIP());
  Serial.print("UDP_PORT:");
  Serial.println(UDP_PORT);
}

void loop() {
  int packetSize = udp.parsePacket();
  if (packetSize > 0) {
    int length = udp.read(packetBuffer, sizeof(packetBuffer) - 1);
    if (length > 0) {
      packetBuffer[length] = '\0';
      char *line = strtok(packetBuffer, "\r\n");
      if (line != nullptr) handleCommand(line);
    }
  }
  if (outputsEnabled && millis() - lastHeartbeat > HEARTBEAT_TIMEOUT_MS) allOff();
}
