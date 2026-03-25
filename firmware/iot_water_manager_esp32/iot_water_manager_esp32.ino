#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>

const char* ssid             = "Ashiis iPhone";
const char* pass             = "12345678910";
const char* SUPABASE_URL     = "https://rpumtokaszpqwkscungk.supabase.co";
const char* SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwdW10b2thc3pwcXdrc2N1bmdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3Mzc3MTAsImV4cCI6MjA4OTMxMzcxMH0.-bhyXpGhZoCNQ11xxMPxA8_1qqVI2WLY_N7VbUOOejo";
const char* DEVICE_ID        = "esp32-tank-1";

#define TRIG_PIN       5
#define ECHO_PIN       18
#define PUMP_RELAY_PIN 14
#define RELAY_ACTIVE_LOW 1

const int EMPTY_CM = 17;
const int FULL_CM  = 5;
const int PUMP_ON_LEVEL  = 20;
const int PUMP_OFF_LEVEL = 100;

const unsigned long UPDATE_MS = 5000;
unsigned long lastUpdate = 0;

bool pumpRunning   = false;
bool pumpCmd       = false;
bool deviceEnabled = true;
String mode        = "auto";
int waterLevel     = 0;

void setPump(bool on) {
  pumpRunning = on;
  digitalWrite(PUMP_RELAY_PIN, (RELAY_ACTIVE_LOW == 1) ? !on : on);
  Serial.printf("[PUMP] Pump is now %s\n", on ? "ON" : "OFF");
}

void connectWiFi() {
  Serial.printf("[WIFI] Connecting to %s", ssid);
  WiFi.begin(ssid, pass);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WIFI] Connected! IP: %s\n",
                  WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\n[WIFI] Failed — running offline");
  }
}

int readWaterLevel() {
  int readings[5];
  int valid = 0;
  Serial.println("[SENSOR] --- Reading water level ---");
  for (int i = 0; i < 5; i++) {
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    long duration = pulseIn(ECHO_PIN, HIGH, 30000);
    if (duration == 0) {
      Serial.printf("  [%d] timeout — no echo received\n", i);
      delay(50);
      continue;
    }
    int distCm = (int)(duration * 0.034 / 2);
    if (distCm < 0 || distCm > 400) {
      Serial.printf("  [%d] out-of-range dist=%dcm (duration=%ld µs)\n", i, distCm, duration);
      delay(50);
      continue;
    }
    int level = map(distCm, EMPTY_CM, FULL_CM, 0, 100);
    readings[valid] = constrain(level, 0, 100);
    Serial.printf("  [%d] duration=%ld µs  dist=%dcm  level=%d%%\n",
                  i, duration, distCm, readings[valid]);
    valid++;
    delay(50);
  }
  if (valid == 0) {
    Serial.printf("[SENSOR] All readings failed! Check wiring. TRIG=%d ECHO=%d\n",
                  TRIG_PIN, ECHO_PIN);
    Serial.printf("[SENSOR] Returning last known level: %d%%\n", waterLevel);
    return waterLevel;
  }
  // Bubble-sort then take median
  for (int i = 0; i < valid - 1; i++)
    for (int j = i + 1; j < valid; j++)
      if (readings[i] > readings[j]) {
        int tmp = readings[i];
        readings[i] = readings[j];
        readings[j] = tmp;
      }
  int result = readings[valid / 2];
  Serial.printf("[SENSOR] Median level = %d%% (from %d valid readings)\n", result, valid);
  return result;
}

void runAutomation() {
  if (!deviceEnabled) { setPump(false); return; }
  if (mode == "auto") {
    if (waterLevel <= PUMP_ON_LEVEL && !pumpRunning) {
      Serial.println("[AUTO] Level <= 20% — Pump ON");
      setPump(true);
    } else if (waterLevel >= PUMP_OFF_LEVEL && pumpRunning) {
      Serial.println("[AUTO] Tank full — Pump OFF");
      setPump(false);
    }
  } else {
    if (pumpCmd != pumpRunning) setPump(pumpCmd);
  }
}

void pullCommands() {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SUPABASE_URL)
    + "/rest/v1/devices?id=eq." + DEVICE_ID
    + "&select=pump_cmd,device_enabled,mode";
  http.begin(url);
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  int code = http.GET();
  if (code == 200) {
    String body = http.getString();
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, body);
    if (!err && doc.is<JsonArray>() && doc.as<JsonArray>().size() > 0) {
      JsonObject row = doc[0];
      pumpCmd       = row["pump_cmd"]       | false;
      deviceEnabled = row["device_enabled"] | true;
      mode          = row["mode"]           | "auto";
      Serial.printf("[PULL] mode=%s enabled=%d pump_cmd=%d\n",
                    mode.c_str(), deviceEnabled, pumpCmd);
    }
  } else {
    Serial.printf("[PULL] HTTP error %d\n", code);
  }
  http.end();
}

// Returns current UTC time as ISO 8601 string, e.g. "2026-03-19T06:47:01Z"
String getIsoTimestamp() {
  time_t now = time(nullptr);
  if (now < 1000000000UL) {
    // NTP not synced yet — fall back to millis-based placeholder
    return String("1970-01-01T00:00:00Z");
  }
  struct tm t;
  gmtime_r(&now, &t);
  char buf[25];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           t.tm_year + 1900, t.tm_mon + 1, t.tm_mday,
           t.tm_hour, t.tm_min, t.tm_sec);
  return String(buf);
}

void pushTelemetry() {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SUPABASE_URL)
    + "/rest/v1/devices?id=eq." + DEVICE_ID;
  JsonDocument doc;
  doc["water_level"] = waterLevel;
  doc["pump_status"] = pumpRunning;
  doc["flow_rate"]   = 0.0;
  doc["updated_at"]  = getIsoTimestamp();
  String body;
  serializeJson(doc, body);
  http.begin(url);
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");
  int code = http.PATCH(body);
  Serial.printf("[PUSH] level=%d%% pump=%s updated_at=%s -> HTTP %d\n",
                waterLevel, pumpRunning ? "ON" : "OFF",
                getIsoTimestamp().c_str(), code);
  http.end();
  delay(100);
}

void setup() {
  Serial.begin(115200);
  delay(500);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(PUMP_RELAY_PIN, OUTPUT);
  setPump(false);
  Serial.println("\n[BOOT] IoT Water Manager starting...");
  connectWiFi();
  // Sync time via NTP so updated_at timestamps are accurate
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("[NTP] Syncing time");
  time_t now = time(nullptr);
  int ntpAttempts = 0;
  while (now < 1000000000UL && ntpAttempts < 20) {
    delay(500);
    Serial.print(".");
    now = time(nullptr);
    ntpAttempts++;
  }
  Serial.printf(" done (epoch=%lu)\n", now);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Reconnecting...");
    connectWiFi();
  }
  if (millis() - lastUpdate >= UPDATE_MS) {
    lastUpdate = millis();
    waterLevel = readWaterLevel();
    Serial.printf("[SENSOR] Water level: %d%%\n", waterLevel);
    pullCommands();
    runAutomation();
    pushTelemetry();
  }
  delay(50);
}