/*
 * ╔════════════════════════════════════════════════════════════════════════════╗
 * ║        SMARTHOME ESP32 — CODE LỚP HỌC THÔNG MINH (SMART CLASSROOM)          ║
 * ╠════════════════════════════════════════════════════════════════════════════╣
 * ║  ✅ Màn hình OLED 0.96" (I2C): SDA (D17), SCK/SCL (D21)                      ║
 * ║  ✅ Đọc thẻ RFID-RC522 (SPI): SS (D5), SCK (D18), MISO (D19), MOSI (D23),    ║
 * ║     RST (GPIO22)                                                           ║
 * ║  ✅ Cảm biến Nhiệt độ & Độ ẩm DHT11: (D2)                                  ║
 * ║  ✅ Servo điều khiển cửa lớp: (D13)                                        ║
 * ║  ✅ 2 Kênh Relay: Quạt (D12), Đèn (D14)                                    ║
 * ║  ✅ Cảm biến Quang (LDR): (D27) — Báo Ánh sáng Tốt / Trung bình / Yếu       ║
 * ║  ✅ Quạt tự động BẬT khi Nhiệt độ >= 27°C                                  ║
 * ║  ✅ Quẹt thẻ RFID mở cửa + Báo mã thẻ lên OLED & Cloud                     ║
 * ║  ✅ WiFi Portal cấu hình mạng tĩnh qua Web Captive Portal                  ║
 * ║  ✅ MQTT WSS Telemetry & Điều khiển từ xa qua Backend                      ║
 * ╚════════════════════════════════════════════════════════════════════════════╝
 */

#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <WebSocketsClient.h>
#include <MQTTPubSubClient.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <SPI.h>
#include <MFRC522.h>
#include "DHT.h"
#include <ESP32Servo.h>
#include <ArduinoJson.h>

// ─────────────────────────────────────────────────────────────
//  SƠ ĐỒ CHÂN PHẦN CỨNG (PINOUT ESP32)
// ─────────────────────────────────────────────────────────────
// 1. OLED 0.96" I2C
#define PIN_OLED_SDA    17  // D17
#define PIN_OLED_SCL    21  // D21
#define SCREEN_WIDTH    128
#define SCREEN_HEIGHT   64
#define OLED_RESET      -1
#define SCREEN_ADDRESS  0x3C

// 2. RFID RC522 SPI
#define PIN_RFID_SS     5   // D5 (SS / SDA)
#define PIN_RFID_RST    22  // GPIO22 (RST)
#define PIN_SPI_SCK     18  // D18
#define PIN_SPI_MISO    19  // D19
#define PIN_SPI_MOSI    23  // D23

// 3. CẢM BIẾN & THIẾT BỊ
#define PIN_DHT         16  // D16 (DHT11 - Chuyển sang D16 để không bị kẹt nạp code ở GPIO2)
#define PIN_SERVO       13  // D13 (Servo Mở cửa / cửa sổ)
#define PIN_FAN         4   // D4 (Relay Quạt - Dùng GPIO4 an toàn khi nạp code)
#define PIN_LED         14  // D14 (Relay Đèn)
#define PIN_LDR         27  // D27 (Đọc chân DO cảm biến quang: LOW = SÁNG/TỐT, HIGH = TỐI/YẾU)

#define DHTTYPE         DHT11
#define RELAY_ON        HIGH
#define RELAY_OFF       LOW

// Ngưỡng nhiệt độ tự động bật quạt
#define TEMP_AUTO_FAN   27.0f

// Ngưỡng đọc cảm biến quang LDR (ESP32 ADC 0-4095)
// Tùy theo loại module LDR (có thể điều chỉnh trong code hoặc biến cấu hình)
#define LDR_GOOD_VAL    2500  // Trở lên là Tốt
#define LDR_MED_VAL     1200  // 1200 -> 2500 là Trung bình, dưới 1200 là Yếu

// ─────────────────────────────────────────────────────────────
//  PORTAL CẤU HÌNH WIFI & PREFERENCES
// ─────────────────────────────────────────────────────────────
#define AP_SSID         "SmartClassroom_ESP32"
#define AP_PASSWORD     ""
IPAddress apIP(192, 168, 4, 1);
const byte DNS_PORT = 53;

#define MAX_WIFI        5
struct WifiEntry {
  char ssid[32];
  char pass[32];
};
WifiEntry wifiList[MAX_WIFI];
int wifiCount = 0;

// ─────────────────────────────────────────────────────────────
//  MQTT CẤU HÌNH
// ─────────────────────────────────────────────────────────────
// MQTT Broker mới — Mosquitto local, expose qua Cloudflare Tunnel
// ESP32 gửi WSS (beginSSL) → Cloudflare lo TLS → forward WS → Mosquitto :9001
#define MQTT_HOST       "mqtt.duynguyen.io.vn"
#define MQTT_PORT       443
#define CHIP_ID         "CLASSROOM_01"

#define DEV_TEMP        "classroom_temp"
#define DEV_HUMI        "classroom_humi"
#define DEV_LIGHT       "classroom_light"
#define DEV_LED         "classroom_led"
#define DEV_FAN         "classroom_fan"
#define DEV_DOOR        "classroom_door"
#define DEV_RFID        "classroom_rfid"
#define DEV_MODE        "classroom_mode"

// ─────────────────────────────────────────────────────────────
//  INTERVAL THỜI GIAN (REALTIME)
// ─────────────────────────────────────────────────────────────
#define TELEMETRY_MS     3000   // Cập nhật telemetry cảm biến & trạng thái mỗi 3s
#define SENSOR_FAST_MS   300    // Đọc LDR & RFID siêu nhanh 300ms
#define HEARTBEAT_MS     5000   // Báo online heartbeat mỗi 5s
#define RECONNECT_MS     5000   // Thử kết nối lại mạng mỗi 5s

// ─────────────────────────────────────────────────────────────
//  ĐỐI TƯỢNG (OBJECTS)
// ─────────────────────────────────────────────────────────────
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
MFRC522 rfc522(PIN_RFID_SS, PIN_RFID_RST);
DHT dht(PIN_DHT, DHTTYPE);
Servo servoDoor;

WebServer webServer(80);
DNSServer dnsServer;
WebSocketsClient wsClient;
MQTTPubSubClient mqttClient;
Preferences preferences;

// ─────────────────────────────────────────────────────────────
//  TRẠNG THÁI TOÀN CỤC
// ─────────────────────────────────────────────────────────────
bool portalActive = false;
int doorAngle = 0;
String ledState = "OFF";
String fanState = "OFF";
String systemMode = "AUTO"; // AUTO: Tự động theo cảm biến | MANUAL: Điều khiển thủ công qua App
String lightLevelStr = "Dang doc...";
String lastScannedRFID = "";
bool autoFanTriggered = false;
bool autoLightTriggered = false;
unsigned long rfidDisplayTimer = 0;

float currentTemp = 0.0f;
float currentHumi = 0.0f;
int rawLDR = 0;

unsigned long lastTelemetry = 0;
unsigned long lastFastRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastReconnect = 0;

// RTC Memory cho Double Reset Detector trên ESP32
RTC_DATA_ATTR static uint32_t rtcMagicNumber = 0;
#define DOUBLE_RESET_MAGIC 0xABCD1234

// ─────────────────────────────────────────────────────────────
//  HÀM PHỤ TRỢ (HELPERS)
// ─────────────────────────────────────────────────────────────
String relayRead(uint8_t pin) {
  return (digitalRead(pin) == RELAY_ON) ? "ON" : "OFF";
}

void adjustDoorAngle(int angle) {
  doorAngle = constrain(angle, 0, 180);
  servoDoor.write(doorAngle);
}

// Đánh giá mức độ ánh sáng từ chân DO (LOW = Có ánh sáng/Tốt | HIGH = Trời tối/Yếu)
String getLightStatus(int digitalVal) {
  return (digitalVal == LOW) ? "Tot" : "Yeu";
}

// ─────────────────────────────────────────────────────────────
//  HÀM HIỂN THỊ OLED
// ─────────────────────────────────────────────────────────────
void updateOLEDDisplay(float temp, float humi, String lightStatus) {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);

  // 1. TIÊU ĐỀ
  display.setCursor(2, 2);
  display.println(F("= LOP HOC THONG MINH ="));
  display.drawFastHLine(0, 13, 128, SSD1306_WHITE);

  // 2. NHIỆT ĐỘ (Y: 18)
  display.setCursor(0, 19);
  if (!isnan(temp)) {
    display.printf("Nhiet do : %.1f C\n", temp);
  } else {
    display.println(F("Nhiet do : -- C"));
  }

  // 3. ĐỘ ẨM (Y: 33)
  display.setCursor(0, 33);
  if (!isnan(humi)) {
    display.printf("Do am    : %.1f %%\n", humi);
  } else {
    display.println(F("Do am    : -- %"));
  }

  // 4. ÁNH SÁNG (Y: 48)
  display.setCursor(0, 48);
  display.printf("Anh sang : %s\n", lightStatus.c_str());

  display.display();
}

// ─────────────────────────────────────────────────────────────
//  PREFERENCES (LƯU WIFI TRÊN ESP32)
// ─────────────────────────────────────────────────────────────
void saveWifiList() {
  preferences.begin("wifistore", false);
  preferences.putInt("count", wifiCount);
  for (int i = 0; i < wifiCount; i++) {
    String sKey = "s" + String(i);
    String pKey = "p" + String(i);
    preferences.putString(sKey.c_str(), wifiList[i].ssid);
    preferences.putString(pKey.c_str(), wifiList[i].pass);
  }
  preferences.end();
}

void loadWifiList() {
  preferences.begin("wifistore", true);
  wifiCount = preferences.getInt("count", 0);
  if (wifiCount < 0 || wifiCount > MAX_WIFI) wifiCount = 0;

  for (int i = 0; i < wifiCount; i++) {
    String sKey = "s" + String(i);
    String pKey = "p" + String(i);
    String s = preferences.getString(sKey.c_str(), "");
    String p = preferences.getString(pKey.c_str(), "");
    s.toCharArray(wifiList[i].ssid, 32);
    p.toCharArray(wifiList[i].pass, 32);
  }
  preferences.end();
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
  Serial.println("\n🔍 [ESP32] Quét các mạng WiFi đã lưu...");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  if (wifiCount == 0) {
    Serial.println("❌ Chưa có thông tin WiFi nào trong bộ nhớ!");
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
    Serial.println("⚠️ Không tìm thấy qua scan, thử kết nối WiFi lưu gần nhất...");
    bestIdx = wifiCount - 1;
  } else {
    Serial.printf("📶 Đã phát hiện: %s (%ddBm)\n", wifiList[bestIdx].ssid, bestRSSI);
  }

  Serial.printf("🚀 Đang kết nối: %s\n", wifiList[bestIdx].ssid);
  WiFi.begin(wifiList[bestIdx].ssid, wifiList[bestIdx].pass);

  for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi OK! Địa chỉ IP: " + WiFi.localIP().toString());
    return true;
  } else {
    Serial.println("\n❌ Kết nối WiFi thất bại!");
    return false;
  }
}

// ─────────────────────────────────────────────────────────────
//  MQTT TELEMETRY & COMMANDS
// ─────────────────────────────────────────────────────────────
void mqttPub(const char* device, const String& payload) {
  if (!mqttClient.isConnected()) return;
  String topic = "tele/" + String(device) + "/status";
  mqttClient.publish(topic, payload, false, 0);
}

void pubOnline()     { mqttPub(CHIP_ID, "online"); }
void pubTemp(float t){ mqttPub(DEV_TEMP, "{\"value\":" + String(t,1) + "}"); }
void pubHumi(float h){ mqttPub(DEV_HUMI, "{\"value\":" + String(h,1) + "}"); }
void pubLight(String s){ mqttPub(DEV_LIGHT, "{\"value\":\"" + s + "\"}"); }
void pubLed()   { ledState = relayRead(PIN_LED); mqttPub(DEV_LED, "{\"value\":\""+ledState+"\"}"); }
void pubFan()   { fanState = relayRead(PIN_FAN); mqttPub(DEV_FAN, "{\"value\":\""+fanState+"\"}"); }
void pubDoor()  { mqttPub(DEV_DOOR, "{\"value\":" + String(doorAngle) + "}"); }
void pubMode()  { mqttPub(DEV_MODE, "{\"value\":\"" + systemMode + "\"}"); }
void pubRFID(String uid) {
  String payload = "{\"uid\":\"" + uid + "\"}";
  mqttPub(DEV_RFID, payload);
}

void mqttCallback(const String& topicStr, const String& payload, const size_t size) {
  String topic = topicStr;
  String cmd = payload;
  cmd.trim();

  Serial.printf("\n📥 [MQTT RX] Topic: %s | Cmd: %s\n", topic.c_str(), cmd.c_str());

  if (topic.indexOf(DEV_MODE) >= 0) {
    systemMode = (cmd == "MANUAL" || cmd == "OFF") ? "MANUAL" : "AUTO";
    Serial.println("🔄 [MODE] Đã chuyển chế độ hoạt động sang: " + systemMode);

    // KHI CHUYỂN VỀ AUTO: Thực hiện đánh giá tự động cảm biến và đóng ngắt ngay lập tức
    if (systemMode == "AUTO") {
      if (!isnan(currentTemp)) {
        if (currentTemp >= TEMP_AUTO_FAN) {
          digitalWrite(PIN_FAN, RELAY_ON);
        } else {
          digitalWrite(PIN_FAN, RELAY_OFF);
        }
      }
      if (lightLevelStr == "Yeu") {
        digitalWrite(PIN_LED, RELAY_ON);
      } else {
        digitalWrite(PIN_LED, RELAY_OFF);
      }
    }

    // ĐỒNG BỘ REALTIME TẤT CẢ THIẾT BỊ NGAY LẬP TỨC
    pubMode(); wsClient.loop(); delay(20);
    pubLed();  wsClient.loop(); delay(20);
    pubFan();  wsClient.loop(); delay(20);
    pubDoor(); wsClient.loop(); delay(20);
    if (!isnan(currentTemp)) pubTemp(currentTemp);
    if (!isnan(currentHumi)) pubHumi(currentHumi);
    pubLight(lightLevelStr);
  }
  else if (topic.indexOf(DEV_LED) >= 0) {
    digitalWrite(PIN_LED, cmd == "ON" ? RELAY_ON : RELAY_OFF);
    pubLed();
  }
  else if (topic.indexOf(DEV_FAN) >= 0) {
    digitalWrite(PIN_FAN, cmd == "ON" ? RELAY_ON : RELAY_OFF);
    pubFan();
  }
  else if (topic.indexOf(DEV_DOOR) >= 0) {
    lastScannedRFID = ""; // Reset cờ RFID để không bị tự đóng cửa khi bật/tắt thủ công qua App
    int a = (cmd == "ON" || cmd == "OPEN" || cmd == "90") ? 90 : ((cmd == "OFF" || cmd == "CLOSE" || cmd == "0") ? 0 : cmd.toInt());
    adjustDoorAngle(a);
    pubDoor();
  }
}

void reconnectMQTT() {
  if (!mqttClient.isConnected()) {
    Serial.print("📡 Đang kết nối MQTT WSS (Port " + String(MQTT_PORT) + ")...");
    uint64_t chipid = ESP.getEfuseMac();
    String clientId = "ESP32-Classroom-" + String((uint32_t)(chipid >> 32), HEX);
    String lwtTopic = "tele/" + String(CHIP_ID) + "/status";

    mqttClient.setWill(lwtTopic, "offline", true, 1);

    if (mqttClient.connect(clientId, "", "")) {
      Serial.println("Thành công!");
      pubOnline(); wsClient.loop(); delay(30);

      mqttClient.subscribe("cmnd/" + String(DEV_MODE) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_MODE) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(30);

      mqttClient.subscribe("cmnd/" + String(DEV_LED) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_LED) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(30);

      mqttClient.subscribe("cmnd/" + String(DEV_FAN) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_FAN) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(30);

      mqttClient.subscribe("cmnd/" + String(DEV_DOOR) + "/POWER", [](const char* payload, unsigned int size) {
        String cmd = ""; for(unsigned int i=0; i<size; i++) cmd += payload[i];
        mqttCallback("cmnd/" + String(DEV_DOOR) + "/POWER", cmd, size);
      });
      wsClient.loop(); delay(30);

      // ĐỒNG BỘ TOÀN BỘ TRẠNG THÁI KHI VỪA CẮM ĐIỆN / KẾT NỐI MẠNG LẠI
      pubMode();  wsClient.loop(); delay(20);
      pubLed();   wsClient.loop(); delay(20);
      pubFan();   wsClient.loop(); delay(20);
      pubDoor();  wsClient.loop(); delay(20);
      pubLight(lightLevelStr); wsClient.loop(); delay(20);
      if (!isnan(currentTemp)) pubTemp(currentTemp);
      if (!isnan(currentHumi)) pubHumi(currentHumi);
    } else {
      Serial.println("Lỗi hoặc đang thiết lập WebSockets...");
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  WEB CAPTIVE PORTAL (CẤU HÌNH WIFI)
// ─────────────────────────────────────────────────────────────
const char PORTAL_HTML[] PROGMEM = R"rawhtml(
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ESP32 Smart Classroom Setup</title>
<style>body{font-family:sans-serif;background:#0f172a;color:#f8fafc;display:flex;justify-content:center;padding:20px}
.c{max-width:400px;width:100%;} input{width:100%;padding:12px;margin-bottom:10px;border-radius:6px;border:none;box-sizing:border-box} button{padding:12px;width:100%;background:#0284c7;color:#fff;border:none;border-radius:6px;cursor:pointer;font-weight:bold}
#st{margin-top:15px;text-align:center;font-weight:bold;padding:10px;border-radius:6px;display:none;}</style>
</head><body><div class="c"><h2>🏫 ESP32 Lớp Học Thông Minh</h2>
<button onclick="scan()" style="margin-bottom:10px;background:#4f46e5;">🔍 Quét danh sách WiFi</button><div id="w" style="margin-bottom:10px;line-height:1.8;cursor:pointer;"></div>
<input id="s" placeholder="Tên WiFi"><input type="password" id="p" placeholder="Mật khẩu WiFi">
<button onclick="conn()">🚀 Kết nối & Lưu</button><div id="st"></div></div>
<script>
function scan() {
  document.getElementById('w').innerHTML = 'Đang quét mạng...';
  fetch('/scan')
    .then(r => r.json())
    .then(l => {
      document.getElementById('w').innerHTML = l.map(n => 
        `<div style="padding:8px; background:#1e293b; margin-top:5px; border-radius:6px;" onclick="document.getElementById('s').value='${n.ssid}'">📶 ${n.ssid} (${n.rssi}dBm)</div>`
      ).join('');
    })
    .catch(e => { document.getElementById('w').innerHTML = '❌ Lỗi quét mạng'; });
}
function conn() {
  const s = document.getElementById('s').value;
  const p = document.getElementById('p').value;
  if (!s) { alert("Vui lòng nhập tên WiFi!"); return; }
  const st = document.getElementById('st');
  st.style.display = 'block';
  st.innerHTML = '⏳ Đang thử kết nối... Vui lòng đợi 15 giây!';
  st.style.background = '#334155'; st.style.color = '#fff';
  fetch('/connect', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'ssid=' + encodeURIComponent(s) + '&pass=' + encodeURIComponent(p)
  })
  .then(r => r.json())
  .then(d => {
    if (d.ok) {
      st.style.background = '#16a34a';
      st.innerHTML = '✅ KẾT NỐI THÀNH CÔNG!<br>Mạch đang khởi động lại...';
      alert("Kết nối thành công! Mạch ESP32 đang tự khởi động lại.");
    } else {
      st.style.background = '#dc2626';
      st.innerHTML = '❌ LỖI: ' + (d.message || 'Kết nối thất bại');
    }
  })
  .catch(e => {
    st.style.background = '#dc2626';
    st.innerHTML = '❌ LỖI MẠNG!<br>Vui lòng kiểm tra lại...';
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
  String ssid = webServer.arg("ssid");
  String pass = webServer.arg("pass");
  if (ssid.length() > 0) {
    Serial.printf("Thử kết nối WiFi: %s\n", ssid.c_str());
    WiFi.begin(ssid.c_str(), pass.c_str());
    for (int i = 0; i < 30 && WiFi.status() != WL_CONNECTED; i++) {
      delay(500);
    }
    if (WiFi.status() == WL_CONNECTED) {
      addOrUpdateWifi(ssid, pass);
      webServer.send(200, "application/json", "{\"ok\":true}");
      delay(1000);
      ESP.restart();
    } else {
      WiFi.disconnect();
      webServer.send(200, "application/json", "{\"ok\":false, \"message\":\"Sai mật khẩu hoặc sóng WiFi kém.\"}");
    }
  } else {
    webServer.send(200, "application/json", "{\"ok\":false, \"message\":\"Tên WiFi không được để trống!\"}");
  }
}

void startPortal() {
  portalActive = true;
  Serial.println("\n🌐 [ESP32] Khởi tạo WiFi Access Point Portal...");
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  dnsServer.start(DNS_PORT, "*", apIP);
  webServer.on("/", HTTP_GET, handleRoot);
  webServer.on("/scan", HTTP_GET, handleScan);
  webServer.on("/connect", HTTP_POST, handleConnect);
  webServer.onNotFound(handleNotFound);
  webServer.begin();

  updateOLEDDisplay(currentTemp, currentHumi, lightLevelStr);
  Serial.println("✅ Portal đã sẵn sàng! Kết nối WiFi: SmartClassroom_ESP32");
}

// ─────────────────────────────────────────────────────────────
//  DOUBLE RESET DETECTOR CHO ESP32
// ─────────────────────────────────────────────────────────────
void checkDoubleReset() {
  if (rtcMagicNumber == DOUBLE_RESET_MAGIC) {
    Serial.println("\n⚠️ DETECTED DOUBLE RESET! Xóa cấu hình WiFi...");
    rtcMagicNumber = 0;
    wifiCount = 0;
    saveWifiList();
    startPortal();
  } else {
    rtcMagicNumber = DOUBLE_RESET_MAGIC;
  }
}

// ─────────────────────────────────────────────────────────────
//  SETUP
// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n╔══════════════════════════════════════════════════╗");
  Serial.println("║  🚀 ESP32 SMART CLASSROOM FIRMWARE INITIALIZING  ║");
  Serial.println("╚══════════════════════════════════════════════════╝");

  // 1. Khởi tạo Relay (Quạt & Đèn)
  pinMode(PIN_FAN, OUTPUT); digitalWrite(PIN_FAN, RELAY_OFF);
  pinMode(PIN_LED, OUTPUT); digitalWrite(PIN_LED, RELAY_OFF);

  // 2. Khởi tạo Cảm biến Quang LDR (Chân GPIO27 - Đọc DO Digital)
  pinMode(PIN_LDR, INPUT);

  // 3. Khởi tạo OLED 0.96" I2C (SDA=17, SCL=21)
  Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println("❌ Lỗi: Không thể tìm thấy màn hình OLED SSD1306!");
  } else {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 10);
    display.println("Smart Classroom ESP32");
    display.println("Khoi dong he thong...");
    display.display();
    Serial.println("✅ Màn hình OLED đã khởi tạo (SDA:17, SCL:21)");
  }

  // 4. Khởi tạo RFID RC522 SPI (SS:5, SCK:18, MISO:19, MOSI:23, RST:22)
  SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_RFID_SS);
  rfc522.PCD_Init();
  Serial.println("✅ RFID RC522 đã sẵn sàng trên SPI (SS:5, RST:22)");

  // 5. Khởi tạo DHT11
  dht.begin();
  Serial.println("✅ Cảm biến DHT11 đã khởi tạo trên GPIO2");

  // 6. Khởi tạo Servo D13
  ESP32PWM::allocateTimer(0);
  servoDoor.setPeriodHertz(50);
  servoDoor.attach(PIN_SERVO, 500, 2400);
  servoDoor.write(0);
  Serial.println("✅ Servo cửa đã gắn trên GPIO13");

  // 7. Cấu hình MQTT WebSocket — kết nối WSS tới mqtt.duynguyen.io.vn:443
  // ESP32 gửi WSS (beginSSL) → Cloudflare lo TLS → forward WS → Mosquitto :9001
  // Cloudflare nhận WSS → decrypt TLS → forward plain WS → Mosquitto :443
  // (Mosquitto không cần SSL, Cloudflare lo phần TLS)
  wsClient.beginSSL(MQTT_HOST, MQTT_PORT, "/mqtt");
  wsClient.setExtraHeaders("Sec-WebSocket-Protocol: mqtt");
  mqttClient.begin(wsClient);

  // 8. Tải WiFi & Kiểm tra Double Reset
  loadWifiList();
  checkDoubleReset();

  if (!portalActive) {
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
  // Xóa cờ double reset sau 3 giây hoạt động ổn định
  if (millis() > 3000 && rtcMagicNumber == DOUBLE_RESET_MAGIC) {
    rtcMagicNumber = 0;
  }

  if (portalActive) {
    dnsServer.processNextRequest();
    webServer.handleClient();
    return;
  }

  unsigned long now = millis();

  // Kiểm tra kết nối WiFi
  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastReconnect >= RECONNECT_MS) {
      lastReconnect = now;
      if (connectBestWifi()) {
        wifiRetries = 0;
      } else {
        wifiRetries++;
        if (wifiRetries >= 3) {
          Serial.println("⚠️ Mất kết nối WiFi! Chuyển sang Web Portal...");
          startPortal();
          wifiRetries = 0;
        }
      }
    }
    return;
  } else {
    wifiRetries = 0;
  }

  // Cập nhật MQTT / WebSockets Client
  wsClient.loop();
  mqttClient.update();

  if (!mqttClient.isConnected()) {
    if (now - lastReconnect >= 5000) {
      lastReconnect = now;
      reconnectMQTT();
    }
  }

  // ───────────────────────────────────────────────────────────
  // 1. ĐỌC CẢM BIẾN NHANH (LDR & RFID RC522)
  // ───────────────────────────────────────────────────────────
  if (now - lastFastRead >= SENSOR_FAST_MS) {
    lastFastRead = now;

    // Đọc cảm biến quang DO (LDR - GPIO27: LOW = SÁNG/TỐT, HIGH = TỐI/YẾU)
    int digitalLDR = digitalRead(PIN_LDR);
    String newLightStr = getLightStatus(digitalLDR);
    if (newLightStr != lightLevelStr) {
      lightLevelStr = newLightStr;
      pubLight(lightLevelStr);
      updateOLEDDisplay(currentTemp, currentHumi, lightLevelStr);
      Serial.printf("☀️ [LDR DO - GPIO27] DigitalVal: %d | Status: %s\n", digitalLDR, lightLevelStr.c_str());
    }

    // Đọc thẻ RFID-RC522
    if (rfc522.PICC_IsNewCardPresent() && rfc522.PICC_ReadCardSerial()) {
      String cardUID = "";
      for (byte i = 0; i < rfc522.uid.size; i++) {
        if (rfc522.uid.uidByte[i] < 0x10) cardUID += "0";
        cardUID += String(rfc522.uid.uidByte[i], HEX);
      }
      cardUID.toUpperCase();
      rfc522.PICC_HaltA();
      rfc522.PCD_StopCrypto1();

      Serial.println("💳 [RFID] Phát hiện thẻ UID: " + cardUID);
      lastScannedRFID = cardUID;
      rfidDisplayTimer = millis();

      // Mở cửa bằng Servo (quay 90 độ) trong 3 giây
      adjustDoorAngle(90);
      pubDoor();
      pubRFID(cardUID);
    }
  }

  // Tự động đóng cửa sau khi mở bằng RFID 3 giây
  if (doorAngle > 0 && lastScannedRFID.length() > 0 && (millis() - rfidDisplayTimer >= 3000)) {
    adjustDoorAngle(0);
    pubDoor();
    lastScannedRFID = ""; // Clear cờ RFID để không bị lặp lại việc ép đóng cửa
  }

  // ───────────────────────────────────────────────────────────
  // 2. ĐỌC DHT11 & ĐIỀU KHIỂN TỰ ĐỘNG QUẠT (KHI NHIỆT ĐỘ >= 27°C)
  // ───────────────────────────────────────────────────────────
  if (now - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = now;

    float t = dht.readTemperature();
    float h = dht.readHumidity();

    if (!isnan(t) && !isnan(h)) {
      currentTemp = t;
      currentHumi = h;

      Serial.printf("🌡️ Nhiệt độ: %.1f°C | 💧 Độ ẩm: %.1f%% | ☀️ Ánh sáng: %s\n",
                    t, h, lightLevelStr.c_str());

      pubTemp(t);
      pubHumi(h);
      pubLight(lightLevelStr);

      // ─────────────────────────────────────────────────────────
      //  ĐIỀU KHIỂN TỰ ĐỘNG CHỈ CHẠY KHI Ở CHẾ ĐỘ AUTO (systemMode == "AUTO")
      // ─────────────────────────────────────────────────────────
      if (systemMode == "AUTO") {
        // 1. TỰ ĐỘNG BẬT/TẮT QUẠT THEO NHIỆT ĐỘ (>= 27°C)
        if (currentTemp >= TEMP_AUTO_FAN) {
          if (digitalRead(PIN_FAN) != RELAY_ON) {
            digitalWrite(PIN_FAN, RELAY_ON);
            pubFan();
            Serial.println("🔥 [AUTO] Nhiệt độ >= 27°C! Tự động BẬT Quạt...");
          }
        } else {
          if (digitalRead(PIN_FAN) == RELAY_ON) {
            digitalWrite(PIN_FAN, RELAY_OFF);
            pubFan();
            Serial.println("❄️ [AUTO] Nhiệt độ < 27°C. Tự động TẮT Quạt...");
          }
        }

        // 2. TỰ ĐỘNG BẬT/TẮT ĐÈN THEO CẢM BIẾN ÁNH SÁNG (ÁNH SÁNG YẾU)
        if (lightLevelStr == "Yeu") {
          if (digitalRead(PIN_LED) != RELAY_ON) {
            digitalWrite(PIN_LED, RELAY_ON);
            pubLed();
            Serial.println("💡 [AUTO] Ánh sáng Yếu! Tự động BẬT Đèn...");
          }
        } else {
          if (digitalRead(PIN_LED) == RELAY_ON) {
            digitalWrite(PIN_LED, RELAY_OFF);
            pubLed();
            Serial.println("☀️ [AUTO] Ánh sáng Tốt/Trung bình. Tự động TẮT Đèn...");
          }
        }
      }
    } else {
      Serial.println("⚠️ Lỗi: Không thể đọc dữ liệu từ cảm biến DHT11!");
    }

    // Cập nhật màn hình OLED
    updateOLEDDisplay(currentTemp, currentHumi, lightLevelStr);
  }

  // Heartbeat
  if (now - lastHeartbeat >= HEARTBEAT_MS) {
    lastHeartbeat = now;
    pubOnline();
  }
}
