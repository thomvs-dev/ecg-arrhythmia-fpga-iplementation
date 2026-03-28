# ─────────────────────────────────────────────────────────────────────────────
# ZedBoard Master Constraints File
# Project  : ECG CNN Arrhythmia Classifier
# Target   : ZedBoard Zynq-7000 (XC7Z020-CLG484-1)
# ─────────────────────────────────────────────────────────────────────────────


# ─── System Clock ─────────────────────────────────────────────────────────────
# 100 MHz onboard oscillator
set_property PACKAGE_PIN Y9       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]


# ─── Reset ────────────────────────────────────────────────────────────────────
# BTN0 — active low reset
# Press this button on ZedBoard to reset the system
set_property PACKAGE_PIN P16      [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]


# ─── UART TX ──────────────────────────────────────────────────────────────────
# Onboard USB-UART bridge (CP2102)
# Connect micro USB to your PC and open PuTTY at 115200 baud
set_property PACKAGE_PIN U19      [get_ports uart_tx]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx]


# ─── Timing Constraints ───────────────────────────────────────────────────────
# False path on reset — reset is async, no timing analysis needed
set_false_path -from [get_ports rst_n]

# False path on UART TX output — slow signal, no timing constraint needed
set_false_path -to   [get_ports uart_tx]


# ─── Bitstream Settings ───────────────────────────────────────────────────────
# Required for JTAG programming mode
set_property BITSTREAM.GENERAL.COMPRESS      TRUE  [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE     33    [current_design]
set_property CONFIG_VOLTAGE                  3.3   [current_design]
set_property CFGBVS                          VCCO  [current_design]
```

---

## What Each Section Does

**Clock** — tells Vivado the `Y9` pin is your 100MHz clock. The `create_clock` line is critical — without it Vivado can't do timing analysis and synthesis may fail.

**Reset** — maps `BTN0` (pin P16) to your `rst_n` signal. Press this button on the board to restart inference from the beginning.

**UART TX** — pin `U19` goes to the onboard CP2102 USB-UART chip which connects directly to your PC via the micro USB cable. No extra wiring needed.

**False paths** — tells Vivado not to analyse timing on reset and UART lines. Without this you may get timing violation errors during implementation even though those signals are fine.

**Bitstream settings** — `COMPRESS TRUE` reduces bitstream size for faster JTAG programming. `CONFIGRATE 33` sets programming speed. The `CONFIG_VOLTAGE` and `CFGBVS` lines are required for ZedBoard or Vivado throws a DRC warning that blocks bitstream generation.

---

## How to Add It in Vivado

1. In the Sources panel → click **"Add Sources"**
2. Select **"Add or Create Constraints"**
3. Click **"Create File"** → name it `zedboard.xdc`
4. Paste the content above
5. Click **Finish**

---

## Your Project File List Should Now Look Like This
```
Design Sources:
├── main.v
├── bram_reader.v
├── cnn_top.v
├── conv1d.v
├── maxpool.v
├── dense.v
└── uart_display.v

Constraints:
└── zedboard.xdc

Memory Files (in project folder):
├── conv1_weights.mem
├── conv1_bias.mem
├── conv2_weights.mem
├── conv2_bias.mem
├── conv3_weights.mem
├── conv3_bias.mem
├── dense1_weights.mem
├── dense1_bias.mem
├── dense2_weights.mem
├── dense2_bias.mem
├── dense3_weights.mem
├── dense3_bias.mem
└── ecg_test_samples.mem