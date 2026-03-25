# IoT Water Manager – Wiring Guide

A step-by-step guide to connect all components on your zero board. **Read fully before soldering.** Mistakes are hard to fix once soldered.

---

## Before You Start

1. **Double-check** every connection before soldering.
2. **Label** wires with tape (e.g. "Trig", "Pump relay") so you don’t mix them.
3. **Power off** whenever you add or change wires.
4. Use **different wire colours** for power (red 5V, black GND) and signals.

---

## Power Flow (Simplified)

```
12V Adapter
    │
    ├──► LM2596 Buck ──► 9V  ──► Pump + Valve (via relay outputs)
    │
    └──► 5V Buck ──────► 5V  ──► ESP32, HC-SR04, Relay Module, Level Shifter
```

---

## Connection Table

Use this as the main reference. Row = FROM, Column = TO.

### Power connections

| FROM | TO | Wire |
|------|-----|------|
| 12V Adapter (+) | LM2596 IN+ | Red |
| 12V Adapter (-) | LM2596 IN- | Black |
| LM2596 OUT+ (9V) | Relay COM pins (for pump & valve power) | Red |
| 12V Adapter (+) | 5V Buck IN+ | Red |
| 12V Adapter (-) | 5V Buck IN- | Black |
| 5V Buck OUT+ | ESP32 5V, HC-SR04 VCC, Relay VCC, Level Shifter HV & LV VCC | Red |
| 5V Buck OUT- | Common GND rail | Black |
| Common GND | ESP32 GND, HC-SR04 GND, Relay GND, Level Shifter GND | Black |

### HC-SR04 (Ultrasonic) via level shifter

| HC-SR04 Pin | Level Shifter | Level Shifter | ESP32 |
|-------------|---------------|---------------|-------|
| VCC | — | — | (use 5V from buck) |
| GND | — | — | (use GND rail) |
| Trig | HV1 IN | LV1 OUT | **GPIO 13** |
| Echo | HV2 OUT | LV2 IN | **GPIO 12** |

*Level shifter HV side = 5V, LV side = 3.3V. Connect HV VCC to 5V, LV VCC to 3.3V (or ESP32 3.3V).*

### Relay module

| Relay Module Pin | Connect To |
|------------------|------------|
| VCC | 5V (from 5V buck) |
| GND | GND rail |
| IN1 | ESP32 **GPIO 14** (pump) |
| IN2 | ESP32 **GPIO 27** (valve) |
| COM1 | 9V+ (from LM2596) |
| NO1 | Pump (+) |
| COM2 | 12V+ (from adapter, if valve is 12V) or 9V+ |
| NO2 | Valve (+) |

*Pump and valve (-) go to GND.*

### ESP32 pin summary

| ESP32 Pin | Connects To | Purpose |
|-----------|-------------|---------|
| 3.3V | Level shifter LV VCC | 3.3V supply for shifter |
| 5V | (optional – ESP32 can use USB or 5V) | Power |
| GND | GND rail | Ground |
| GPIO 12 | Level shifter LV2 (Echo) | Water level echo |
| GPIO 13 | Level shifter LV1 (Trig) | Ultrasonic trigger |
| GPIO 14 | Relay IN1 | Pump control |
| GPIO 27 | Relay IN2 | Valve control |

---

## Step-by-Step Wiring

### Step 1: Power section

1. Solder a **GND rail** along one edge of the board.
2. Solder 12V adapter wires to the board (mark + and -).
3. Connect 12V+ and 12V- to the LM2596 input. Adjust LM2596 to **9V** output.
4. Connect 12V+ and 12V- to the 5V buck input. Check 5V buck output is **5V**.
5. Connect LM2596 OUT- and 5V buck OUT- to the GND rail.
6. Connect 5V buck OUT+ to a **5V rail** (or distribution point).

### Step 2: Level shifter (for ultrasonic)

1. Mount the 4-channel level shifter.
2. **HV side**: HV VCC → 5V, HV GND → GND.
3. **LV side**: LV VCC → 3.3V (ESP32 3.3V pin), LV GND → GND.
4. Channels used: HV1/LV1 (Trig), HV2/LV2 (Echo).

### Step 3: HC-SR04

1. HC-SR04 **VCC** → 5V rail.
2. HC-SR04 **GND** → GND rail.
3. HC-SR04 **Trig** → Level shifter **HV1 IN** (or HV1).
4. HC-SR04 **Echo** → Level shifter **HV2 OUT** (or HV2).

*HV IN/OUT labels depend on your shifter. HV1 connects Trig, HV2 connects Echo. Check your module datasheet.*

### Step 4: Level shifter to ESP32

1. Level shifter **LV1 OUT** → ESP32 **GPIO 13** (Trig).
2. Level shifter **LV2 IN** (from Echo side) → ESP32 **GPIO 12** (Echo).

### Step 5: Relay module

1. Relay **VCC** → 5V.
2. Relay **GND** → GND.
3. Relay **IN1** → ESP32 **GPIO 14**.
4. Relay **IN2** → ESP32 **GPIO 27**.
5. Relay **COM1** → 9V+ (LM2596).
6. Relay **NO1** → Pump (+) wire.
7. Relay **COM2** → 12V+ or 9V+ (depending on valve voltage).
8. Relay **NO2** → Valve (+) wire.
9. Pump (-) and Valve (-) → GND.

### Step 6: ESP32 power

1. ESP32 **5V** (or VIN) → 5V rail.
2. ESP32 **GND** → GND rail.

---

## Simple “What Goes Where” Overview

```
┌─────────────────┐
│  12V Adapter    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐  ┌───────┐
│ LM2596│  │ 5V Buck│
│  →9V  │  │  →5V   │
└───┬───┘  └───┬───┘
    │          │
    │     ┌────┼────┬────────┬──────────┐
    │     │    │    │        │          │
    │     ▼    ▼    ▼        ▼          ▼
    │   ESP32 5V  HC-SR04  Relay    Level Shifter
    │   + GND     VCC,GND  VCC,GND   HV,LV VCC,GND
    │
    │   Relay COM/NO ──► Pump & Valve
    │
    └──► 9V to relay COM (pump/valve power)

ESP32 GPIO 13 ──► Level Shifter ──► HC-SR04 Trig
ESP32 GPIO 12 ◄── Level Shifter ◄── HC-SR04 Echo
ESP32 GPIO 14 ──► Relay IN1 (Pump)
ESP32 GPIO 27 ──► Relay IN2 (Valve)
```

---

## Checks Before Power-On

- [ ] No short between 12V/9V/5V and GND
- [ ] Level shifter HV = 5V, LV = 3.3V
- [ ] HC-SR04 Echo goes through level shifter (do not connect Echo directly to ESP32)
- [ ] Relay IN1/IN2 go to GPIO 14 and 27
- [ ] Pump and valve polarity correct

---

## Important Notes

1. **Level shifter**: Protects ESP32 from the HC-SR04 5V echo signal. Use it as shown.
2. **Relay COM/NO**: COM = common, NO = normally open. When the relay is on, COM and NO are connected.
3. **Valve voltage**: If your solenoid is 12V, supply COM2 from 12V. If it can work on 9V, you can use 9V from the LM2596.
4. **Female headers**: Solder headers to the board and plug the ESP32 into them so you can replace it if needed.

---

## Quick Reference – Pin Summary

| Component | Pin | Wire To |
|-----------|-----|---------|
| ESP32 | GPIO 12 | Level shifter LV (Echo) |
| ESP32 | GPIO 13 | Level shifter LV (Trig) |
| ESP32 | GPIO 14 | Relay IN1 (Pump) |
| ESP32 | GPIO 27 | Relay IN2 (Valve) |
| HC-SR04 | Trig | Level shifter HV |
| HC-SR04 | Echo | Level shifter HV |
| Relay | IN1 | ESP32 GPIO 14 |
| Relay | IN2 | ESP32 GPIO 27 |
