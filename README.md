<div align="center">

# Thermal Guardian

### A digital twin that predicts and prevents electrical fires in power strips

![MATLAB](https://img.shields.io/badge/MATLAB-R2017b%2B-orange)
![Toolboxes](https://img.shields.io/badge/toolboxes-none%20needed-brightgreen)
![Simulation](https://img.shields.io/badge/type-simulation-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

**One file. No hardware. No toolboxes.**

</div>

---

## The problem, in one minute

A power strip sits **under a blanket**, so heat cannot escape. At the same time, its plug works itself **loose**.

A loose plug has high resistance. Heat is `I squared R` - more resistance means more heat. The joint gets hotter, its resistance rises, and it gets hotter still. That is **thermal runaway**, and it is a real cause of house fires.

Nobody notices until it is too late.

**This project builds that board on a computer and adds a small safety brain that cuts the power in time.**

---

## Quick start

```matlab
ThermalGuardian
```

That's it. MATLAB R2017b or newer. Nothing else to install.

The run takes about 10 seconds, opens **two figures**, and prints a plain-English report.

---

## What happens in the test

Three boards are simulated side by side:

| Test | What it is | What happens |
|---|---|---|
| **1. Healthy board** | Normal plug, normal cooling | Must stay safe with **zero false alarms** |
| **2. Fault, no guard** | Loose plug under a blanket | The board overheats and reaches danger |
| **3. Fault, with guard** | Same fault, Guardian active | Power is cut in time; the board stays safe |

---

## How to read the graphs

**Figure 1 - the simple view:**

| Panel | What you are looking at |
|---|---|
| 1. How hot does the board get? | Red line = no protection. Green = protected. Dashed lines = danger and fire levels. |
| 2. Board without Guardian | A heat picture of the board at the end. Red spots are hot. |
| 3. Board with Guardian | Same moment, same colours - the board is barely warm. |
| 4. Cleaning noisy data | Grey dots = messy sensor readings. Blue = the Guardian's clean estimate. |
| 5. Traffic light | Green safe, yellow watch, orange slow down, red power OFF. The black line is how much power is flowing. |
| 6. What happened | The whole story written in words. |

**Figure 2 - the engineering view:**

| Panel | What you are looking at |
|---|---|
| 1. PCB trace check | Is the copper track wide enough? A standard IPC-2221 check. |
| 2. Integer vs float | The same filter in whole-number maths (cheap chip) against decimal maths. The gap is measured. |
| 3. IoT packets | Sending every second versus sending only when it matters. |
| 4. CUSUM detector | How the guard spots abnormal heating early. |
| 5. Countdown | How many minutes are left before the board gets dangerous. |
| 6. Scoreboard | Every number from all three tests, in one place. |

---

## What is inside

| # | Feature | In plain words |
|---|---|---|
| 1 | **2-D heat flow** | The board is a grid of small squares. Heat spreads between them each second. |
| 2 | **Thermal runaway** | Copper resistance rises with temperature, so hot spots get hotter by themselves. |
| 3 | **Real sensor chain** | NTC thermistor, 10-bit ADC rounding, noise, and random electrical spikes. |
| 4 | **Kalman filter** | Turns noisy readings into a clean estimate of temperature and how fast it is rising. |
| 5 | **Integer-only filter** | The same filter using whole numbers only - what a cheap chip without a maths unit can run. |
| 6 | **Glitch gating** | Bad readings are thrown away, and it re-locks automatically if it gets stuck. |
| 7 | **CUSUM detector** | Spots heating that is faster than it should be, before any threshold is crossed. |
| 8 | **Time-to-danger countdown** | Says how many minutes until the board gets dangerous. |
| 9 | **Safety state machine** | SAFE, WATCH, SLOW DOWN, CUT OFF - with hysteresis so it does not flap. |
| 10 | **IoT reporting** | Sends a message only when something changes, saving most of the radio traffic. |
| 11 | **IPC-2221 check** | Confirms the copper track is wide enough for the current. |
| 12 | **Firmware export** | Writes real C code (`guardian_constants.h`) for ESP32, STM32 or Arduino. |

---

## What the run proves

| Check | Why it matters |
|---|---|
| Zero false alarms on a healthy board | A guard that cries wolf gets ignored |
| Power cut before danger | The whole point of the project |
| Integer maths close to decimal maths | Proves it can run on a cheap chip |
| Glitches rejected, and it re-locks | Proves it survives electrical noise |
| Fixed IoT reduction | Proves the radio saving is real |
| Track width acceptable | Proves the copper is not the weak point |

---

## Honest limitations

Read this before showing the project to anyone.

- **This is a simulation using representative values.** A real product would calibrate every number with a thermal camera and a current probe.
- **Not validated against a physical board.** No real power strip was tested.
- **One board geometry and one load.** Real strips vary enormously.
- **The thermal model is simplified.** It ignores airflow, solder joints, and how the strip sits.
- **The generated C code is a starting point.** It has not been compiled or flashed onto a real chip.
- **Not a safety-certified device.** This is a demonstration of the engineering method, not a product.

---

## Files

```
ThermalGuardian/
|-- ThermalGuardian.m        The whole project in one file
|-- README.md
|-- LICENSE
|-- .gitignore
```

Running it also creates:

- `ThermalGuardian_dashboard.png` - the simple figure
- `ThermalGuardian_engineering.png` - the engineering figure
- `guardian_constants.h` - the C firmware header

---

<div align="center">

Released under the MIT License.

</div>
