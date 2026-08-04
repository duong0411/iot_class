/*
 * ╔══════════════════════════════════════════════════════════════╗
 * ║         SMARTHOME ESP8266 — TỐI ƯU HÓA BỘ NHỚ (40KB RAM)    ║
 * ╠══════════════════════════════════════════════════════════════╣
 * ║  ✅ WiFiManager Web Portal tĩnh tối ưu bộ nhớ               ║
 * ║  ✅ Lưu WiFi vào EEPROM thay cho Preferences của ESP32      ║
 * ║  ✅ PubSubClient (MQTT TCP 1883) + WebSocketMCP (WSS)       ║
 * ║  ✅ Quản lý Cảm biến (Gas, Lửa, DHT) và Relay, Servo        ║
 * ╚══════════════════════════════════════════════════════════════╝
 * ⚠️ CHÚ Ý QUAN TRỌNG VỀ PHẦN CỨNG & BỘ NHỚ:
 * - Chân D5 (GPIO14) được dùng cho cảm biến Lửa (an toàn hơn D3).
 * - Code MCP XiaoZhi đã được chuyển lên Node.js Backend. ESP8266 chỉ còn chạy MQTT.
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <DNSServer.h>
#include <EEPROM.h>
#include <WebSocketsClient.h>
#include <MQTTPubSubClient.h>
#include "DHT.h"
#include <Servo.h>
#include <ArduinoJson.h>

// ─────────────────────────────────────────────────────────────
//  SƠ ĐỒ CHÂN (PINOUT ESP8266)
// ─────────────────────────────────────────────────────────────
#define PIN_GAS     A0  // MQ2 Analog
#define PIN_FAN     5   // D1 (GPIO5)
#define PIN_LED     4   // D2 (GPIO4)
#define PIN_FIRE    14  // D5 (GPIO14) - An toàn khi boot
#define PIN_DHT     2   // D4 (GPIO2)
#define PIN_DOOR    13  // D7 (GPIO13)
#define PIN_DRYER   15  // D8 (GPIO15)
#define PIN_BUZZER  12  // D6 (GPIO12) - Còi báo động
#define PIN_RAIN    16  // D0 (GPIO16) - Cảm biến mưa

#define DHTTYPE     DHT11
#define RELAY_ON    HIGH
#define RELAY_OFF   LOW
#define GAS_THRESHOLD 500

// ─────────────────────────────────────────────────────────────
//  PORTAL CẤU HÌNH
// ─────────────────────────────────────────────────────────────
#define AP_SSID     "SmartHome"
#define AP_PASSWORD ""
IPAddress apIP(192, 168, 4, 1);
const byte DNS_PORT = 53;

// ─────────────────────────────────────────────────────────────
//  MQTT (Dùng WSS Port 443 đi qua Cloudflare)
// ─────────────────────────────────────────────────────────────
#define MQTT_HOST   "mqtt.aiotlearninghub.com"
#define MQTT_PORT   443
#define CHIP_ID     "123"

#define DEV_TEMP    "123_temp_livingroom"
#define DEV_HUMI    "123_humi_living_room"
#define DEV_LED     "123_led1"
#define DEV_FAN     "123_fan_livingroom"
#define DEV_DOOR    "123_door_livingroom1"
#define DEV_DRYER   "123_dryer_livingroom"
#define DEV_GAS     "123_gas_livingroom"
#define DEV_FIRE    "123_fire_livingroom"
#define DEV_RAIN    "123_rain_livingroom"

// ─────────────────────────────────────────────────────────────
//  MULTI-WIFI (EEPROM)
// ─────────────────────────────────────────────────────────────
#define EEPROM_SIZE 512
#define MAX_WIFI    5

struct WifiEntry {
  char ssid[32];
  char pass[32];
};
WifiEntry wifiList[MAX_WIFI];
int wifiCount = 0;

// ─────────────────────────────────────────────────────────────
//  INTERVAL
// ─────────────────────────────────────────────────────────────
#define TELEMETRY_MS     5000
#define SENSOR_FAST_MS   500
#define HEARTBEAT_MS    30000
#define RECONNECT_MS    10000

// ─────────────────────────────────────────────────────────────
//  OBJECTS
// ─────────────────────────────────────────────────────────────
DHT dht(PIN_DHT, DHTTYPE);
Servo servoDoor;
Servo servoDryer;
ESP8266WebServer webServer(80);
DNSServer dnsServer;
WebSocketsClient wsClient;
MQTTPubSubClient mqttClient;

// ─────────────────────────────────────────────────────────────
//  TRẠNG THÁI
// ─────────────────────────────────────────────────────────────
bool portalActive = false;
int doorAngle = 0;
int dryerAngle = 0;
String ledState = "OFF";
String fanState = "OFF";

bool isGasAlert = false;
bool isFireAlert = false;
bool isRainAlert = false;

unsigned long lastTelemetry = 0;
unsigned long lastFastRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastReconnect = 0;

// ─────────────────────────────────────────────────────────────
//  HELPER
// ─────────────────────────────────────────────────────────────
String relayRead(uint8_t pin) {
  return (digitalRead(pin) == RELAY_ON) ? "ON" : "OFF";
}

void adjustDoorAngle(int angle) {
  doorAngle = constrain(angle, 0, 180);
  servoDoor.write(doorAngle);
}

void adjustDryerAngle(int angle) {
  dryerAngle = constrain(angle, 0, 180);
  servoDryer.write(dryerAngle);
}

// ─────────────────────────────────────────────────────────────
//  EEPROM WIFI
// ─────────────────────────────────────────────────────────────
void saveWifiList() {
  EEPROM.begin(EEPROM_SIZE);
  EEPROM.put(0, wifiCount);
  int addr = sizeof(wifiCount);
  for (int i = 0; i < MAX_WIFI; i++) {
    EEPROM.put(addr, wifiList[i]);
    addr += sizeof(WifiEntry);
  }
  EEPROM.commit();
  EEPROM.end();
}

void loadWifiList() {
  EEPROM.begin(EEPROM_SIZE);
  EEPROM.get(0, wifiCount);
  if (wifiCount < 0 || wifiCount > MAX_WIFI) wifiCount = 0;
  
  int addr = sizeof(wifiCount);
  for (int i = 0; i < MAX_WIFI; i++) {
    EEPROM.get(addr, wifiList[i]);
    addr += sizeof(WifiEntry);
  }
  EEPROM.end();
}

void addOrUpdateWifi(String ssid, String pass) {
  for (int i = 0; i < wifiCount; i++) {
    if (String(wifiList[i].ssid) == ssid) {
      pass.toCharArray(wifiList[i].pass, 32);
      saveWifiList();
      return;
    }
  }
  if (wifiCount >= MAX_WIFI) {
    for (int i = 0; i < MAX_WIFI - 1; i++) wifiList[i] = wifiList[i+1];
    wifiCount = MAX_WIFI - 1;
  }
  ssid.toCharArray(wifiList[wifiCount].ssid, 32);
  pass.toCharArray(wifiList[wifiCount].pass, 32);
  wifiCount++;
  saveWifiList();
}

bool connectBestWifi() {
  Serial.println("\n🔍 Quét mạng WiFi đã lưu...");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  if (wifiCount == 0) {
    Serial.println("❌ Chưa có WiFi nào được lưu!");
    return false;
  }

  int n = WiFi.scanNetworks();
  int bestIdx = -1;
  int bestRSSI = -999;

  if (n > 0) {
    for (int i = 0; i < n; i++) {
      String scannedSSID = WiFi.SSID(i);
      int rssi = WiFi.RSSI(i);
      for (int w = 0; w < wifiCount; w++) {
        if (String(wifiList[w].ssid) == scannedSSID && rssi > bestRSSI) {
          bestRSSI = rssi;
          bestIdx = w;
        }
      }
    }
    WiFi.scanDelete();
  }

  if (bestIdx < 0) {
    Serial.println("⚠️ Không thấy qua scan, thử kết nối WiFi được lưu gần nhất...");
    bestIdx = wifiCount - 1; // Fallback: thử mạng mới nhất
  } else {
    Serial.printf("📶 Tìm thấy: %s (%ddBm)\n", wifiList[bestIdx].ssid, bestRSSI);
  }

  Serial.printf("🚀 Đang kết nối: %s\n", wifiList[bestIdx].ssid);
  WiFi.begin(wifiList[bestIdx].ssid, wifiList[bestIdx].pass);
  
  for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi OK! IP: " + WiFi.localIP().toString());
    return true;
  } else {
    Serial.println("\n❌ Kết nối WiFi thất bại!");
    return false;
  }
}

// ─────────────────────────────────────────────────────────────
//  MQTT
// ─────────────────────────────────────────────────────────────
void mqttPub(const char* device, const String& payload) {
  if (!mqttClient.isConnected()) return;
  String topic = "tele/" + String(device) + "/status";
  mqttClient.publish(topic, payload, false, 0);
}

void pubOnline()    { mqttPub(CHIP_ID, "online"); }
void pubTemp(float t){ mqttPub(DEV_TEMP, "{\"value\":" + String(t,1) + "}"); }
void pubHumi(float h){ mqttPub(DEV_HUMI, "{\"value\":" + String(h,1) + "}"); }
void pubLed()  { ledState = relayRead(PIN_LED); mqttPub(DEV_LED, "{\"value\":\""+ledState+"\"}"); }
void pubFan()  { fanState = relayRead(PIN_FAN); mqttPub(DEV_FAN, "{\"value\":\""+fanState+"\"}"); }
void pubDoor() { mqttPub(DEV_DOOR, "{\"value\":" + String(doorAngle) + "}"); }
void pubDryer() { mqttPub(DEV_DRYER, "{\"value\":" + String(dryerAngle) + "}"); }
void pubGas() { mqttPub(DEV_GAS, isGasAlert ? "{\"value\":\"ON\"}" : "{\"value\":\"OFF\"}"); }
void pubFire() { mqttPub(DEV_FIRE, isFireAlert ? "{\"value\":\"ON\"}" : "{\"value\":\"OFF\"}"); }
void pubRain() { mqttPub(DEV_RAIN, isRainAlert ? "{\"value\":\"ON\"}" : "{\"value\":\"OFF\"}"); }

void mqttCallback(const String& topicStr, const String& payload, const size_t size) {
  String topic = topicStr;
  String cmd = payload;
  cmd.trim();

  if (topic.indexOf(DEV_LED) >= 0) {
    digitalWrite(PIN_LED, cmd == "ON" ? RELAY_ON : RELAY_OFF);
    pubLed();
  }
  else if (topic.indexOf(DEV_FAN) >= 0) {
    digitalWrite(PIN_FAN, cmd == "ON" ? RELAY_ON : RELAY_OFF);
    pubFan();
  }
  else if (topic.indexOf(DEV_DOOR) >= 0) {
    int a = (cmd == "ON") ? 90 : (cmd == "OFF" ? 0 : cmd.toInt());
    adjustDoorAngle(a);
    pubDoor();
  }
  else if (topic.indexOf(DEV_DRYER) >= 0) {
    int a = (cmd == "ON") ? 90 : (cmd == "OFF" ? 0 : cmd.toInt());
    adjustDryerAngle(a);
    pubDryer();
  }
}

void reconnectMQTT() {
  if (!mqttClient.isConnected()) {
    Serial.print("📡 Đang kết nối MQTT WSS (Port " + String(MQTT_PORT) + ")...");
    String clientId = "ESP8266-" + String(ESP.getChipId(), HEX);
    String lwtTopic = "tele/" + String(CHIP_ID) + "/status";
    
    mqttClient.setWill(lwtTopic, "offline", true, 1);
    
    if (mqttClient.connect(clientId, "", "")) {
      Serial.println("Thành công!");
      pubOnline(); wsClient.loop(); delay(50);
      
      mqttClient.subscribe("cmnd/" + String(DEV_LED) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_LED) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(50);
      
      mqttClient.subscribe("cmnd/" + String(DEV_FAN) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_FAN) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(50);
      
      mqttClient.subscribe("cmnd/" + String(DEV_DOOR) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_DOOR) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(50);
      
      mqttClient.subscribe("cmnd/" + String(DEV_DRYER) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_DRYER) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(50);

      pubLed(); wsClient.loop(); delay(50);
      pubFan(); wsClient.loop(); delay(50);
      pubDoor(); wsClient.loop(); delay(50);
      pubDryer(); wsClient.loop();
    } else {
      Serial.println("Lỗi hoặc Đang thiết lập WebSockets, thử lại sau...");
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  PORTAL HTML
// ─────────────────────────────────────────────────────────────
const char PORTAL_HTML[] PROGMEM = R"rawhtml(
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SmartHome Setup</title>
<style>body{font-family:sans-serif;background:#0a0e1a;color:#e2e8f0;display:flex;justify-content:center;padding:20px}
.c{max-width:400px;width:100%;} input{width:100%;padding:10px;margin-bottom:10px;border-radius:5px;border:none} button{padding:10px;width:100%;background:#0ea5e9;color:#fff;border:none;border-radius:5px;cursor:pointer;font-weight:bold}
#st{margin-top:15px;text-align:center;font-weight:bold;padding:10px;border-radius:5px;display:none;}</style>
</head><body><div class="c"><h2>⚙️ SmartHome WiFi</h2>
<button onclick="scan()" style="margin-bottom:10px;background:#6366f1;">🔍 Quét mạng xung quanh</button><div id="w" style="margin-bottom:10px;line-height:1.8;cursor:pointer;"></div>
<input id="s" placeholder="Tên WiFi"><input type="password" id="p" placeholder="Mật khẩu">
<button onclick="conn()">🚀 Kết nối</button><div id="st"></div></div>
<script>
function scan() {
  document.getElementById('w').innerHTML = 'Đang quét...';
  fetch('/scan')
    .then(r => r.json())
    .then(l => {
      document.getElementById('w').innerHTML = l.map(n => 
        `<div style="padding:5px; background:#1e293b; margin-top:5px; border-radius:5px;" onclick="document.getElementById('s').value='${n.ssid}'">📶 ${n.ssid} (${n.rssi}dBm)</div>`
      ).join('');
    })
    .catch(e => {
      document.getElementById('w').innerHTML = '❌ Lỗi quét mạng';
    });
}
function conn() {
  const s = document.getElementById('s').value;
  const p = document.getElementById('p').value;
  if (!s) { alert("Vui lòng nhập tên WiFi!"); return; }
  
  const st = document.getElementById('st');
  st.style.display = 'block';
  st.innerHTML = '⏳ Đang kết nối thử... Vui lòng đợi đến 15s!';
  st.style.background = '#334155';
  st.style.color = '#fff';
  
  fetch('/connect', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'ssid=' + encodeURIComponent(s) + '&pass=' + encodeURIComponent(p)
  })
  .then(r => r.json())
  .then(d => {
    if (d.ok) {
      st.style.background = '#22c55e';
      st.innerHTML = '✅ KẾT NỐI THÀNH CÔNG!<br>Mạch đang tự khởi động lại...';
      alert("Kết nối WiFi thành công! Mạch đang khởi động lại.");
    } else {
      st.style.background = '#ef4444';
      st.innerHTML = '❌ LỖI: ' + (d.message || 'Kết nối thất bại');
    }
  })
  .catch(e => {
    st.style.background = '#ef4444';
    st.innerHTML = '❌ LỖI MẠNG!<br>Vui lòng thử lại...';
  });
}
</script></body></html>
)rawhtml";

void handleNotFound() {
  webServer.sendHeader("Location", "http://192.168.4.1/", true);
  webServer.send(302, "text/plain", "");
}

void handleRoot() { webServer.send_P(200, "text/html", PORTAL_HTML); }
void handleScan() {
  int n = WiFi.scanNetworks();
  String json = "[";
  for (int i = 0; i < n; i++) {
    if (i) json += ",";
    json += "{\"ssid\":\""+WiFi.SSID(i)+"\",\"rssi\":"+String(WiFi.RSSI(i))+"}";
  }
  json += "]"; WiFi.scanDelete(); webServer.send(200, "application/json", json);
}
void handleConnect() {
  String ssid = webServer.arg("ssid"); String pass = webServer.arg("pass");
  if (ssid.length() > 0) {
    Serial.printf("Thử kết nối đến WiFi: %s\n", ssid.c_str());
    WiFi.begin(ssid.c_str(), pass.c_str());
    for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
      delay(500);
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("Kết nối WiFi thử nghiệm thành công!");
      addOrUpdateWifi(ssid, pass);
      webServer.send(200, "application/json", "{\"ok\":true}");
      delay(1000); 
      ESP.restart(); // Khởi động lại để kết nối thay vì connect ngay
    } else {
      Serial.println("Kết nối WiFi thử nghiệm thất bại!");
      WiFi.disconnect();
      webServer.send(200, "application/json", "{\"ok\":false, \"message\":\"Sai mật khẩu hoặc WiFi quá yếu.\"}");
    }
  } else {
    webServer.send(200, "application/json", "{\"ok\":false, \"message\":\"Chưa nhập tên WiFi!\"}");
  }
}

void startPortal() {
  portalActive = true;
  Serial.println("\n🌐 Khởi tạo WiFi Access Point...");
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  dnsServer.start(DNS_PORT, "*", apIP);
  webServer.on("/", HTTP_GET, handleRoot);
  webServer.on("/scan", HTTP_GET, handleScan);
  webServer.on("/connect", HTTP_POST, handleConnect);
  webServer.onNotFound(handleNotFound);
  webServer.begin();
  Serial.println("✅ Portal đã sẵn sàng!");
  Serial.println("👉 Vui lòng kết nối điện thoại vào WiFi: SmartHome");
  Serial.println("👉 Sau đó truy cập trang: http://192.168.4.1");
}

// ─────────────────────────────────────────────────────────────
//  DOUBLE RESET DETECTOR
// ─────────────────────────────────────────────────────────────
#define DOUBLE_RESET_MAGIC 0x12345678
#define RTC_OFFSET 0

uint32_t rtcData = 0;
bool isDoubleReset = false;

void checkDoubleReset() {
  ESP.rtcUserMemoryRead(RTC_OFFSET, (uint32_t*) &rtcData, sizeof(rtcData));
  if (rtcData == DOUBLE_RESET_MAGIC) {
    isDoubleReset = true;
    Serial.println("\n⚠️ DOUBLE RESET DETECTED! Xóa toàn bộ cấu hình WiFi...");
    rtcData = 0;
    ESP.rtcUserMemoryWrite(RTC_OFFSET, (uint32_t*) &rtcData, sizeof(rtcData));
    
    // Xóa danh sách WiFi trong EEPROM
    wifiCount = 0;
    saveWifiList();
    Serial.println("✅ Đã xóa WiFi. Khởi động chế độ cài đặt mạng (Portal)...");
  } else {
    isDoubleReset = false;
    rtcData = DOUBLE_RESET_MAGIC;
    ESP.rtcUserMemoryWrite(RTC_OFFSET, (uint32_t*) &rtcData, sizeof(rtcData));
  }
}

void clearDoubleResetFlag() {
  if (rtcData == DOUBLE_RESET_MAGIC) {
    rtcData = 0;
    ESP.rtcUserMemoryWrite(RTC_OFFSET, (uint32_t*) &rtcData, sizeof(rtcData));
  }
}

// ─────────────────────────────────────────────────────────────
//  SETUP
// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n╔════════════════════════════════════╗");
  Serial.println("║  🚀 SmartHome ESP8266 Khởi động  ║");
  Serial.println("╚════════════════════════════════════╝");
  
  pinMode(PIN_LED, OUTPUT); digitalWrite(PIN_LED, RELAY_OFF);
  pinMode(PIN_FAN, OUTPUT); digitalWrite(PIN_FAN, RELAY_OFF);
  pinMode(PIN_BUZZER, OUTPUT); digitalWrite(PIN_BUZZER, LOW);
  pinMode(PIN_FIRE, INPUT_PULLUP);
  pinMode(PIN_RAIN, INPUT_PULLUP);
  dht.begin();
  servoDoor.attach(PIN_DOOR);
  servoDoor.write(0);
  servoDryer.attach(PIN_DRYER);
  servoDryer.write(0);

  wsClient.beginSSL(MQTT_HOST, MQTT_PORT, "/mqtt");
  wsClient.setExtraHeaders("Sec-WebSocket-Protocol: mqtt");
  // Thư viện WebSocketsClient mặc định không kiểm tra SSL nếu không truyền fingerprint, nên không cần hàm setInsecure()
  
  mqttClient.begin(wsClient);

  loadWifiList();
  
  checkDoubleReset();
  
  if (isDoubleReset) {
    startPortal();
  } else {
    if (!(wifiCount > 0 && connectBestWifi())) {
      startPortal();
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  LOOP
// ─────────────────────────────────────────────────────────────
int wifiRetries = 0;

void loop() {
  // Xóa cờ Double Reset nếu mạch đã chạy ổn định quá 3 giây (3000ms)
  if (millis() > 3000 && rtcData == DOUBLE_RESET_MAGIC) {
    clearDoubleResetFlag();
  }

  if (portalActive) {
    dnsServer.processNextRequest();
    webServer.handleClient();
    return;
  }

  unsigned long now = millis();

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastReconnect >= RECONNECT_MS) {
      lastReconnect = now;
      if (connectBestWifi()) {
        wifiRetries = 0;
      } else {
        wifiRetries++;
        if (wifiRetries >= 3) {
          Serial.println("⚠️ Không thể kết nối lại mạng! Chuyển sang chế độ Portal cấu hình...");
          startPortal();
          wifiRetries = 0;
        }
      }
    }
    return;
  } else {
    wifiRetries = 0;
  }

  wsClient.loop();
  mqttClient.update();

  if (!mqttClient.isConnected()) {
    if (now - lastReconnect >= 5000) {
      lastReconnect = now;
      reconnectMQTT();
    }
  }

  if (now - lastFastRead >= SENSOR_FAST_MS) {
    lastFastRead = now;
    int gasVal = analogRead(PIN_GAS);
    bool currentGasAlert = (gasVal > GAS_THRESHOLD);
    if (currentGasAlert != isGasAlert) {
      isGasAlert = currentGasAlert;
      pubGas();
    }

    bool currentFireAlert = (digitalRead(PIN_FIRE) == LOW);
    if (currentFireAlert != isFireAlert) {
      isFireAlert = currentFireAlert;
      pubFire();
    }

    bool currentRainAlert = (digitalRead(PIN_RAIN) == LOW);
    if (currentRainAlert != isRainAlert) {
      isRainAlert = currentRainAlert;
      pubRain();
      if (isRainAlert) {
        adjustDryerAngle(0); // Tự động đóng dàn phơi khi mưa
        pubDryer();
      }
    }

    if (isGasAlert || isFireAlert) {
      digitalWrite(PIN_BUZZER, HIGH);
    } else {
      digitalWrite(PIN_BUZZER, LOW);
    }
  }

  // Heartbeat
  if (now - lastHeartbeat >= HEARTBEAT_MS) {
    lastHeartbeat = now;
    pubOnline();
  }

  // Telemetry 5s
  if (now - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = now;
    float h = dht.readHumidity();
    float t = dht.readTemperature();
    if (!isnan(t) && !isnan(h)) {
      Serial.printf("🌡️ Nhiệt độ: %.1f°C | 💧 Độ ẩm: %.1f%%\n", t, h);
      pubTemp(t); pubHumi(h);
    } else {
      Serial.println("⚠️ Lỗi: Không đọc được cảm biến DHT!");
    }
  }
}
