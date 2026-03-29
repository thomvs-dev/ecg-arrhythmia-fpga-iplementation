set_property PACKAGE_PIN Y9       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]


# ─── Reset ────────────────────────────────────────────────────────────────────
# BTN0 - active low reset
# Press this button on ZedBoard to reset the system
set_property PACKAGE_PIN P16      [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]


# ─── UART TX ──────────────────────────────────────────────────────────────────
# Onboard USB-UART bridge (CP2102)
# Connect micro USB to your PC and open PuTTY at 115200 baud
set_property PACKAGE_PIN U19      [get_ports uart_tx]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx]


# ─── Timing Constraints ───────────────────────────────────────────────────────
# False path on reset - reset is async, no timing analysis needed
set_false_path -from [get_ports rst_n]

# False path on UART TX output - slow signal, no timing constraint needed
set_false_path -to   [get_ports uart_tx]


# ─── Bitstream Settings ───────────────────────────────────────────────────────
# Required for JTAG programming mode
set_property BITSTREAM.GENERAL.COMPRESS      TRUE  [current_design]
# set_property BITSTREAM.CONFIG.CONFIGRATE     33    [current_design] 
set_property CONFIG_VOLTAGE                  3.3   [current_design]
set_property CFGBVS                          VCCO  [current_design]