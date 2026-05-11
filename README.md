# Washing Machine FSM on PYNQ-Z2

A learning project focused on FPGA, VHDL and embedded systems concepts using the PYNQ-Z2 board.

The goal of this project is to progressively rebuild and modernize knowledge acquired during university, especially around:

- Finite State Machines (FSM)
- FPGA development
- Hardware description languages (VHDL)
- Digital design
- Embedded systems

---

# Project Overview

This project implements a simplified washing machine controller as a Finite State Machine (FSM).

The FSM was first implemented in Python using the PYNQ framework, then rewritten entirely in VHDL and synthesized directly onto the FPGA fabric of the PYNQ-Z2 board.

The current implementation includes:

- FSM design in VHDL
- GHDL simulation
- GTKWave waveform analysis
- Vivado synthesis and implementation
- FPGA bitstream generation
- Deployment to PYNQ-Z2
- Hardware testing using physical buttons and LEDs

---

# FSM States

The washing machine simulation currently uses the following states:

```text
IDLE
FILL
WASH
RINSE
SPIN
DONE
```

---

## Current Architecture

<img width="1600" height="951" alt="image" src="https://github.com/user-attachments/assets/6fbbdf95-37f6-4c39-a57b-1d39f1905668" />
