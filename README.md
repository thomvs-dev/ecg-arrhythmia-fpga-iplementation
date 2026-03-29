# ECG Arrhythmia Classification on FPGA using 1D-CNN

## Abstract

This project presents a hardware-level implementation of a **1D Convolutional Neural Network (CNN)** on an **FPGA** for real-time classification of cardiac arrhythmias from single-lead ECG signals. The CNN architecture—comprising three convolutional layers, max-pooling layers, ReLU activations, and a fully connected dense layer—is implemented entirely in synthesizable Verilog HDL, targeting the **Xilinx ZedBoard (Zynq-7000)**. Pre-trained model weights (quantized to 8-bit integers) are loaded from memory files into on-chip Block RAM at synthesis time, enabling inference without any software or processor intervention. Classification results are transmitted over **UART** to a PC terminal for real-time monitoring, making the system a fully self-contained, edge-deployable arrhythmia detector.

## Domain

**Biomedical Signal Processing · Embedded AI · Digital VLSI Design**

This project sits at the intersection of healthcare electronics and embedded machine learning. It demonstrates how deep learning models trained in software (e.g., Keras/TensorFlow) can be ported to dedicated hardware for low-latency, low-power inference—a critical requirement in wearable and point-of-care medical devices.

## What the Project Evaluates

The system classifies each incoming ECG heartbeat (a 187-sample segment) into one of **five arrhythmia classes** based on the MIT-BIH Arrhythmia Database annotations:

| Class | Label               | Description                                  |
|:-----:|----------------------|----------------------------------------------|
|   0   | **Normal (N)**       | Normal sinus rhythm beat                     |
|   1   | **Supraventricular (S)** | Supraventricular premature beat          |
|   2   | **Ventricular (V)**  | Premature ventricular contraction            |
|   3   | **Fusion (F)**       | Fusion of ventricular and normal beat        |
|   4   | **Unknown (Q)**      | Unclassifiable beat                          |

The evaluation demonstrates that a quantized CNN implemented purely in FPGA fabric can achieve real-time heartbeat classification, validating the feasibility of deploying neural networks on resource-constrained hardware for cardiac monitoring applications.

## Architecture Overview

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  BRAM Reader │────▶│   CNN Top    │────▶│ UART Display │───▶ PC Terminal
│  (ECG Data)  │     │  (Inference) │     │  (115200 bd) │    (PuTTY)
└──────────────┘     └──────────────┘     └──────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
    ┌───────────┐     ┌───────────┐     ┌───────────┐
    │  Conv1D   │     │  MaxPool  │     │   Dense   │
    │  Layer    │     │  Layer    │     │   Layer   │
    └───────────┘     └───────────┘     └───────────┘
```

### CNN Pipeline

```
Input (187 × 8-bit samples)
  │
  ├─▶ Conv1D (32 filters, kernel=5)  →  ReLU  →  MaxPool (3/2)
  │
  ├─▶ Conv1D (64 filters, kernel=3)  →  ReLU  →  MaxPool (3/2)
  │
  ├─▶ Conv1D (128 filters, kernel=3) →  ReLU  →  MaxPool (2/2)
  │
  ├─▶ Flatten (2944 neurons)
  │
  └─▶ Dense (2944 → 5 classes)  →  Argmax  →  Classification Result
```

## Module Descriptions

| Module           | File              | Role                                                                 |
|------------------|-------------------|----------------------------------------------------------------------|
| **main**         | `main.v`          | Top-level module; wires BRAM reader, CNN, and UART together          |
| **bram_reader**  | `bram_reader.v`   | Reads pre-loaded ECG test samples from Block RAM at a controlled rate |
| **cnn_top**      | `cnn_top.v`       | FSM-based CNN controller; orchestrates conv → pool → dense pipeline  |
| **conv1d**       | `conv1d.v`        | Parameterized 1D convolution with DSP48 MAC inference and ReLU       |
| **maxpool**      | `maxpool.v`       | Parameterized 1D max pooling with configurable window size and stride |
| **dense**        | `dense.v`         | Fully connected layer with DSP48 MAC, bias addition, and ReLU        |
| **uart_display** | `uart_display.v`  | UART transmitter (115200 baud, 8N1); sends human-readable labels     |

## Key Design Decisions

- **Int8 Quantization** — All weights are quantized to signed 8-bit integers, matching Xilinx DSP48 slice input widths for efficient multiply-accumulate operations.
- **Block RAM Storage** — Weights, biases, and test ECG data are loaded into BRAM via `$readmemh` at synthesis time, eliminating the need for external memory or a processor.
- **FSM-Driven Dataflow** — Each layer operates as a finite state machine, with handshake signals (`start`/`done`) ensuring correct sequential execution through the pipeline.
- **DSP48 Inference** — Multiply-accumulate operations are structured to allow Vivado to automatically infer DSP48 hardware multiplier slices.
- **UART Output** — Results are transmitted as plain-text labels (e.g., `Beat: NORMAL (0)`) over UART for easy verification on a serial terminal.

## Target Platform

- **FPGA Board**: Xilinx ZedBoard (Zynq-7000 SoC, XC7Z020)
- **Clock**: 100 MHz system clock
- **Toolchain**: Xilinx Vivado Design Suite
- **Interface**: USB-UART at 115200 baud (8N1)

## How to Use

1. **Train & Export Weights** — Train the 1D-CNN model in Python (Keras/TensorFlow) on the MIT-BIH dataset, quantize weights to Int8, and export as `.mem` files (`conv1_weights.mem`, `conv1_bias.mem`, `conv2_weights.mem`, `dense_weights.mem`, `dense_bias.mem`, etc.).
2. **Prepare Test Data** — Extract ECG test samples and save as `ecg_test_samples.mem` in 2-digit hex format.
3. **Synthesize** — Open the project in Vivado, add all `.v` files, and run Synthesis → Implementation → Generate Bitstream.
4. **Program FPGA** — Flash the bitstream to the ZedBoard via JTAG.
5. **View Results** — Open a serial terminal (PuTTY) at 115200 baud to see real-time classification output.

## Repository Structure

```
ecg-arrhythmia-fpga-implementation/
├── MAIN MODULES/
│   ├── main.v            # Top-level integration
│   ├── bram_reader.v     # ECG sample reader from Block RAM
│   ├── cnn_top.v         # CNN pipeline controller (FSM)
│   ├── conv1d.v          # 1D convolution layer
│   ├── maxpool.v         # Max pooling layer
│   ├── dense.v           # Fully connected layer
│   └── uart_display.v    # UART transmitter for result display
└── README.md
```

## License

This project is licensed under the [MIT License](LICENSE).
