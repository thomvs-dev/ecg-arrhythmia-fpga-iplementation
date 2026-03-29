set_property PACKAGE_PIN Y9       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]


# ─── Reset ────────────────────────────────────────────────────────────────────
# ─── Reset ────────────────────────────────────────────────────────────────────
# BTNC (center button) — press to RESET the system
# Inverted inside main.v (button HIGH = reset active)
set_property PACKAGE_PIN P16      [get_ports rst_btn]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_btn]

# BTNU (up button) - press to cycle through results
set_property PACKAGE_PIN T18      [get_ports btn_next]
set_property IOSTANDARD  LVCMOS33 [get_ports btn_next]


# ─── UART TX ──────────────────────────────────────────────────────────────────
# NOTE: ZedBoard USB-UART (J14) is on PS MIO pins, NOT accessible from PL.
# This pin goes to PMOD JE1 — connect an external USB-UART adapter here.
set_property PACKAGE_PIN V12      [get_ports uart_tx]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx]


# ─── LEDs ─────────────────────────────────────────────────────────────────────
# 8 onboard user LEDs (LD0–LD7)
# LED[2:0] = class result, LED[5:3] = beat number (1-5)
# LED[6] = all 5 done, LED[7] = heartbeat blink
set_property PACKAGE_PIN T22      [get_ports {led[0]}]
set_property PACKAGE_PIN T21      [get_ports {led[1]}]
set_property PACKAGE_PIN U22      [get_ports {led[2]}]
set_property PACKAGE_PIN U21      [get_ports {led[3]}]
set_property PACKAGE_PIN V22      [get_ports {led[4]}]
set_property PACKAGE_PIN W22      [get_ports {led[5]}]
set_property PACKAGE_PIN U19      [get_ports {led[6]}]
set_property PACKAGE_PIN U14      [get_ports {led[7]}]

set_property IOSTANDARD LVCMOS33  [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33  [get_ports {led[7]}]


# ─── Timing Constraints ───────────────────────────────────────────────────────
set_false_path -from [get_ports rst_btn]
set_false_path -from [get_ports btn_next]
set_false_path -to   [get_ports uart_tx]
set_false_path -to   [get_ports {led[*]}]


# ─── Bitstream Settings ───────────────────────────────────────────────────────
set_property BITSTREAM.GENERAL.COMPRESS      TRUE  [current_design]
set_property CONFIG_VOLTAGE                  3.3   [current_design]
set_property CFGBVS                          VCCO  [current_design]