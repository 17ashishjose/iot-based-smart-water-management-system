# IoT Water Manager

Flutter app + ESP32 firmware for 5L water tank monitoring with ultrasonic sensor, solenoid valve, and pump.

## Hardware

- **ESP32 DevKit V1**
- **HC-SR04** – Ultrasonic sensor (water level)
- **12V Solenoid Valve** – Controls water flow (via relay)
- **9V DC Pump** – Fills tank (via relay)

## Automation Logic (Auto Mode)

| Water Level | Valve | Pump |
|-------------|-------|------|
| < 25%       | CLOSED (no outflow) | ON (filling) |
| 25–50%      | CLOSED | ON (filling until 50%) |
| 50–100%     | OPEN  | OFF |

Works offline: ESP32 runs the same logic locally when WiFi is down.

## Mobile App Features

- Live water level
- Flow rate (L/min) from level change
- Manual pump & valve control (manual mode)
- Master on/off switch
- Auto/Manual mode
- Low water notification (< 10%)
- History (last 10 logs)

## Supabase Setup

### 1. Create tables (or migrate existing)

**New project:**
```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  water_level INT DEFAULT 0,
  flow_rate REAL DEFAULT 0,
  pump_status BOOLEAN DEFAULT false,
  valve_status BOOLEAN DEFAULT false,
  pump_cmd BOOLEAN DEFAULT false,
  valve_cmd BOOLEAN DEFAULT false,
  device_enabled BOOLEAN DEFAULT true,
  mode TEXT DEFAULT 'auto',
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER PUBLICATION supabase_realtime ADD TABLE devices;
ALTER PUBLICATION supabase_realtime ADD TABLE activity_logs;

INSERT INTO devices (id, water_level, pump_status, valve_status, device_enabled, mode)
VALUES ('esp32-tank-1', 50, false, true, true, 'auto');
```

**Existing project** – run:
```sql
ALTER TABLE devices ADD COLUMN IF NOT EXISTS flow_rate REAL DEFAULT 0;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS valve_status BOOLEAN DEFAULT false;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS pump_cmd BOOLEAN DEFAULT false;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS valve_cmd BOOLEAN DEFAULT true;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_enabled BOOLEAN DEFAULT true;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS mode TEXT DEFAULT 'auto';
```

### 2. RLS (optional)

Enable RLS and allow anon read/write for `devices` and `activity_logs` if needed.

## ESP32 Pinout

| Component     | GPIO |
|---------------|------|
| HC-SR04 Trig  | 13   |
| HC-SR04 Echo  | 12   |
| Pump relay    | 14   |
| Valve relay   | 27   |

Use relay modules for the 12V valve and 9V pump.

## Configuration

- **Flutter** (`lib/main.dart`): Set Supabase URL and anon key.
- **ESP32** (`.ino`): Set WiFi, Supabase URL/key, and `deviceId`.

## Run

```bash
flutter pub get
flutter run
```
