## PYNQ-Z2 minimal constraints for washer_fsm

## 125 MHz PL clock
# set_property PACKAGE_PIN H16 [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]
# create_clock -name sys_clk -period 8.000 [get_ports clk]

## Buttons
set_property PACKAGE_PIN D19 [get_ports start_0]
set_property IOSTANDARD LVCMOS33 [get_ports start_0]

## set_property PACKAGE_PIN D20 [get_ports reset_0]
## set_property IOSTANDARD LVCMOS33 [get_ports reset_0]

## LEDs
## LD0
set_property PACKAGE_PIN R14 [get_ports fill_valve_0]
set_property IOSTANDARD LVCMOS33 [get_ports fill_valve_0]

## LD1
set_property PACKAGE_PIN P14 [get_ports motor_0]
set_property IOSTANDARD LVCMOS33 [get_ports motor_0]

## LD2
set_property PACKAGE_PIN N16 [get_ports pump_0]
set_property IOSTANDARD LVCMOS33 [get_ports pump_0]

## LD3
set_property PACKAGE_PIN M14 [get_ports done_led_0]
set_property IOSTANDARD LVCMOS33 [get_ports done_led_0]

## Temporary: expose state_code on physical pins
## TODO: later replace this with AXI GPIO / MMIO instead of physical pins