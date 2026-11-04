# 设置与参考指南

[English](SETUP.md) | **简体中文** · [返回项目首页](../README.zh-CN.md)

本指南包含 Vicon_Trajectory_UM 的硬件连接、参数配置、导出格式和问题排查。

## 硬件与软件要求

### 硬件

| 设备 | 模拟模式 | 真实采集 |
| --- | :---: | :---: |
| 安装 MATLAB 的 Windows 64 位电脑 | 必需 | 必需 |
| 已标定、覆盖路线范围的 Vicon 相机系统，以及配套网络和供电设备 | 不需要 | 必需 |
| 固定安装多个反光球的刚性手持棒 | 不需要 | 必需 |
| 在标定区域内铺设的地面路线，例如胶带标线 | 不需要 | 必需 |
| 与 Tracker 电脑的网络连接（当 MATLAB 在另一台电脑运行时） | 不需要 | 必需 |

反光球布局应保持刚性，并能被 Tracker 稳定识别。本游戏检测的是**刚体原点**，不是棒尖；不需要无人机、Pixhawk、MAVProxy 或游戏手柄。

### 软件

| 软件 | 项目使用环境 | 用途与官方来源 |
| --- | --- | --- |
| Windows | 64 位 | 运行 BAT 启动器和 .NET 采集适配器。 |
| MATLAB | **R2025b** | 运行界面、采集、回放和误差分析。[MATLAB 官网](https://www.mathworks.com/products/matlab.html) |
| Vicon Tracker | **3.10.0** | 追踪刚体并提供 DataStream 数据。[Tracker 官网](https://www.vicon.com/software/tracker/) |
| Vicon DataStream SDK | **1.11.0，Windows x64 .NET 版本** | 连接 MATLAB 与 Tracker。[SDK 官网](https://www.vicon.com/software/datastream-sdk/) |
| .NET Framework C# 编译器 | `Framework64\v4.0.30319\csc.exe` | 首次真实运行时自动编译后台采集适配器。 |

Tracker 3.10.0 和 SDK 1.11.0 是维护者提供的硬件环境版本；MATLAB R2025b 已用于开发和流程测试。其他版本组合尚未全面验证。官网可能优先展示新版，请从历史下载列表寻找旧版，或联系 Vicon 获取对应安装包。

**仅体验模拟模式时，只需 Windows 和 MATLAB。** Tracker、SDK 和 C# 编译器用于真实采集。MATLAB 与 Vicon 软件需自行安装，仓库不附带第三方安装包或 SDK 二进制文件。

程序直接运行 MATLAB 源码，不需要 MATLAB Compiler、单独的 MATLAB Runtime、Parallel Computing Toolbox 或 Python。

## 连接真实 Vicon

1. 安装 Tracker 和 Windows x64 DataStream SDK。默认 SDK DLL 路径为：

   ```text
   C:\Program Files\Vicon\DataStream SDK\Win64\dotNET
   ```

   该目录应包含 `ViconDataStreamSDK_DotNET.dll` 和原生依赖 `ViconDataStreamSDK_CPP.dll`。

2. 在 Tracker 中完成相机系统和全局坐标系标定，将手持棒定义为刚体 **STEM_WAND**。也可以使用其他名称，但需与配置一致。
3. 确认棒子能够正常追踪，并开启 **DataStream 数据输出**。Tracker 与 MATLAB 不在同一台电脑时，确认网络连通，并使用 Tracker 电脑的 IP 地址。
4. 修改 [config.json](../config.json)，将 `SIMULATION_MODE` 改为 `false`，检查 `VICON_SERVER`、`RIGID_BODY_NAME` 和 `SDK_DIR`。默认服务器为 `localhost`，刚体名称为 `STEM_WAND`。
5. 双击 BAT，或在 MATLAB 中运行主程序。首次真实运行会从 `sdk/ViconSampler.cs` 自动生成 `sdk/ViconSampler.dll`，因此项目目录需要可写。等待 **Connected** 和 **Tracking** 后再进入起点区域。

> [!IMPORTANT]
> 地面路线必须与 Vicon 全局 XY 坐标中的标准路线位置一致。软件不会自动平移、旋转或缩放路线，也不计算棒尖偏移。画面为**横轴 Y、纵轴 −X**，保存与计算使用原始 XY 坐标。

<details>
<summary><strong>标准路线坐标，单位：米</strong></summary>

| 点 | X | Y |
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

按顺序连接各点。P2 → P3 是以两点为直径端点、向 X 正方向凸出的半圆，其余部分为直线。要修改路线，请编辑主程序内的 `generateReferencePath` 函数。

</details>

## 配置说明

用文本编辑器修改 [config.json](../config.json) 后重新启动，保留合法的 JSON 引号、逗号和括号。

| 参数 | 公开版默认值 | 含义 |
| --- | --- | --- |
| `SIMULATION_MODE` | `true` | 模拟模式；真实采集改为 `false`。 |
| `VICON_SERVER` | `"localhost"` | Tracker 服务器主机名或 IP 地址。 |
| `RIGID_BODY_NAME` | `"STEM_WAND"` | Tracker 中的刚体名称。 |
| `SDK_DIR` | SDK 默认安装路径 | 包含 .NET SDK DLL 的文件夹。 |
| `START_RADIUS_M` | `0.15` | 起点检测半径，米。 |
| `START_COUNTDOWN_SEC` | `3` | 开始前倒计时，秒。 |
| `FINISH_RADIUS_M` | `0.15` | 终点检测半径，米。 |
| `FINISH_HOLD_SEC` | `0.3` | 终点连续有效停留时间，秒。 |
| `REPLAY_SPEED` | `1` | 回放速度倍率，1 为原速。 |
| `RESULTS_DIR` | `"results"` | 保存目录，可为相对或绝对路径。 |
| `SIM_DURATION` | `20` | 模拟走完整条路线的秒数。 |
| `SIM_LOSS_INTERVAL` | `[7, 9]` | 模拟追踪丢失区间；`[]` 可关闭。 |

JSON 中的 Windows 路径需要写双反斜杠，例如：

```json
"SDK_DIR": "C:\\Program Files\\Vicon\\DataStream SDK\\Win64\\dotNET"
```

## 数据导出

```text
results/
└── 日期_时间_唯一标识/
    ├── trajectory.csv          # 原始数据和有效标记
    ├── trajectory_result.png   # 轨迹对比和误差
    └── session.mat             # 完整 MATLAB 会话数据
```

CSV 列为 `timestamp,x,y,tracking_valid,frame_number`。位置单位为米；时间戳为 Start 之后的本机单调接收时间，并非 Vicon 曝光时间。缺失位置使用 `NaN`，合成的缺帧标记也使用 `NaN` 帧号。

CSV 在录制结束时保存，PNG 与 MAT 在回放结束后保存。每轮独立建目录，不覆盖旧记录。

## 项目结构

```text
Vicon_Trajectory_UM/
├── .gitignore                    # 排除记录和生成文件
├── .gitattributes                # 文本与 BAT 换行规则
├── README.md                     # 英文说明
├── README.zh-CN.md               # 中文说明
├── Start_Vicon_Trajectory_UM.bat  # Windows 启动器
├── Vicon_Trajectory_UM.m          # 主程序
├── config.json                   # 默认模拟配置
├── docs/
│   ├── SETUP.md                  # 英文设置与参考指南
│   ├── SETUP.zh-CN.md            # 中文设置与参考指南
│   └── images/                   # 两份说明共享的图片
└── sdk/ViconSampler.cs           # 后台采集适配器源码
```

运行时生成的 `results/` 与 `sdk/ViconSampler.dll` 已加入 `.gitignore`。上传时保留 `docs/images/`；仓库不附带真实采集记录、重复 Word 文档或第三方安装包。

## 常见问题

<details>
<summary><strong>BAT 提示找不到 MATLAB</strong></summary>

BAT 优先寻找 `%ProgramFiles%\MATLAB\R2025b\bin\matlab.exe`，然后查询 PATH。安装位置不同可修改 BAT 中的 `MATLAB_EXE`，或直接在 MATLAB 中打开本目录运行 `Vicon_Trajectory_UM`。

</details>

<details>
<summary><strong>显示 Disconnected，或首次编译适配器失败</strong></summary>

检查 Tracker 的 DataStream 输出、服务器地址和 SDK 路径。首次真实运行还需确认两个 SDK DLL 与 `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 存在，并且项目的 `sdk` 目录可写。修改配置后重启；临时掉线可使用 Reconnect。

</details>

<details>
<summary><strong>显示 Lost，或没有倒计时</strong></summary>

检查刚体名称和反光球可见性。刚体原点必须在起点范围内，并在倒计时期间持续有效追踪。检测不使用棒尖位置。

</details>

<details>
<summary><strong>画面轨迹与地面路线不一致</strong></summary>

核对 Vicon 全局坐标系和标准路线坐标。画面使用 Y 与 −X，保存和距离计算使用原始 XY；没有自动对齐或棒尖补偿。

</details>
