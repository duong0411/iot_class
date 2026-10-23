/*
 * ESP32 — LỚP HỌC THÔNG MINH  |  firmware CLASSROOM_02
 *
 * Portal WiFi: thử mạng mới tối đa 8 giây, sai mật khẩu thì về portal ngay,
 * không kẹt 3 lần x 15 giây như bản CLASSROOM_01.
 *
 * Chip MQTT: CLASSROOM_02  (khác CLASSROOM_01)
 *   tele/CLASSROOM_02/status
 *   tele/CLASSROOM_02_<thiet bi>/status
 *   cmnd/CLASSROOM_02_<thiet bi>/POWER
 *
 * Đèn và quạt có AUTO / MANUAL riêng.
 * Quang + gas/CO2 + lửa: digital.
 *   Quang LOW = tối  -> đèn AUTO bật  (MQTT ánh sáng = 0%,  < 40%)
 *   Quang HIGH = sáng -> đèn AUTO tắt (MQTT ánh sáng = 100%, >= 45%)
 *   Quạt AUTO bật khi nhiệt > 30°C hoặc có gas/CO2, tắt khi <= 29.5°C và hết gas.
 *   Có gas/CO2 thì quạt bật kể cả khi đang MANUAL (an toàn), trả lại MANUAL khi hết gas.
 *   Còi kêu khi có cháy hoặc có gas/CO2.
 *   Cửa mở khi quẹt thẻ và thân nhiệt 33–40°C, tự đóng sau 5 giây.
 *
 * Chân:
 *   OLED SH1106 1.3"  SDA 21, SCL 22          3.3V
 *   MLX90614          SDA 16, SCL 27          3.3V  (I2C riêng)
 *   RC522             SS 5, SCK 18, MOSI 23, MISO 19, RST 17   3.3V
 *   DHT11             GPIO 4
 *   Quang DO          GPIO 34  (input-only, không kéo nội)
 *   Gas/CO2 DO        GPIO 35  (input-only, không kéo nội)
 *   Lửa DO            GPIO 32
 *   Relay IN1 đèn     GPIO 26
 *   Relay IN2 quạt    GPIO 33
 *   Còi               GPIO 25
 *   Servo SG90        GPIO 13  (5V riêng, chung GND)
 *
 * Thư viện:
 *   WebSockets (Markus Sattler), MQTTPubSubClient (Hideaki Tai),
 *   Adafruit GFX, Adafruit SH110X,
 *   MFRC522, DHT sensor library, Adafruit Unified Sensor, ESP32Servo
 *   MLX90614 đọc thẳng I2C, không cần thư viện riêng.
 *
 * Portal: WiFi "SmartClassroom_C2" -> http://192.168.4.1
 * Reset nguồn/nút RST hai lần trong 3 giây để xóa WiFi và mở portal.
 *
 * Nếu relay kích ngược: đặt RELAY_ACTIVE_LOW = 0.
 * Nếu digital ngược (còi kêu hoài / đèn bật khi trời sáng): đặt *_ACTIVE_LOW = 0.
 */

#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <WebSocketsClient.h>
#include <MQTTPubSubClient.h>
#include <Wire.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
#include <MFRC522.h>
#include <DHT.h>
#include <ESP32Servo.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// ── chân ────────────────────────────────────────────────────
#define PIN_OLED_SDA  21
#define PIN_OLED_SCL  22
#define PIN_MLX_SDA   16
#define PIN_MLX_SCL   27

#define PIN_RFID_SS   5
#define PIN_RFID_RST  17
#define PIN_SPI_SCK   18
#define PIN_SPI_MISO  19
#define PIN_SPI_MOSI  23

#define PIN_DHT       4
#define PIN_LDR       34
#define PIN_GAS       35
#define PIN_FIRE      32
#define PIN_LED       26
#define PIN_FAN       33
#define PIN_BUZZER    25
#define PIN_SERVO     13

#define SCREEN_W      128
#define SCREEN_H      64

// 1 = kích mức thấp (mạch relay 2 kênh opto thông dụng)
#define RELAY_ACTIVE_LOW  1
// DO mức thấp = sự kiện (module LM393 / MQ / lửa thông dụng)
#define LIGHT_ACTIVE_LOW  1
#define GAS_ACTIVE_LOW    1
#define FIRE_ACTIVE_LOW   1

#if RELAY_ACTIVE_LOW
#define RELAY_ON   LOW
#define RELAY_OFF  HIGH
#else
#define RELAY_ON   HIGH
#define RELAY_OFF  LOW
#endif

#define DHTTYPE DHT11

#define TEMP_FAN_ON    30.0f
#define TEMP_FAN_OFF   29.5f
#define BODY_MIN       33.0f
#define BODY_MAX       40.0f
#define DOOR_OPEN_DEG  90
#define DOOR_SHUT_DEG  0
#define DOOR_HOLD_MS   5000

#define WIFI_TRY_MS    8000
#define WIFI_TRY2_MS   6000
#define FAIL_FAST_MS   3000
#define SENSOR_MS      100
#define DHT_MS         2000
#define MLX_MS         1000
#define OLED_MS        800
#define TELE_MS        3000
#define HEART_MS       10000
#define MQTT_RETRY_MS  5000
#define LIGHT_DB_MS    350
#define HAZARD_DB_MS   120
#define HAZARD_BOOT_MS 3000
#define RFID_GAP_MS    2500
#define MAX_WIFI       5

// ── MQTT: chip khác bản cũ CLASSROOM_01 ─────────────────────
#define MQTT_HOST   "mqtt.duynguyen.io.vn"
#define MQTT_PORT   443
#define MQTT_PATH   "/mqtt"
#define CHIP_ID     "CLASSROOM_02"

#define DEV_TEMP      CHIP_ID "_temp"
#define DEV_HUMI      CHIP_ID "_humi"
#define DEV_LIGHT     CHIP_ID "_light"
#define DEV_LED       CHIP_ID "_led"
#define DEV_FAN       CHIP_ID "_fan"
#define DEV_LED_MODE  CHIP_ID "_led_mode"
#define DEV_FAN_MODE  CHIP_ID "_fan_mode"
#define DEV_DOOR      CHIP_ID "_door"
#define DEV_RFID      CHIP_ID "_rfid"
#define DEV_BODY      CHIP_ID "_body"
#define DEV_GAS       CHIP_ID "_gas"
#define DEV_FIRE      CHIP_ID "_fire"
#define DEV_ALARM     CHIP_ID "_alarm"

#define AP_SSID "SmartClassroom_C2"
IPAddress apIP(192, 168, 4, 1);
const byte DNS_PORT = 53;

// ── đối tượng ───────────────────────────────────────────────
Adafruit_SH1106G display(SCREEN_W, SCREEN_H, &Wire, -1);
MFRC522 rfid(PIN_RFID_SS, PIN_RFID_RST);
DHT dht(PIN_DHT, DHTTYPE);
Servo servoDoor;

WebServer webServer(80);
DNSServer dnsServer;
WebSocketsClient wsClient;
MQTTPubSubClient mqttClient;
Preferences preferences;

struct WifiEntry {
  char ssid[32];
  char pass[64];
};

struct DigIn {
  uint8_t pin;
  bool activeLow;
  uint32_t db;
  bool raw;
  bool stable;
  uint32_t changedAt;
  bool ready;
};

// ── trạng thái ──────────────────────────────────────────────
WifiEntry wifiList[MAX_WIFI];
int wifiCount = 0;
int lastWifiIdx = 0;

bool portalActive = false;
bool oledOK = false;
bool mlxOK = false;
bool mqttInited = false;

bool ledAuto = true;
bool fanAuto = true;
bool ledOn = false;
bool fanOn = false;
bool ledManualOn = false;
bool fanManualOn = false;

bool lightDark = false;
bool gasAlarm = false;
bool fireAlarm = false;

float tempC = NAN;
float humiC = NAN;
float bodyC = NAN;
uint32_t lastDhtOk = 0;

int doorAngle = 0;
bool doorAutoClose = false;
uint32_t doorOpenedAt = 0;
char lastUid[24] = "";
uint32_t lastUidMs = 0;

char ledReason[160] = "Khoi dong";
char fanReason[160] = "Khoi dong";
char portalMsg[96] = "Nhap WiFi 2.4GHz. Thu ket noi toi da 8 giay.";

DigIn lightDig;
DigIn gasDig;
DigIn fireDig;

bool tryWifi = false;
bool tryBegan = false;
uint32_t tryStart = 0;
char trySsid[32] = "";
char tryPass[64] = "";

bool wifiRetryOn = false;
int wifiRetryStep = 0;
bool wifiRetryBegan = false;
uint32_t wifiRetryT0 = 0;

uint32_t bootReadyAt = 0;
uint32_t wifiDownSince = 0;
uint32_t denyUntil = 0;
uint32_t lastFast = 0;
uint32_t lastDht = 0;
uint32_t lastMlx = 0;
uint32_t lastOled = 0;
uint32_t lastTele = 0;
uint32_t lastHeart = 0;
uint32_t lastMqtt = 0;

RTC_DATA_ATTR static uint32_t rtcMagic = 0;
#define DOUBLE_RESET_MAGIC 0xC1A55002

// ── tiện ích ────────────────────────────────────────────────
void setPortalMsg(const char* s) {
  strncpy(portalMsg, s, sizeof(portalMsg) - 1);
  portalMsg[sizeof(portalMsg) - 1] = 0;
  for (char* p = portalMsg; *p; ++p) {
    if (*p == '"' || *p == '\\') *p = ' ';
  }
}

void initDig(DigIn& d, uint8_t pin, bool activeLow, uint32_t db) {
  d.pin = pin;
  d.activeLow = activeLow;
  d.db = db;
  d.raw = false;
  d.stable = false;
  d.changedAt = 0;
  d.ready = false;
}

void pollDig(DigIn& d) {
  bool high = digitalRead(d.pin);
  bool active = d.activeLow ? !high : high;
  uint32_t now = millis();
  if (!d.ready) {
    d.raw = active;
    d.stable = false;
    d.changedAt = now;
    d.ready = true;
    return;
  }
  if (active != d.raw) {
    d.raw = active;
    d.changedAt = now;
    return;
  }
  if ((now - d.changedAt) >= d.db) d.stable = d.raw;
}

void mqttPub(const char* dev, const char* payload) {
  if (!mqttInited || !mqttClient.isConnected()) return;
  char topic[72];
  snprintf(topic, sizeof(topic), "tele/%s/status", dev);
  mqttClient.publish(topic, payload, false, 0);
}

void updateLedReason() {
  if (!ledAuto) {
    snprintf(ledReason, sizeof(ledReason), "Thu cong");
  } else if (lightDark) {
    snprintf(ledReason, sizeof(ledReason),
             "Tu dong BAT: Anh sang 0%% < 40%% (Toi)");
  } else {
    snprintf(ledReason, sizeof(ledReason),
             "Tu dong TAT: Anh sang 100%% >= 45%% (Du sang)");
  }
}

void updateFanReason() {
  if (gasAlarm) {
    snprintf(fanReason, sizeof(fanReason), "BAT an toan: Phat hien gas/CO2");
  } else if (!fanAuto) {
    snprintf(fanReason, sizeof(fanReason), "Thu cong");
  } else if (!isnan(tempC) && tempC > TEMP_FAN_ON) {
    snprintf(fanReason, sizeof(fanReason),
             "Tu dong BAT: Nhiet do phong %.1fC > 30C (Nong)", tempC);
  } else if (!isnan(tempC) && tempC <= TEMP_FAN_OFF) {
    snprintf(fanReason, sizeof(fanReason),
             "Tu dong TAT: Nhiet do phong %.1fC <= 29.5C", tempC);
  } else if (!isnan(tempC)) {
    snprintf(fanReason, sizeof(fanReason),
             "Giu trang thai: Nhiet do %.1fC (29.5-30C)", tempC);
  } else {
    snprintf(fanReason, sizeof(fanReason), "Chua co nhiet do DHT11");
  }
}

void publishLedMode() {
  mqttPub(DEV_LED_MODE, ledAuto ? "{\"value\":\"AUTO\"}" : "{\"value\":\"MANUAL\"}");
}
void publishFanMode() {
  mqttPub(DEV_FAN_MODE, fanAuto ? "{\"value\":\"AUTO\"}" : "{\"value\":\"MANUAL\"}");
}

void publishLed() {
  updateLedReason();
  char buf[240];
  snprintf(buf, sizeof(buf),
           "{\"value\":\"%s\",\"mode\":\"%s\",\"reason\":\"%s\"}",
           ledOn ? "ON" : "OFF", ledAuto ? "AUTO" : "MANUAL", ledReason);
  mqttPub(DEV_LED, buf);
}

void publishFan() {
  updateFanReason();
  char buf[240];
  snprintf(buf, sizeof(buf),
           "{\"value\":\"%s\",\"mode\":\"%s\",\"reason\":\"%s\"}",
           fanOn ? "ON" : "OFF", fanAuto ? "AUTO" : "MANUAL", fanReason);
  mqttPub(DEV_FAN, buf);
}

void publishLight() {
  char buf[80];
  snprintf(buf, sizeof(buf),
           "{\"value\":%d,\"state\":\"%s\",\"raw\":%d}",
           lightDark ? 0 : 100,
           lightDark ? "DARK" : "BRIGHT",
           lightDark ? 0 : 1);
  mqttPub(DEV_LIGHT, buf);
}

void publishTemp() {
  if (isnan(tempC)) return;
  char buf[32];
  snprintf(buf, sizeof(buf), "{\"value\":%.1f}", tempC);
  mqttPub(DEV_TEMP, buf);
}
void publishHumi() {
  if (isnan(humiC)) return;
  char buf[32];
  snprintf(buf, sizeof(buf), "{\"value\":%.1f}", humiC);
  mqttPub(DEV_HUMI, buf);
}
void publishBody() {
  if (isnan(bodyC)) return;
  char buf[32];
  snprintf(buf, sizeof(buf), "{\"value\":%.1f}", bodyC);
  mqttPub(DEV_BODY, buf);
}
void publishGas() {
  mqttPub(DEV_GAS, gasAlarm ? "{\"value\":\"ON\"}" : "{\"value\":\"OFF\"}");
}
void publishFire() {
  mqttPub(DEV_FIRE, fireAlarm ? "{\"value\":\"ON\"}" : "{\"value\":\"OFF\"}");
}
void publishAlarm() {
  char buf[48];
  snprintf(buf, sizeof(buf), "{\"value\":\"%s\",\"gas\":%d,\"fire\":%d}",
           (gasAlarm || fireAlarm) ? "ON" : "OFF", gasAlarm ? 1 : 0, fireAlarm ? 1 : 0);
  mqttPub(DEV_ALARM, buf);
}
void publishDoor() {
  char buf[24];
  snprintf(buf, sizeof(buf), "{\"value\":%d}", doorAngle);
  mqttPub(DEV_DOOR, buf);
}

void writeLed(bool on) {
  ledOn = on;
  digitalWrite(PIN_LED, on ? RELAY_ON : RELAY_OFF);
}
void writeFan(bool on) {
  fanOn = on;
  digitalWrite(PIN_FAN, on ? RELAY_ON : RELAY_OFF);
}

void commitLed(bool forcePub) {
  bool want = ledAuto ? lightDark : ledManualOn;
  bool changed = (want != ledOn);
  if (changed) writeLed(want);
  if (changed || forcePub) publishLed();
}

void commitFan(bool forcePub) {
  bool have = false;
  bool want = fanOn;
  if (gasAlarm) {
    want = true;
    have = true;
  } else if (!fanAuto) {
    want = fanManualOn;
    have = true;
  } else if (!isnan(tempC)) {
    if (tempC > TEMP_FAN_ON) {
      want = true;
      have = true;
    } else if (tempC <= TEMP_FAN_OFF) {
      want = false;
      have = true;
    }
  }
  bool changed = have && (want != fanOn);
  if (changed) writeFan(want);
  if (changed || forcePub) publishFan();
}

void saveCfg() {
  preferences.begin("sc2cfg", false);
  preferences.putBool("leda", ledAuto);
  preferences.putBool("fana", fanAuto);
  preferences.putBool("ledp", ledManualOn);
  preferences.putBool("fanp", fanManualOn);
  preferences.end();
}

void loadCfg() {
  preferences.begin("sc2cfg", true);
  ledAuto = preferences.getBool("leda", true);
  fanAuto = preferences.getBool("fana", true);
  ledManualOn = preferences.getBool("ledp", false);
  fanManualOn = preferences.getBool("fanp", false);
  preferences.end();
}

void setLedAuto(bool v) {
  ledAuto = v;
  saveCfg();
  commitLed(true);
  publishLedMode();
}
void setFanAuto(bool v) {
  fanAuto = v;
  saveCfg();
  commitFan(true);
  publishFanMode();
}
void setLedPower(bool on) {
  ledAuto = false;
  ledManualOn = on;
  saveCfg();
  commitLed(true);
  publishLedMode();
}
void setFanPower(bool on) {
  fanAuto = false;
  fanManualOn = on;
  saveCfg();
  commitFan(true);
  publishFanMode();
}

void setDoor(int angle, bool autoClose) {
  doorAngle = constrain(angle, 0, 180);
  servoDoor.write(doorAngle);
  doorAutoClose = autoClose && doorAngle > 0;
  if (doorAutoClose) doorOpenedAt = millis();
  publishDoor();
}

void startDenyBeep() {
  if (gasAlarm || fireAlarm) return;
  denyUntil = millis() + 480;
}

float readBody() {
  if (!mlxOK) return NAN;
  Wire1.beginTransmission(0x5A);
  Wire1.write(0x07);  // RAM Tobj1
  if (Wire1.endTransmission(false) != 0) return NAN;
  if (Wire1.requestFrom((uint8_t)0x5A, (uint8_t)3) != 3) return NAN;
  uint16_t lo = Wire1.read();
  uint16_t hi = Wire1.read();
  Wire1.read();
  uint16_t raw = (hi << 8) | lo;
  if (raw == 0) return NAN;
  float t = raw * 0.02f - 273.15f;
  if (t < 0.0f || t > 80.0f) return NAN;
  return t;
}

void publishRfid(const char* uid, float body, const char* result) {
  char buf[96];
  snprintf(buf, sizeof(buf),
           "{\"uid\":\"%s\",\"body\":%.1f,\"result\":\"%s\"}",
           uid, isnan(body) ? 0.0f : body, result);
  mqttPub(DEV_RFID, buf);
}

void onCard(const char* uid) {
  uint32_t now = millis();
  if (doorAutoClose && strcmp(uid, lastUid) == 0) return;
  if (strcmp(uid, lastUid) == 0 && (now - lastUidMs) < RFID_GAP_MS) return;
  strncpy(lastUid, uid, sizeof(lastUid) - 1);
  lastUid[sizeof(lastUid) - 1] = 0;
  lastUidMs = now;

  float body = readBody();
  if (!isnan(body)) bodyC = body;

  bool ok = !isnan(body) && body >= BODY_MIN && body <= BODY_MAX;
  const char* result = ok ? "OPEN" : (isnan(body) ? "NOTEMP" : "DENY");
  if (isnan(body)) Serial.printf("[RFID] %s than nhiet -- -> %s\n", uid, result);
  else Serial.printf("[RFID] %s than nhiet %.1f -> %s\n", uid, body, result);
  publishRfid(uid, body, result);
  publishBody();

  if (ok) {
    setDoor(DOOR_OPEN_DEG, true);
  } else {
    startDenyBeep();
  }
}

void serviceDoor() {
  if (doorAutoClose && (millis() - doorOpenedAt >= DOOR_HOLD_MS)) {
    Serial.println(F("[DOOR] Dong sau 5 giay"));
    setDoor(DOOR_SHUT_DEG, false);
  }
}

void serviceBuzzer() {
  if (gasAlarm || fireAlarm) {
    uint32_t step = (gasAlarm && fireAlarm) ? 100 : 180;
    bool on = ((millis() / step) % 2) == 0;
    digitalWrite(PIN_BUZZER, on ? HIGH : LOW);
    return;
  }
  if (denyUntil && millis() < denyUntil) {
    bool on = ((millis() / 120) % 2) == 0;
    digitalWrite(PIN_BUZZER, on ? HIGH : LOW);
    return;
  }
  denyUntil = 0;
  digitalWrite(PIN_BUZZER, LOW);
}

void readRfid() {
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return;
  char uid[24];
  int p = 0;
  uid[0] = 0;
  for (byte i = 0; i < rfid.uid.size && p < (int)sizeof(uid) - 3; i++) {
    p += snprintf(uid + p, sizeof(uid) - p, "%02X", rfid.uid.uidByte[i]);
  }
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  if (p > 0) onCard(uid);
}

void serviceFast() {
  pollDig(lightDig);
  pollDig(gasDig);
  pollDig(fireDig);

  bool hazardReady = millis() >= bootReadyAt;
  bool newDark = lightDig.stable;
  bool newGas = hazardReady && gasDig.stable;
  bool newFire = hazardReady && fireDig.stable;

  bool lightEdge = newDark != lightDark;
  bool gasEdge = newGas != gasAlarm;
  bool fireEdge = newFire != fireAlarm;
  lightDark = newDark;
  gasAlarm = newGas;
  fireAlarm = newFire;

  if (lightEdge) {
    Serial.printf("[LDR] %s\n", lightDark ? "TOI" : "SANG");
    publishLight();
  }
  if (gasEdge) {
    Serial.printf("[GAS] %s\n", gasAlarm ? "BAO" : "OK");
    publishGas();
  }
  if (fireEdge) {
    Serial.printf("[FIRE] %s\n", fireAlarm ? "BAO" : "OK");
    publishFire();
  }
  if (gasEdge || fireEdge) publishAlarm();

  commitLed(false);
  commitFan(gasEdge);
  readRfid();
  serviceDoor();
  serviceBuzzer();
}

void serviceDht() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t) && !isnan(h)) {
    tempC = t;
    humiC = h;
    lastDhtOk = millis();
    commitFan(false);
  } else if (lastDhtOk && (millis() - lastDhtOk > 60000)) {
    tempC = NAN;
    humiC = NAN;
  }
}

void serviceMlx() {
  float t = readBody();
  if (!isnan(t)) bodyC = t;
}

// ── WiFi lưu trong flash (namespace mới, không dùng pass cũ) ─
void saveWifiList() {
  preferences.begin("sc2wifi", false);
  preferences.putInt("count", wifiCount);
  for (int i = 0; i < wifiCount; i++) {
    char ks[8], kp[8];
    snprintf(ks, sizeof(ks), "s%d", i);
    snprintf(kp, sizeof(kp), "p%d", i);
    preferences.putString(ks, wifiList[i].ssid);
    preferences.putString(kp, wifiList[i].pass);
  }
  for (int i = wifiCount; i < MAX_WIFI; i++) {
    char ks[8], kp[8];
    snprintf(ks, sizeof(ks), "s%d", i);
    snprintf(kp, sizeof(kp), "p%d", i);
    preferences.remove(ks);
    preferences.remove(kp);
  }
  preferences.end();
}

void loadWifiList() {
  preferences.begin("sc2wifi", true);
  wifiCount = preferences.getInt("count", 0);
  if (wifiCount < 0 || wifiCount > MAX_WIFI) wifiCount = 0;
  for (int i = 0; i < wifiCount; i++) {
    char ks[8], kp[8];
    snprintf(ks, sizeof(ks), "s%d", i);
    snprintf(kp, sizeof(kp), "p%d", i);
    String s = preferences.getString(ks, "");
    String p = preferences.getString(kp, "");
    strncpy(wifiList[i].ssid, s.c_str(), sizeof(wifiList[i].ssid) - 1);
    strncpy(wifiList[i].pass, p.c_str(), sizeof(wifiList[i].pass) - 1);
    wifiList[i].ssid[sizeof(wifiList[i].ssid) - 1] = 0;
    wifiList[i].pass[sizeof(wifiList[i].pass) - 1] = 0;
  }
  preferences.end();
  if (wifiCount > 0) lastWifiIdx = wifiCount - 1;
}

void clearWifiList() {
  wifiCount = 0;
  memset(wifiList, 0, sizeof(wifiList));
  saveWifiList();
}

void addOrUpdateWifi(const char* ssid, const char* pass) {
  for (int i = 0; i < wifiCount; i++) {
    if (strcmp(wifiList[i].ssid, ssid) == 0) {
      strncpy(wifiList[i].pass, pass, sizeof(wifiList[i].pass) - 1);
      wifiList[i].pass[sizeof(wifiList[i].pass) - 1] = 0;
      lastWifiIdx = i;
      saveWifiList();
      return;
    }
  }
  if (wifiCount >= MAX_WIFI) {
    for (int i = 0; i < MAX_WIFI - 1; i++) wifiList[i] = wifiList[i + 1];
    wifiCount = MAX_WIFI - 1;
  }
  strncpy(wifiList[wifiCount].ssid, ssid, sizeof(wifiList[wifiCount].ssid) - 1);
  strncpy(wifiList[wifiCount].pass, pass, sizeof(wifiList[wifiCount].pass) - 1);
  wifiList[wifiCount].ssid[sizeof(wifiList[wifiCount].ssid) - 1] = 0;
  wifiList[wifiCount].pass[sizeof(wifiList[wifiCount].pass) - 1] = 0;
  lastWifiIdx = wifiCount;
  wifiCount++;
  saveWifiList();
}

bool connectOne(const char* ssid, const char* pass, uint32_t timeoutMs) {
  Serial.printf("[WiFi] Thu %s (<= %lus)\n", ssid, (unsigned long)(timeoutMs / 1000));
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setHostname("classroom-02");
  WiFi.disconnect(false, true);
  delay(80);
  WiFi.begin(ssid, pass);

  uint32_t t0 = millis();
  while (true) {
    wl_status_t st = WiFi.status();
    if (st == WL_CONNECTED) {
      WiFi.setSleep(false);
      WiFi.setAutoReconnect(true);
      Serial.print(F("[WiFi] OK "));
      Serial.println(WiFi.localIP());
      return true;
    }
    uint32_t elapsed = millis() - t0;
    bool dead = (st == WL_CONNECT_FAILED || st == WL_NO_SSID_AVAIL);
    if (elapsed >= timeoutMs || (dead && elapsed >= FAIL_FAST_MS)) {
      Serial.println(F("[WiFi] FAIL"));
      return false;
    }
    delay(150);
    Serial.print('.');
  }
}

bool connectSaved() {
  if (wifiCount <= 0) return false;
  int idx[2];
  int n = 0;
  idx[n++] = wifiCount - 1;
  if (wifiCount >= 2) idx[n++] = wifiCount - 2;
  for (int i = 0; i < n; i++) {
    uint32_t ms = (i == 0) ? WIFI_TRY_MS : WIFI_TRY2_MS;
    if (connectOne(wifiList[idx[i]].ssid, wifiList[idx[i]].pass, ms)) {
      lastWifiIdx = idx[i];
      return true;
    }
  }
  setPortalMsg("Khong vao duoc WiFi da luu. Nhap lai mang 2.4GHz.");
  return false;
}

void bringApUp() {
  WiFi.mode(WIFI_AP);
  delay(30);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(AP_SSID, nullptr, 1, 0, 4);
}

// ── MQTT ────────────────────────────────────────────────────
void normalizeCmd(char* s) {
  int len = strlen(s);
  while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\r' || s[len - 1] == '\n' || s[len - 1] == '\t')) {
    s[--len] = 0;
  }
  int i = 0;
  while (s[i] == ' ' || s[i] == '\t') i++;
  if (i) memmove(s, s + i, strlen(s + i) + 1);
  for (char* p = s; *p; ++p) {
    if (*p >= 'a' && *p <= 'z') *p = *p - 32;
  }
}

void extractCmd(char* s) {
  char* v = strstr(s, "value");
  if (v) {
    char* c = strchr(v, ':');
    if (c) {
      c++;
      while (*c == ' ' || *c == '"') c++;
      char* e = c;
      while (*e && *e != '"' && *e != '}' && *e != ',' && *e != ' ') e++;
      *e = 0;
      memmove(s, c, strlen(c) + 1);
    }
  }
  normalizeCmd(s);
}

void handleCmd(const char* topic, const char* raw) {
  char cmd[48];
  strncpy(cmd, raw, sizeof(cmd) - 1);
  cmd[sizeof(cmd) - 1] = 0;
  extractCmd(cmd);
  Serial.printf("[MQTT] %s <= %s\n", topic, cmd);

  if (strstr(topic, DEV_LED_MODE)) {
    if (!strcmp(cmd, "MANUAL")) setLedAuto(false);
    else if (!strcmp(cmd, "AUTO")) setLedAuto(true);
  } else if (strstr(topic, DEV_FAN_MODE)) {
    if (!strcmp(cmd, "MANUAL")) setFanAuto(false);
    else if (!strcmp(cmd, "AUTO")) setFanAuto(true);
  } else if (strstr(topic, DEV_LED)) {
    if (!strcmp(cmd, "AUTO")) setLedAuto(true);
    else if (!strcmp(cmd, "MANUAL")) setLedAuto(false);
    else if (!strcmp(cmd, "ON")) setLedPower(true);
    else if (!strcmp(cmd, "OFF")) setLedPower(false);
  } else if (strstr(topic, DEV_FAN)) {
    if (!strcmp(cmd, "AUTO")) setFanAuto(true);
    else if (!strcmp(cmd, "MANUAL")) setFanAuto(false);
    else if (!strcmp(cmd, "ON")) setFanPower(true);
    else if (!strcmp(cmd, "OFF")) setFanPower(false);
  } else if (strstr(topic, DEV_DOOR)) {
    int angle;
    if (!strcmp(cmd, "ON") || !strcmp(cmd, "OPEN") || !strcmp(cmd, "90")) angle = DOOR_OPEN_DEG;
    else if (!strcmp(cmd, "OFF") || !strcmp(cmd, "CLOSE") || !strcmp(cmd, "0")) angle = DOOR_SHUT_DEG;
    else angle = atoi(cmd);
    setDoor(angle, false);
  }
}

void subscribeDev(const char* dev) {
  char topic[72];
  snprintf(topic, sizeof(topic), "cmnd/%s/POWER", dev);
  String t(topic);
  mqttClient.subscribe(t, [t](const char* payload, unsigned int size) {
    char buf[48];
    unsigned int n = size < sizeof(buf) - 1 ? size : sizeof(buf) - 1;
    memcpy(buf, payload, n);
    buf[n] = 0;
    handleCmd(t.c_str(), buf);
  });
  wsClient.loop();
  delay(15);
}

void syncAll() {
  mqttPub(CHIP_ID, "online");
  wsClient.loop();
  publishLedMode();
  publishFanMode();
  publishLed();
  publishFan();
  publishLight();
  publishGas();
  publishFire();
  publishAlarm();
  publishDoor();
  publishTemp();
  publishHumi();
  publishBody();
  wsClient.loop();
}

void connectMqtt() {
  if (!mqttInited || mqttClient.isConnected()) return;
  uint32_t mac = (uint32_t)ESP.getEfuseMac();
  char clientId[24];
  snprintf(clientId, sizeof(clientId), "cls02-%08X", mac);
  char willTopic[48];
  snprintf(willTopic, sizeof(willTopic), "tele/%s/status", CHIP_ID);

  Serial.printf("[MQTT] %s ...\n", clientId);
  mqttClient.setWill(willTopic, "offline", true, 1);
  if (!mqttClient.connect(clientId, "", "")) {
    Serial.println(F("[MQTT] WS chua san sang"));
    return;
  }
  Serial.println(F("[MQTT] OK"));
  subscribeDev(DEV_LED_MODE);
  subscribeDev(DEV_FAN_MODE);
  subscribeDev(DEV_LED);
  subscribeDev(DEV_FAN);
  subscribeDev(DEV_DOOR);
  syncAll();
}

void initMqtt() {
  if (mqttInited) return;
  wsClient.beginSSL(MQTT_HOST, MQTT_PORT, MQTT_PATH);
  wsClient.setExtraHeaders("Sec-WebSocket-Protocol: mqtt");
  wsClient.setReconnectInterval(5000);
  mqttClient.begin(wsClient);
  mqttInited = true;
}

void printTopics() {
  const char* devs[] = {
    DEV_TEMP, DEV_HUMI, DEV_LIGHT, DEV_LED, DEV_FAN, DEV_LED_MODE, DEV_FAN_MODE,
    DEV_DOOR, DEV_RFID, DEV_BODY, DEV_GAS, DEV_FIRE, DEV_ALARM
  };
  Serial.printf("Chip %s  tele/%s/status = online\n", CHIP_ID, CHIP_ID);
  for (unsigned i = 0; i < sizeof(devs) / sizeof(devs[0]); i++) {
    Serial.printf("  tele/%s/status\n", devs[i]);
  }
  Serial.println(F("  Lenh: cmnd/<id>/POWER  ON|OFF|AUTO|MANUAL"));
}

// ── portal ──────────────────────────────────────────────────
const char PORTAL_HTML[] PROGMEM = R"RAW(
<!DOCTYPE html><html><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Classroom C2</title>
<style>
body{font-family:sans-serif;background:#0f172a;color:#e2e8f0;padding:16px}
.c{max-width:420px;margin:auto}
input,button{width:100%;padding:12px;margin:6px 0;border:0;border-radius:8px;box-sizing:border-box}
button{background:#0284c7;color:#fff;font-weight:700}
.item{background:#1e293b;padding:8px;margin:4px 0;border-radius:6px}
#st{min-height:1.2em;color:#fde68a}
small{color:#94a3b8}
</style></head><body><div class="c">
<h2>Lop hoc thong minh</h2>
<p>Chip <b>CLASSROOM_02</b> — WiFi <b>SmartClassroom_C2</b></p>
<button type="button" onclick="scan()">Quet WiFi 2.4GHz</button>
<div id="w"></div>
<input id="s" placeholder="Ten WiFi" maxlength="31">
<input id="p" type="password" placeholder="Mat khau" maxlength="63">
<button type="button" onclick="conn()">Ket noi (toi da 8 giay)</button>
<button type="button" onclick="wipe()" style="background:#334155">Xoa WiFi da luu</button>
<p id="st">San sang</p>
<small>Sai mat khau thi bao trong vai giay va giu portal, khong khoi dong lai mai. Chi dung WiFi 2.4GHz. Nhan RST hai lan trong 3 giay de mo lai portal.</small>
</div>
<script>
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');}
async function tick(){
  try{
    const j=await (await fetch('/status')).json();
    var extra=j.left?(' ('+j.left+'s)'):'';
    document.getElementById('st').textContent=(j.msg||j.state)+extra;
  }catch(e){
    document.getElementById('st').textContent='Mat AP. Noi lai SmartClassroom_C2 roi tai lai trang.';
  }
}
async function scan(){
  document.getElementById('w').textContent='Dang quet...';
  try{
    const l=await (await fetch('/scan')).json();
    document.getElementById('w').innerHTML=l.map(function(n){
      return '<div class="item" data-s="'+esc(n.ssid)+'">'+esc(n.ssid)+' ('+n.rssi+' dBm)</div>';
    }).join('')||'Khong thay mang';
    document.querySelectorAll('#w .item').forEach(function(el){
      el.onclick=function(){document.getElementById('s').value=el.getAttribute('data-s')||'';};
    });
  }catch(e){document.getElementById('w').textContent='Loi quet';}
}
async function conn(){
  var s=document.getElementById('s').value.trim();
  var p=document.getElementById('p').value;
  if(!s){alert('Nhap ten WiFi');return;}
  document.getElementById('st').textContent='Dang gui...';
  var body='ssid='+encodeURIComponent(s)+'&pass='+encodeURIComponent(p);
  try{
    var j=await (await fetch('/connect',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:body})).json();
    document.getElementById('st').textContent=j.msg||'Dang thu';
  }catch(e){
    document.getElementById('st').textContent='Da gui. Neu mat AP, noi lai SmartClassroom_C2.';
  }
}
async function wipe(){
  if(!confirm('Xoa toan bo WiFi da luu?'))return;
  await fetch('/forget',{method:'POST'});
  tick();
}
setInterval(tick,1000);tick();
</script></body></html>
)RAW";

void handleRoot() {
  webServer.send_P(200, "text/html", PORTAL_HTML);
}

void handleStatus() {
  int left = 0;
  const char* st = "portal";
  if (tryWifi) {
    st = "trying";
    uint32_t el = (tryBegan) ? (millis() - tryStart) : 0;
    left = (!tryBegan || el >= WIFI_TRY_MS) ? (tryBegan ? 0 : 8) : (int)((WIFI_TRY_MS - el) / 1000);
  }
  const char* ip = "";
  String ipStr;
  if (WiFi.status() == WL_CONNECTED) {
    ipStr = WiFi.localIP().toString();
    ip = ipStr.c_str();
    st = "ok";
  }
  char buf[256];
  snprintf(buf, sizeof(buf),
           "{\"state\":\"%s\",\"msg\":\"%s\",\"left\":%d,\"saved\":%d,\"chip\":\"%s\",\"ip\":\"%s\"}",
           st, portalMsg, left, wifiCount, CHIP_ID, ip);
  webServer.send(200, "application/json", buf);
}

void handleScan() {
  if (tryWifi) {
    webServer.send(200, "application/json", "[]");
    return;
  }
  WiFi.mode(WIFI_AP_STA);
  delay(50);
  int n = WiFi.scanNetworks(false, false, false, 80);
  String json = "[";
  if (n > 0) {
    for (int i = 0; i < n; i++) {
      if (i) json += ",";
      String ssid = WiFi.SSID(i);
      ssid.replace("\\", "\\\\");
      ssid.replace("\"", "\\\"");
      json += "{\"ssid\":\"" + ssid + "\",\"rssi\":" + String(WiFi.RSSI(i)) + "}";
    }
    WiFi.scanDelete();
  }
  json += "]";
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(AP_SSID, nullptr, 1, 0, 4);
  webServer.send(200, "application/json", json);
}

void handleConnect() {
  if (tryWifi) {
    webServer.send(200, "application/json", "{\"ok\":false,\"msg\":\"Dang thu ket noi\"}");
    return;
  }
  String ssid = webServer.arg("ssid");
  String pass = webServer.arg("pass");
  ssid.trim();
  if (ssid.length() == 0 || ssid.length() > 31 || pass.length() > 63) {
    webServer.send(200, "application/json", "{\"ok\":false,\"msg\":\"Ten WiFi khong hop le\"}");
    return;
  }
  strncpy(trySsid, ssid.c_str(), sizeof(trySsid) - 1);
  strncpy(tryPass, pass.c_str(), sizeof(tryPass) - 1);
  trySsid[sizeof(trySsid) - 1] = 0;
  tryPass[sizeof(tryPass) - 1] = 0;
  tryWifi = true;
  tryBegan = false;
  tryStart = millis();
  setPortalMsg("Dang thu ket noi, toi da 8 giay");
  Serial.printf("[PORTAL] Yeu cau thu '%s'\n", trySsid);
  webServer.send(200, "application/json", "{\"ok\":true,\"msg\":\"Dang thu ket noi, toi da 8 giay\"}");
}

void handleForget() {
  clearWifiList();
  setPortalMsg("Da xoa WiFi. Nhap mang moi.");
  webServer.send(200, "application/json", "{\"ok\":true,\"msg\":\"Da xoa WiFi\"}");
}

void portalFail(const char* why) {
  Serial.println(why);
  char msg[96];
  snprintf(msg, sizeof(msg), "Khong vao duoc %s. Kiem tra mat khau 2.4GHz.", trySsid);
  setPortalMsg(msg);
  tryWifi = false;
  tryBegan = false;
  WiFi.setAutoReconnect(false);
  WiFi.disconnect(false, true);
  delay(40);
  bringApUp();
}

void portalTryLoop() {
  if (!tryWifi) return;
  if (!tryBegan) {
    tryBegan = true;
    tryStart = millis();
    Serial.printf("[PORTAL] Bat dau %s\n", trySsid);
    WiFi.setAutoReconnect(false);
    WiFi.mode(WIFI_AP_STA);
    delay(80);
    WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
    WiFi.softAP(AP_SSID, nullptr, 1, 0, 4);
    delay(40);
    WiFi.begin(trySsid, tryPass);
    return;
  }

  wl_status_t st = WiFi.status();
  if (st == WL_CONNECTED) {
    addOrUpdateWifi(trySsid, tryPass);
    String ip = WiFi.localIP().toString();
    char msg[96];
    snprintf(msg, sizeof(msg), "Da ket noi %s. Restart.", ip.c_str());
    setPortalMsg(msg);
    Serial.println(msg);
    tryWifi = false;
    delay(700);
    ESP.restart();
    return;
  }

  uint32_t elapsed = millis() - tryStart;
  bool dead = (st == WL_CONNECT_FAILED || st == WL_NO_SSID_AVAIL);
  if (elapsed >= WIFI_TRY_MS || (dead && elapsed >= FAIL_FAST_MS)) {
    portalFail(dead ? "[PORTAL] Tu choi / khong thay mang" : "[PORTAL] Qua 8 giay");
  }
}

void startPortal() {
  if (portalActive) return;
  portalActive = true;
  wifiRetryOn = false;
  tryWifi = false;
  tryBegan = false;
  Serial.println(F("[PORTAL] Mo SoftAP"));
  if (mqttInited) wsClient.disconnect();
  WiFi.persistent(false);
  WiFi.setAutoReconnect(false);
  WiFi.disconnect(true);
  delay(40);
  WiFi.mode(WIFI_OFF);
  delay(40);
  bringApUp();
  Serial.printf("[PORTAL] %s  IP %s\n", AP_SSID, WiFi.softAPIP().toString().c_str());

  dnsServer.stop();
  dnsServer.start(DNS_PORT, "*", apIP);
  webServer.stop();
  webServer.on("/", HTTP_GET, handleRoot);
  webServer.on("/scan", HTTP_GET, handleScan);
  webServer.on("/status", HTTP_GET, handleStatus);
  webServer.on("/connect", HTTP_POST, handleConnect);
  webServer.on("/forget", HTTP_POST, handleForget);
  webServer.on("/generate_204", HTTP_GET, handleRoot);
  webServer.on("/gen_204", HTTP_GET, handleRoot);
  webServer.on("/hotspot-detect.html", HTTP_GET, handleRoot);
  webServer.on("/connecttest.txt", HTTP_GET, handleRoot);
  webServer.on("/ncsi.txt", HTTP_GET, handleRoot);
  webServer.on("/fwlink", HTTP_GET, handleRoot);
  webServer.onNotFound([]() {
    webServer.sendHeader("Location", "http://192.168.4.1/", true);
    webServer.send(302, "text/plain", "");
  });
  webServer.begin();
}

void serviceWifiRetry() {
  if (!wifiRetryOn) {
    if (wifiCount <= 0) {
      setPortalMsg("Mat WiFi va chua co mang luu.");
      startPortal();
      return;
    }
    wifiRetryOn = true;
    wifiRetryStep = 0;
    wifiRetryBegan = false;
    return;
  }

  int idx = (wifiRetryStep == 0) ? lastWifiIdx : (lastWifiIdx == 0 ? wifiCount - 1 : 0);
  if (idx < 0 || idx >= wifiCount || (wifiRetryStep > 0 && idx == lastWifiIdx) || wifiRetryStep > 1) {
    setPortalMsg("Mat WiFi. Mo portal de nhap mang moi.");
    startPortal();
    return;
  }

  if (!wifiRetryBegan) {
    Serial.printf("[WiFi] Mat mang, thu lai %s\n", wifiList[idx].ssid);
    WiFi.mode(WIFI_STA);
    WiFi.begin(wifiList[idx].ssid, wifiList[idx].pass);
    wifiRetryBegan = true;
    wifiRetryT0 = millis();
    return;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(F("[WiFi] Noi lai OK"));
    WiFi.setSleep(false);
    WiFi.setAutoReconnect(true);
    lastWifiIdx = idx;
    wifiRetryOn = false;
    wifiRetryBegan = false;
    return;
  }

  uint32_t limit = (wifiRetryStep == 0) ? WIFI_TRY_MS : WIFI_TRY2_MS;
  wl_status_t st = WiFi.status();
  bool dead = (st == WL_CONNECT_FAILED || st == WL_NO_SSID_AVAIL);
  if ((millis() - wifiRetryT0) >= limit || (dead && (millis() - wifiRetryT0) >= FAIL_FAST_MS)) {
    wifiRetryStep++;
    wifiRetryBegan = false;
  }
}

// ── OLED ────────────────────────────────────────────────────
void drawOled() {
  if (!oledOK) return;
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);
  display.setTextSize(1);

  display.setCursor(0, 0);
  if (portalActive) {
    display.print(F("AP SmartClassroom_C2"));
  } else if (WiFi.status() == WL_CONNECTED) {
    display.print(mqttClient.isConnected() ? F("C2 NET MQTT") : F("C2 NET ...."));
  } else if (wifiRetryOn) {
    display.print(F("C2 dang noi lai"));
  } else {
    display.print(F("C2 khoi dong"));
  }

  display.setCursor(0, 10);
  if (!isnan(tempC)) display.printf("T:%.1fC H:%.0f%%", tempC, isnan(humiC) ? 0 : humiC);
  else display.print(F("T:-- H:--"));

  display.setCursor(0, 20);
  display.printf("Sang:%s Den:%s %c",
                 lightDark ? "TOI" : "SANG",
                 ledOn ? "ON" : "OFF",
                 ledAuto ? 'A' : 'M');

  display.setCursor(0, 30);
  display.printf("Quat:%s %c Gas:%s",
                 fanOn ? "ON" : "OFF",
                 fanAuto ? 'A' : 'M',
                 gasAlarm ? "BAO" : "OK");

  display.setCursor(0, 40);
  if (!isnan(bodyC)) display.printf("Chay:%s Than:%.1f", fireAlarm ? "BAO" : "OK", bodyC);
  else display.printf("Chay:%s Than:--", fireAlarm ? "BAO" : "OK");

  display.setCursor(0, 52);
  if (portalActive && tryWifi) {
    display.print(F("Dang thu WiFi..."));
  } else if (doorAutoClose) {
    uint32_t elapsed = millis() - doorOpenedAt;
    uint32_t left = (elapsed < DOOR_HOLD_MS) ? (DOOR_HOLD_MS - elapsed) / 1000 : 0;
    display.printf("Cua:MO %lus", (unsigned long)left);
  } else if (lastUid[0]) {
    display.printf("Cua:%s %s", doorAngle > 0 ? "MO" : "DONG", lastUid);
  } else if (portalActive) {
    display.print(F("192.168.4.1"));
  } else {
    display.printf("Cua:%s", doorAngle > 0 ? "MO" : "DONG");
  }
  display.display();
}

void scanBus(TwoWire& bus, const char* name) {
  Serial.printf("[I2C %s]", name);
  int n = 0;
  for (uint8_t a = 1; a < 127; a++) {
    bus.beginTransmission(a);
    if (bus.endTransmission() == 0) {
      Serial.printf(" 0x%02X", a);
      n++;
    }
  }
  if (!n) Serial.print(F(" khong thay"));
  Serial.println();
}

void checkDoubleReset() {
  if (rtcMagic == DOUBLE_RESET_MAGIC) {
    rtcMagic = 0;
    Serial.println(F("[BOOT] Reset 2 lan -> xoa WiFi, mo portal"));
    clearWifiList();
    setPortalMsg("Da xoa WiFi. Nhap mang moi.");
    startPortal();
  } else {
    rtcMagic = DOUBLE_RESET_MAGIC;
  }
}

// ── setup / loop ────────────────────────────────────────────
void setup() {
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, RELAY_OFF);
  pinMode(PIN_FAN, OUTPUT);
  digitalWrite(PIN_FAN, RELAY_OFF);
  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);
  pinMode(PIN_LDR, INPUT);
  pinMode(PIN_GAS, INPUT);
  pinMode(PIN_FIRE, INPUT_PULLUP);

  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println(F("==== SMART CLASSROOM  CLASSROOM_02 ===="));

  initDig(lightDig, PIN_LDR, LIGHT_ACTIVE_LOW, LIGHT_DB_MS);
  initDig(gasDig, PIN_GAS, GAS_ACTIVE_LOW, HAZARD_DB_MS);
  initDig(fireDig, PIN_FIRE, FIRE_ACTIVE_LOW, HAZARD_DB_MS);

  Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
  oledOK = display.begin(0x3C, true);
  if (!oledOK) oledOK = display.begin(0x3D, true);
  if (oledOK) {
    display.clearDisplay();
    display.setTextColor(SH110X_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println(F("CLASSROOM_02"));
    display.println(F("Dang khoi dong"));
    display.display();
    Serial.println(F("[OLED] SH1106 OK SDA21 SCL22"));
  } else {
    Serial.println(F("[OLED] Khong thay SH1106"));
  }

  Wire1.begin(PIN_MLX_SDA, PIN_MLX_SCL, 100000);
  Wire1.beginTransmission(0x5A);
  mlxOK = (Wire1.endTransmission() == 0);
  Serial.println(mlxOK ? F("[MLX] OK SDA16 SCL27") : F("[MLX] Khong thay - cua se tu choi"));

  scanBus(Wire, "OLED");
  scanBus(Wire1, "MLX");

  SPI.begin(PIN_SPI_SCK, PIN_SPI_MISO, PIN_SPI_MOSI, PIN_RFID_SS);
  rfid.PCD_Init();
  byte ver = rfid.PCD_ReadRegister(MFRC522::VersionReg);
  Serial.printf("[RFID] ver 0x%02X SS5 RST17\n", ver);
  if (ver == 0x00 || ver == 0xFF) Serial.println(F("[RFID] Khong thay RC522"));

  dht.begin();
  Serial.println(F("[DHT] GPIO4"));

  ESP32PWM::allocateTimer(0);
  servoDoor.setPeriodHertz(50);
  servoDoor.attach(PIN_SERVO, 500, 2400);
  servoDoor.write(DOOR_SHUT_DEG);
  Serial.println(F("[SERVO] GPIO13 goc 0"));

  loadCfg();
  ledOn = (!ledAuto && ledManualOn);
  fanOn = (!fanAuto && fanManualOn);
  writeLed(ledOn);
  writeFan(fanOn);
  Serial.printf("[MODE] Den %s | Quat %s\n", ledAuto ? "AUTO" : "MANUAL", fanAuto ? "AUTO" : "MANUAL");

  loadWifiList();
  Serial.printf("[WiFi] Da luu %d mang\n", wifiCount);
  printTopics();
  checkDoubleReset();

  if (!portalActive) {
    if (wifiCount == 0 || !connectSaved()) {
      if (wifiCount == 0) setPortalMsg("Chua co WiFi. Nhap mang 2.4GHz.");
      startPortal();
    } else {
      initMqtt();
    }
  }

  bootReadyAt = millis() + HAZARD_BOOT_MS;
  lastDht = millis();
  Serial.println(portalActive ? F("[BOOT] Portal") : F("[BOOT] Chay"));
}

void loop() {
  uint32_t now = millis();
  if (now > 3000 && rtcMagic == DOUBLE_RESET_MAGIC) rtcMagic = 0;

  if (portalActive) {
    dnsServer.processNextRequest();
    webServer.handleClient();
    portalTryLoop();
  } else if (WiFi.status() != WL_CONNECTED) {
    if (wifiDownSince == 0) wifiDownSince = now;
    if ((now - wifiDownSince) >= 1500) serviceWifiRetry();
  } else {
    wifiDownSince = 0;
    wifiRetryOn = false;
    if (!mqttInited) initMqtt();
    wsClient.loop();
    mqttClient.update();
    if (!mqttClient.isConnected() && (now - lastMqtt >= MQTT_RETRY_MS)) {
      lastMqtt = now;
      connectMqtt();
    }
    if (mqttClient.isConnected() && (now - lastHeart >= HEART_MS)) {
      lastHeart = now;
      mqttPub(CHIP_ID, "online");
      publishLedMode();
      publishFanMode();
    }
    if (mqttClient.isConnected() && (now - lastTele >= TELE_MS)) {
      lastTele = now;
      publishTemp();
      publishHumi();
      publishLight();
      publishLed();
      publishFan();
      publishGas();
      publishFire();
      publishAlarm();
      publishDoor();
      publishBody();
      Serial.printf("[IO] T=%.1f H=%.0f sang=%s gas=%d chay=%d den=%d quat=%d cua=%d than=%.1f\n",
                    isnan(tempC) ? -99 : tempC,
                    isnan(humiC) ? -99 : humiC,
                    lightDark ? "TOI" : "SANG",
                    gasAlarm ? 1 : 0,
                    fireAlarm ? 1 : 0,
                    ledOn ? 1 : 0,
                    fanOn ? 1 : 0,
                    doorAngle,
                    isnan(bodyC) ? -99 : bodyC);
    }
  }

  if (now - lastFast >= SENSOR_MS) {
    lastFast = now;
    serviceFast();
  }
  if (now - lastDht >= DHT_MS) {
    lastDht = now;
    serviceDht();
  }
  if (now - lastMlx >= MLX_MS) {
    lastMlx = now;
    serviceMlx();
  }
  if (now - lastOled >= OLED_MS) {
    lastOled = now;
    drawOled();
  }
}
