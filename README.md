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

The current system is split between the Zynq Processing System (PS), the Programmable Logic (PL), and an external Godot/Dart frontend.

The VHDL FSM runs in the FPGA and exposes its current state through a 4-bit `state_code` signal. This signal is connected to an AXI GPIO peripheral, which makes the value available to the ARM Cortex-A9 processor through a memory-mapped register.

On the PYNQ-Z2 Linux side, a Python backend reads this AXI GPIO register using PYNQ MMIO. The backend decodes the raw state value, detects state transitions, and broadcasts the current FSM state to connected clients through a WebSocket server.

The Godot/Dart frontend connects to this WebSocket server and uses the received state updates to drive the washing machine visualization and animations.

End-to-end data flow:

```text
VHDL FSM
  -> state_code
  -> AXI GPIO
  -> MMIO read from Python
  -> WebSocket broadcast
  -> Godot/Dart visualization
```

The current state encoding is:

```text
0x0 -> IDLE
0x1 -> FILL
0x2 -> WASH
0x3 -> RINSE
0x4 -> SPIN
0x5 -> DONE
```

---

## Sample (Demo)

https://github.com/user-attachments/assets/21aa9df7-122b-413c-b344-21ffcb42ca82

