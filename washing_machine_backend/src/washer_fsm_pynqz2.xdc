## PYNQ-Z2 minimal constraints for washer_fsm

## 125 MHz PL clock
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -name sys_clk -period 8.000 [get_ports clk]

## Buttons
set_property PACKAGE_PIN D19 [get_ports start]
set_property IOSTANDARD LVCMOS33 [get_ports start]

set_property PACKAGE_PIN D20 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

## LEDs
## LD0
set_property PACKAGE_PIN R14 [get_ports fill_valve]
set_property IOSTANDARD LVCMOS33 [get_ports fill_valve]

## LD1
set_property PACKAGE_PIN P14 [get_ports motor]
set_property IOSTANDARD LVCMOS33 [get_ports motor]

## LD2
set_property PACKAGE_PIN N16 [get_ports pump]
set_property IOSTANDARD LVCMOS33 [get_ports pump]

## LD3
set_property PACKAGE_PIN M14 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]