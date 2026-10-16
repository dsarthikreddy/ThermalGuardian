<div align="center">

# Thermal Guardian

### A digital twin that predicts and prevents electrical fires in power strips

![MATLAB](https://img.shields.io/badge/MATLAB-R2017b%2B-orange)
![Toolboxes](https://img.shields.io/badge/toolboxes-none%20needed-brightgreen)
![Version](https://img.shields.io/badge/version-2-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

**One file. No hardware. No toolboxes.**

</div>

---

## The problem, in one minute

A power strip sits **under a blanket**, so heat cannot escape. At the same time, its plug works itself **loose**.

A loose plug has high resistance. Heat is `I squared R` - more resistance means more heat. The joint gets hotter, its resistance rises, and it gets hotter still. That is **thermal runaway**. It is a real cause of house fires, and nobody notices until it is too late.

**This project builds that board on a computer and adds a small safety brain that cuts the power in time.**

---

## Quick start

```matlab
ThermalGuardian
```

MATLAB R2017b or newer. Nothing else to install.

It runs for about **1 minute**, prints a plain-English report, and opens **three figure windows**.

---

## The three figures

### Figure 1 - the simple view

| Panel | What you are looking at |
|---|---|
| 1. How hot does the board get? | Green zone safe, yellow warm, red danger. Red line = no protection, green line = protected. |
| 2. Board without Guardian | A heat map at the end of the test. Red spots are hot. |
| 3. Board with Guardian | Same colours, same moment - the board is only a little warm. |
| 4. Cleaning noisy data | Grey dots = messy sensor readings. Blue = how hot the Guardian thinks it is. |
| 5. Traffic light | Green safe, yellow watch, orange slowing down, red power OFF. Black line = power going to the load. |
| 6. What happened | The whole story in words. |

### Figure 2 - the engineering view

| Panel | What you are looking at |
|---|---|
| A. Is the copper trace thick enough? | A standard IPC-2221 check. Ours passes, so the plug is the weak point, not the trace. |
| B. Cheap-chip maths = PC maths | The same filter in whole numbers (cheap chip) against decimals. They agree closely. |
| C. Fewer messages, same safety | Sending every second versus sending only when something changes. |
| D. Early-warning alarm | How the Guardian spots abnormal heating before any temperature limit is hit. |
| E. A loose plug becomes a heater | The watts being burned inside the plug. This is the actual fire starter. |
| F. Scoreboard | Every number from the main test, in one place. |

### Figure 3 - the random-house test

| Panel | What you are looking at |
|---|---|
| Top | One dot per house. Red = no Guardian, green = with Guardian. The dashed line is danger. Green dots under it mean the Guardian worked. |
| Bottom | How many minutes of warning the Guardian gave in each house. |
| Right | The full result: how many houses were dangerous with and without the Guardian, plus the honest notes. |

---

## What is inside

| # | Feature | In plain words |
|---|---|---|
| 1 | **2-D heat flow** | The board is a grid of small squares. Heat spreads between them every second. |
| 2 | **Thermal runaway** | Copper resistance rises with temperature, so hot spots get hotter by themselves. |
| 3 | **Real sensor chain** | NTC thermistor, 10-bit ADC rounding, noise, and random electrical spikes. |
| 4 | **Kalman filter** | Turns noisy readings into a clean guess of temperature and how fast it is rising. |
| 5 | **Integer-only filter** | The same filter using whole numbers - what a cheap chip without a maths unit can run. |
| 6 | **Glitch gating** | Bad readings are thrown away, and it re-locks itself if it gets stuck. |
| 7 | **CUSUM detector** | Spots heating that is faster than it should be, before any limit is crossed. |
| 8 | **Time-to-danger countdown** | Says how many minutes until the board gets dangerous. |
| 9 | **Safety state machine** | SAFE, WATCH, SLOW DOWN, POWER OFF - and it waits before relaxing, so it does not flicker on and off. |
| 10 | **Event-driven IoT** | Sends a message only when something changes, saving most of the radio traffic. |
| 11 | **IPC-2221 check** | Confirms the copper track is wide enough for the current. |
| 12 | **Firmware export** | Writes real C code (`guardian_constants.h`) for ESP32, STM32 or Arduino. |

---

## The random-house test (Figure 3)

One house proves very little, so the project tests **40 of them**.

Every house is different:

- current 6 to 12 A
- room 15 to 38 degrees C
- blanket put on at a random time
- blanket blocks 50 to 80% of cooling
- plug fault 0.05 to 0.2 ohm
- plug takes 5 to 15 minutes to loosen
- its own sensor noise

**30 of them have a faulty plug.** The other **10 are healthy**, to check the Guardian does not cry wolf.

Each house is run twice - once with the plug fault left alone, once with the Guardian active. The dots in Figure 3 are the result.

---

## What the run proves

| Check | Why it matters |
|---|---|
| Zero false alarms on a healthy board | A guard that cries wolf gets ignored |
| Power cut or slowed before danger | The whole point of the project |
| Integer maths close to decimal maths | Proves it can run on a cheap chip |
| Glitches rejected, and it re-locks | Proves it survives electrical noise |
| Fewer IoT packets, same safety | Proves the radio saving is real |
| Track width acceptable | Proves the copper is not the weak point |
| Most dangerous houses saved | Proves it works, not just in one lucky case |

---

## Honest limitations

Read this before showing the project to anyone.

- **This is a simulation using representative values.** A real product would calibrate every number with a thermal camera and a current probe.
- **Not validated against a physical board.** No real power strip was tested.
- **The random-house counts are not fully independent proof.** The thresholds were tuned on these same tests, so the numbers partly measure the tuning, not the world.
- **The Guardian sometimes slows power on faults that would not have become dangerous.** Figure 3 shows how many. That is the trade-off: a little unnecessary caution in exchange for never missing a real one.
- **One board geometry and one load style.** Real strips vary enormously.
- **The thermal model is simplified.** It ignores airflow, solder joints, and how the strip sits in real life.
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

- `ThermalGuardian_1_dashboard.png` - the simple figure
- `ThermalGuardian_2_engineering.png` - the engineering figure
- `ThermalGuardian_3_random_houses.png` - the random-house figure
- `guardian_constants.h` - the C firmware header

---

<div align="center">

Released under the MIT License.

</div>
