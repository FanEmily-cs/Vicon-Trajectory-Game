# Setup and Reference

**English** | [简体中文](SETUP.zh-CN.md) · [Back to README](../README.md)

Hardware setup, configuration, exports, and troubleshooting for Vicon_Trajectory_UM.

## Requirements

### Hardware

| Component | Simulation | Live recording |
| --- | :---: | :---: |
| Windows x64 | Required | Required |
| MATLAB — tested on R2025b | Required | Required |
| Calibrated Vicon camera system covering the route, with its normal network and power equipment | — | Required |
| Handheld rigid wand with multiple securely attached reflective markers | — | Required |
| Floor route markings, such as tape, in the calibrated capture area | — | Required |
| Network connection to Tracker, if it runs on a different computer | — | Required |

Use a rigid marker arrangement that Tracker can identify reliably. No drone, Pixhawk, MAVProxy, or handheld controller is needed.

### Software

| Software | Project environment | Purpose / official source |
| --- | --- | --- |
| Windows | 64-bit | Runs the BAT launcher and .NET acquisition adapter. |
| MATLAB | **R2025b** | UI, recording, replay, and analysis. [MATLAB](https://www.mathworks.com/products/matlab.html) |
| Vicon Tracker | **3.10.0** | Tracks the wand and provides DataStream output. [Official Tracker page](https://www.vicon.com/software/tracker/) |
| Vicon DataStream SDK | **1.11.0**, Windows x64 .NET package | Connects MATLAB to Tracker. [Official SDK page](https://www.vicon.com/software/datastream-sdk/) |
| .NET Framework C# compiler | `Framework64\v4.0.30319\csc.exe` | Automatically builds the adapter on the first live run. |

Tracker 3.10.0 and SDK 1.11.0 are the versions reported for the maintainer's hardware setup; MATLAB R2025b has been used for development and workflow tests. Other combinations have not been comprehensively validated. The official pages may feature newer releases; use their legacy downloads or contact Vicon if an older installer is needed.

**Simulation only needs Windows and MATLAB.** Tracker, the SDK, and the adapter compiler are needed for live recording. Install third-party software separately; MATLAB and Vicon installers and SDK binaries are not bundled.

The app runs directly from MATLAB source using a BAT launcher. MATLAB Compiler, a separate MATLAB Runtime installation, Parallel Computing Toolbox, and Python are not required.

## Live Vicon Setup

1. Install Tracker and the Windows x64 DataStream SDK. The SDK's `Win64\dotNET` folder should contain `ViconDataStreamSDK_DotNET.dll` and its native dependency `ViconDataStreamSDK_CPP.dll`.
2. Calibrate the camera system and global coordinate frame in Tracker. Define the wand as a rigid body named **STEM_WAND**, or use your own name consistently in Tracker and the configuration.
3. Confirm that the wand is tracked and enable **DataStream output**. If MATLAB and Tracker run on different computers, ensure network connectivity and use the Tracker computer's IP address.
4. Set `SIMULATION_MODE` to `false` in [config.json](../config.json). Check `VICON_SERVER`, `RIGID_BODY_NAME`, and `SDK_DIR`. Default server and body name are `localhost` and `STEM_WAND`.
5. Launch the BAT file or run `Vicon_Trajectory_UM` in MATLAB. On the first live run, `sdk/ViconSampler.dll` is compiled automatically from `sdk/ViconSampler.cs`. Keep the project in a writable folder. Wait for **Connected** and **Tracking** before approaching START.

> [!IMPORTANT]
> Place the floor route at the reference coordinates in the Vicon global coordinate system. The app does not automatically translate, rotate, or scale the reference path. Start and finish detection use the **rigid body origin**, not the wand tip.

<details>
<summary><strong>Reference route coordinates (metres)</strong></summary>

| Point | X | Y |
| --- | ---: | ---: |
| P1 — START | -0.75 | -1.47 |
| P2 | 0.26 | -1.47 |
| P3 | 0.26 | -0.55 |
| P4 | -0.75 | -0.55 |
| P5 | 0.75 | 0.40 |
| P6 | -0.75 | 0.40 |
| P7 | 0.60 | 1.00 |
| P8 | -0.75 | 1.60 |
| P9 — END | 0.75 | 1.60 |

Connect the points in order. P2 → P3 is a semicircle using those points as diameter endpoints, bulging toward positive X. Other connections are straight lines. Edit the local `generateReferencePath` function in `Vicon_Trajectory_UM.m` to change the route.

</details>

## Configuration

Edit [config.json](../config.json), then restart the game. Keep valid JSON syntax, including quotation marks and commas.

| Setting | Default | Description |
| --- | --- | --- |
| `SIMULATION_MODE` | `true` | Public default: simulated movement. Set to `false` for live Vicon data. |
| `VICON_SERVER` | `"localhost"` | Vicon server hostname or IP address. |
| `RIGID_BODY_NAME` | `"STEM_WAND"` | Subject / rigid body name in Vicon. |
| `SDK_DIR` | Local SDK path | Folder containing the Vicon .NET SDK DLLs. |
| `START_RADIUS_M` | `0.15` | Start detection radius, in metres. |
| `START_COUNTDOWN_SEC` | `3` | Countdown before recording, in seconds. |
| `FINISH_RADIUS_M` | `0.15` | Finish detection radius, in metres. |
| `FINISH_HOLD_SEC` | `0.3` | Continuous valid tracking required in the finish area, in seconds. |
| `REPLAY_SPEED` | `1` | Replay speed multiplier; `1` means real time. |
| `RESULTS_DIR` | `"results"` | Output folder, relative to the project directory or an absolute path. |

<details>
<summary><strong>Simulation settings and SDK path example</strong></summary>

- `SIM_DURATION`: time to traverse the simulated route; default **20 seconds**.
- `SIM_LOSS_INTERVAL`: simulated tracking-loss interval; default **[7, 9]** seconds. Use `[]` to disable it.
- Restore `SIMULATION_MODE` to `false` before recording real movements.

The default SDK directory is:

```text
C:\Program Files\Vicon\DataStream SDK\Win64\dotNET
```

Backslashes must be escaped in JSON:

```json
"SDK_DIR": "C:\\Program Files\\Vicon\\DataStream SDK\\Win64\\dotNET"
```

</details>

## Data Export

Every round receives a unique output folder:

```text
results/
└── YYYY-MM-DD_HH-mm-ss-SSS_unique-id/
    ├── trajectory.csv          # Raw samples and tracking validity
    ├── trajectory_result.png   # Trajectory comparison and error metrics
    └── session.mat             # Full session for MATLAB analysis
```

The CSV is saved when recording ends. The PNG and MAT files are saved after the replay completes.

<details>
<summary><strong>CSV columns and timestamp conventions</strong></summary>

| Column | Description |
| --- | --- |
| `timestamp` | Monotonic host receive time in seconds since recording started; not Vicon exposure time. |
| `x`, `y` | Original global XY position, in metres. |
| `tracking_valid` | `1` for valid tracking; `0` for missing data. |
| `frame_number` | Vicon frame number, or simulated frame number in simulation mode. |

Missing positions use `NaN`. Synthetic gap markers also use `NaN` for the frame number. Missing intervals remain disconnected during replay.

</details>

## Project Structure

```text
Vicon_Trajectory_UM/
├── .gitignore                    # Excludes recordings and generated files
├── .gitattributes                # Text and Windows BAT line endings
├── Start_Vicon_Trajectory_UM.bat   # Windows launcher
├── Vicon_Trajectory_UM.m          # UI, game flow, reference path, metrics, and exports
├── config.json                   # User settings
├── README.md                     # Project guide
├── README.zh-CN.md               # Simplified Chinese guide
├── docs/
│   ├── SETUP.md                  # Detailed setup and reference
│   ├── SETUP.zh-CN.md            # Simplified Chinese setup guide
│   └── images/                   # Shared README screenshots
├── sdk/
│   └── ViconSampler.cs           # Background acquisition adapter source
└── results/                      # Created during use; ignored by Git
```

Keep `docs/images/` with the README when uploading the project so the screenshots render on GitHub. The Vicon DataStream SDK is installed separately; `ViconSampler` is the project's acquisition adapter.

`sdk/ViconSampler.dll` is generated on the first live run and ignored by Git. Real recordings, duplicate Word documentation, and generated binaries are excluded from the upload copy.

## Troubleshooting

<details>
<summary><strong>MATLAB is not found when launching the BAT file</strong></summary>

Edit `MATLAB_EXE` in `Start_Vicon_Trajectory_UM.bat` to point to your MATLAB installation. The default is:

```text
C:\Program Files\MATLAB\R2025b\bin\matlab.exe
```

You can also open the project folder in MATLAB and run `Vicon_Trajectory_UM` directly.

</details>

<details>
<summary><strong>The connection status is Disconnected</strong></summary>

Check that Vicon is running and DataStream output is enabled. Verify `VICON_SERVER` and `SDK_DIR`, then click **Reconnect**. If you change the configuration file, restart the game.

For adapter compilation errors, check that the SDK DLLs and `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` exist and the project's `sdk` folder is writable.

</details>

<details>
<summary><strong>Tracking is Lost, or the countdown does not start</strong></summary>

Check that `RIGID_BODY_NAME` matches the subject in Vicon and that the reflective markers are visible. To start the countdown, the rigid body origin must be within the start radius with valid tracking. The wand tip is not used for this check.

</details>

<details>
<summary><strong>The recorded path does not line up with the floor route</strong></summary>

Confirm that the physical route matches the reference coordinates in the Vicon global frame. The screen displays Y and −X, while recording and distance calculations use the original XY coordinates. No automatic alignment or tip offset is applied.

</details>
