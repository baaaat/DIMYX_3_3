/* DIMYX - recepteur ESP32-C3 pour carte fille Wi-Fi. */
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>

const char *WIFI_SSID = "DIMYX-ESP32-C3";
const char *WIFI_PASSWORD = "dimyx-led-5v";
const uint16_t UDP_PORT = 4210;
const IPAddress STATION_IP(192, 168, 4, 11);
const IPAddress STATION_GATEWAY(192, 168, 4, 1);
const IPAddress STATION_SUBNET(255, 255, 255, 0);
const uint8_t PWM_PINS[] = {4, 5, 6};
const uint8_t PWM_CHANNEL_COUNT = sizeof(PWM_PINS) / sizeof(PWM_PINS[0]);
const uint32_t PWM_FREQUENCY = 1000;
const uint8_t PWM_RESOLUTION = 12;
const uint32_t HEARTBEAT_TIMEOUT_MS = 2000;

WiFiUDP udp;
char packetBuffer[512];
uint32_t lastHeartbeat = 0;
bool outputsEnabled = false;

String deviceBoardId() {
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  return "ESP32-C3-" + mac;
}

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

void replyDiscovery() {
  String message = "DIMYX_DISCOVERY;BOARD_ID:";
  message += deviceBoardId();
  message += ";IP:";
  message += WiFi.localIP().toString();
  message += ";UDP_PORT:";
  message += String(UDP_PORT);
  message += ";ROLE:STA\n";
  reply(message.c_str());
}

void handleCommand(char *command) {
  while (*command == ' ' || *command == '\t') ++command;
  if (strcmp(command, "H") == 0) {
    lastHeartbeat = millis();
    reply("H\n");
    return;
  }
  if (strcmp(command, "DISCOVER") == 0) {
    replyDiscovery();
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

  WiFi.setHostname("dimyx-fille");
  WiFi.mode(WIFI_STA);
  WiFi.config(STATION_IP, STATION_GATEWAY, STATION_SUBNET);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  uint32_t startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 15000) delay(250);
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("DIMYX_WIFI_ERROR");
    allOff();
    return;
  }
  udp.begin(UDP_PORT);
  lastHeartbeat = millis();
  Serial.println("THEATRE_CONSOLE");
  Serial.print("BOARD_ID:");
  Serial.println(deviceBoardId());
  Serial.println("ROLE:STA");
  Serial.print("IP:");
  Serial.println(WiFi.localIP());
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
      while (line != nullptr) {
        handleCommand(line);
        line = strtok(nullptr, "\r\n");
      }
    }
  }
  if (outputsEnabled && millis() - lastHeartbeat > HEARTBEAT_TIMEOUT_MS) allOff();
}
