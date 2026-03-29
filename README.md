# ECG Arrhythmia Classification on FPGA using 1D-CNN

> **BITS Pilani FPGA Hackathon** — A fully hardware-accelerated Convolutional Neural Network for real-time cardiac arrhythmia detection, deployed entirely on FPGA Programmable Logic without any ARM processor dependency.

---

## Abstract

This project implements a **1D Convolutional Neural Network (CNN)** entirely in synthesizable Verilog HDL on the **Xilinx ZedBoard (Zynq-7000 XC7Z020)** for real-time classification of cardiac arrhythmias from single-lead ECG signals. The complete inference pipeline — three convolutional layers, three max-pooling layers with ReLU activations, and three fully connected dense layers — runs exclusively on the **Programmable Logic (PL) fabric** at 100 MHz, requiring zero software intervention from the ARM Cortex-A9 Processing System.

Pre-trained model weights, quantized to 8-bit signed integers, are loaded into on-chip Block RAM at synthesis time via `.mem` files. The system ingests 186-sample ECG heartbeat segments from the **MIT-BIH Arrhythmia Database**, classifies each into one of five arrhythmia categories, and transmits human-readable results over **UART (115200 baud)** to a PC terminal — making it a fully self-contained, edge-deployable arrhythmia detector.

---

## Domain

**Biomedical Signal Processing · Embedded AI/ML · Digital VLSI Design**

This project sits at the intersection of healthcare electronics and embedded machine learning. It demonstrates how deep learning models trained in software (Keras/TensorFlow) can be ported to dedicated FPGA hardware for low-latency, low-power inference — a critical requirement in wearable and point-of-care medical devices.

---

## What the Project Evaluates

The system classifies each incoming ECG heartbeat (a 186-sample segment) into one of **five arrhythmia classes** based on the MIT-BIH Arrhythmia Database (PhysioNet) annotations:

| Class | Label                    | Description                               |
|:-----:|--------------------------|-------------------------------------------|
|   0   | **Normal (N)**           | Normal sinus rhythm beat                  |
|   1   | **Supraventricular (S)** | Supraventricular premature beat           |
|   2   | **Ventricular (V)**      | Premature ventricular contraction         |
|   3   | **Fusion (F)**           | Fusion of ventricular and normal beat     |
|   4   | **Unknown (Q)**          | Unclassifiable beat                       |

The evaluation demonstrates that a quantized 1D-CNN implemented purely in FPGA fabric can achieve real-time heartbeat classification, validating the feasibility of deploying neural networks on resource-constrained hardware for cardiac monitoring applications.

---

## System Architecture

```
┌──────────────┐     ┌───────────────────────────────────┐     ┌──────────────┐
│  BRAM Reader │────▶│           CNN Top (FSM)           │────▶│ UART Display │──▶ PC Terminal
│  (ECG Data)  │     │  Conv → Pool → Dense → Argmax    │     │ (115200 baud)│    (PuTTY)
└──────────────┘     └───────────────────────────────────┘     └──────────────┘
```

### CNN Pipeline

```
Input (186 × 8-bit signed samples)
  │
  ├─▶ Conv1D  (32 filters, kernel=5)   →  ReLU  →  MaxPool (size=3, stride=2)
  │
  ├─▶ Conv1D  (64 filters, kernel=3)   →  ReLU  →  MaxPool (size=3, stride=2)
  │
  ├─▶ Conv1D  (128 filters, kernel=3)  →  ReLU  →  MaxPool (size=2, stride=2)
  │
  ├─▶ Flatten (2944 neurons)
  │
  ├─▶ Dense1  (2944 → 64)   →  ReLU
  │
  ├─▶ Dense2  (64 → 32)     →  ReLU
  │
  └─▶ Dense3  (32 → 5)      →  Argmax  →  Classification Result (0–4)
```

---

## Module Descriptions

| Module           | File              | Role                                                                         |
|------------------|-------------------|------------------------------------------------------------------------------|
| **main**         | `main.v`          | Top-level integration; wires BRAM reader, CNN, and UART together             |
| **bram_reader**  | `bram_reader.v`   | Reads 930 pre-loaded ECG test samples from Block RAM at a controlled rate    |
| **cnn_top**      | `cnn_top.v`       | 9-state FSM orchestrator; manages the full Conv → Pool → Dense pipeline      |
| **conv1d**       | `conv1d.v`        | Parameterized 1D convolution with pipelined BRAM reads, DSP48 MAC, and ReLU |
| **maxpool**      | `maxpool.v`       | Parameterized 1D max pooling with configurable window size and stride        |
| **dense**        | `dense.v`         | Fully connected layer with pipelined BRAM weight reads, DSP48 MAC, and ReLU |
| **uart_display** | `uart_display.v`  | Full UART 8N1 transmitter (115200 baud); sends human-readable class labels   |

---

## Critical Engineering Challenges Solved

### 1. Port Interface Flattening — Synthesis Error Fix
**Problem:** Original code used 2D unpacked arrays (e.g., `input signed [7:0] signal_in [0:185]`) on module ports. Vivado's Verilog-2001 synthesizer throws `[Synth 8-9210]` because unpacked structures cannot cross pure Verilog module boundaries.

**Solution:** All inter-module interfaces in `cnn_top`, `conv1d`, `maxpool`, and `dense` were refactored to use **packed 1D bit-vectors** (`data_in_flat`). Inside each module, `generate` loop blocks seamlessly pack/unpack the vectors into internal 2D arrays, preserving human-readable `[index]` accessibility within the logic.

### 2. Dynamic Component Parameterization
**Problem:** `conv1d.v` originally hardcoded `conv1_weights.mem` inside `$readmemh`, preventing code reuse for conv2 and conv3.

**Solution:** Memory files were abstracted into `parameter WEIGHT_FILE` and `parameter BIAS_FILE` strings, allowing `cnn_top.v` to instantiate the same `conv1d.v` block three times with different weight files (`conv1_weights.mem`, `conv2_weights.mem`, `conv3_weights.mem`), creating a clean topological cascade.

### 3. Synchronous Pipelining — BRAM Inference Fix
**Problem:** Original architecture used asynchronous combinational indexing (`wire current_weight = weights[index]`). Vivado cannot synthesize combinational reads into Block RAM — instead it mapped **188,416 weights** into distributed RAM (LUT multiplexers), causing a massive **−11ns WNS timing violation** at 100 MHz.

**Solution:** All memory access was transitioned to a **synchronous pipeline** with registered reads:
```verilog
always @(posedge clk) begin
    weight_reg <= weights[weight_idx];
end
```
This allowed Vivado to correctly infer dedicated Block RAM primitives, resolving the routing nightmare and cleanly meeting the 10ns timing constraint.

### 4. DSP48E1 Synchronous Reset Optimization
**Problem:** Vivado flagged **144 Methodology Warnings (DPIR-#)**. The DSP48 hardware slices on Zynq-7000 contain strictly synchronous registers, but the MAC FSM used asynchronous reset (`always @(posedge clk or negedge rst_n)`). Vivado pulled accumulators out of DSP48 slices onto generic flip-flops.

**Solution:** Converted to standard synchronous reset (`always @(posedge clk)`), ensuring 100% of multiply-accumulate logic gets natively packed inside DSP48 blocks — improving Fmax and saving routing resources.

### 5. REQP-1962 Cascaded BRAM Placer Fix
**Problem:** During Place & Route, Vivado crashed with `[DRC REQP-1962]` on the dense1 memory block. The `weight_idx` address register had enormous fanout, causing Vivado's optimizer to illegally replicate the register, violating the rule that cascaded BRAMs must share identical source address pins.

**Solution:** Injected a synthesis directive to prevent register replication:
```verilog
(* keep = "true" *) reg [19:0] weight_idx;
```
This forced Vivado to route a single unified address bus across all cascaded BRAM blocks, completely resolving the Placer failure.

---

## Weight Files

All weights are quantized to **signed 8-bit integers** and exported as hex `.mem` files:

| File                   | Layer   | Size (entries)            |
|------------------------|---------|---------------------------|
| `conv1_weights.mem`    | Conv1   | 32 × 5 = 160             |
| `conv1_bias.mem`       | Conv1   | 32                        |
| `conv2_weights.mem`    | Conv2   | 64 × 3 = 192 (×channels) |
| `conv2_bias.mem`       | Conv2   | 64                        |
| `conv3_weights.mem`    | Conv3   | 128 × 3 = 384 (×channels)|
| `conv3_bias.mem`       | Conv3   | 128                       |
| `dense1_weights.mem`   | Dense1  | 2944 × 64 = 188,416      |
| `dense1_bias.mem`      | Dense1  | 64                        |
| `dense2_weights.mem`   | Dense2  | 64 × 32 = 2,048          |
| `dense2_bias.mem`      | Dense2  | 32                        |
| `dense3_weights.mem`   | Dense3  | 32 × 5 = 160             |
| `dense3_bias.mem`      | Dense3  | 5                         |
| `ecg_test_samples.mem` | Input   | 930 (5 beats × 186)      |

---

## Target Platform

| Item         | Specification                              |
|--------------|--------------------------------------------|
| **Board**    | Xilinx ZedBoard (Zynq-7000 SoC, XC7Z020)  |
| **Clock**    | 100 MHz system clock (Y9 pin)              |
| **Reset**    | Active-low pushbutton (BTN0, P16 pin)      |
| **UART**     | Onboard CP2102 USB-UART bridge (U19 pin)   |
| **Toolchain**| Xilinx Vivado Design Suite                 |
| **Baud Rate**| 115200, 8N1                                |

---

## Repository Structure

```
ecg-arrhythmia-fpga-implementation/
├── verilog_ecg.xpr                          # Vivado project file
├── verilog_ecg.srcs/
│   ├── sources_1/new/
│   │   ├── main.v                           # Top-level integration
│   │   ├── bram_reader.v                    # ECG sample reader from Block RAM
│   │   ├── cnn_top.v                        # CNN pipeline controller (9-state FSM)
│   │   ├── conv1d.v                         # 1D convolution (parameterized, pipelined)
│   │   ├── maxpool.v                        # Max pooling layer
│   │   ├── dense.v                          # Fully connected layer (pipelined BRAM)
│   │   ├── uart_display.v                   # UART transmitter for result display
│   │   ├── conv[1-3]_weights.mem            # Convolution layer weights (Int8 hex)
│   │   ├── conv[1-3]_bias.mem               # Convolution layer biases
│   │   ├── dense[1-3]_weights.mem           # Dense layer weights (Int8 hex)
│   │   ├── dense[1-3]_bias.mem              # Dense layer biases
│   │   └── ecg_test_samples.mem             # 5 test ECG beats (930 samples)
│   └── constrs_1/new/
│       └── zedboard.xdc                     # Pin assignments & timing constraints
├── verilog_ecg.runs/                        # Synthesis & implementation results
└── README.md
```

---

## How to Use

1. **Train & Export Weights** — Train the 1D-CNN model in Python (Keras/TensorFlow) on the MIT-BIH dataset, quantize weights to Int8, and export as `.mem` files in 2-digit hex format.
2. **Prepare Test Data** — Extract ECG test samples and save as `ecg_test_samples.mem`.
3. **Open Project** — Open `verilog_ecg.xpr` in Vivado.
4. **Synthesize & Implement** — Run Synthesis → Implementation → Generate Bitstream.
5. **Program FPGA** — Flash the bitstream to the ZedBoard via JTAG.
6. **View Results** — Open PuTTY at **115200 baud, 8N1** on the ZedBoard's USB-UART COM port.

**Expected terminal output:**
```
Beat: NORMAL (0)
Beat: VENTRICULAR (2)
Beat: FUSION (3)
Beat: NORMAL (0)
Beat: SUPRAVENTRICULAR (1)
```

---

## License

This project is licensed under the [MIT License](LICENSE).
