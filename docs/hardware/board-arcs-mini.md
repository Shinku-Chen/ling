> ⚠️ **先确认板型**：`arcs_mini` 与 `arcs_mini3` 是**两块不同的板**，SoC、引脚、boot/ap 镜像都不同。
>
> | 项 | `arcs_mini` | **`arcs_mini3`** |
> |---|---|---|
> | SoC | LS2684 | **LS2663** |
> | 构建 | `-DBOARD=arcs_mini` | **`-DBOARD=arcs_mini3`** |
> | 资源目录 | `res/arcs-mini/` | **`res/arcs-mini3/`**（tone / wake_word / emoji / respak 共用 mini 的） |
> | CP 日志 | uart1 = PB02 | **uart0 = PA02(RX)/PA03(TX)** |
> | AP 日志 | uart0 = PA02/PA03 | uart1 = PB02 |
> | 外部/烧录串口 | PB02（uart2_txd） | **UART2 = PB06/PB07** |
>
> **刷错板型的现象是：黑屏 + USB 不识别 + 反复重启**（2026-10-02 实测，排了一整天）。
> 本工作区当前设备是 **arcs_mini3**。

# Arcs-mini（LS26）硬件事实

> 来源标注：`[官方-开发板]` = 聆思文档中心《Arcs-Mini 开发板》；`[官方-芯片]` = 聆思文档中心《LS26系列芯片介绍》；
> `[固件]` = `arcs_mini` 固件仓库（`apps/arcs-mini/prj.conf`、`arcs-sdk/boards/arcs_mini/`、`arcs-sdk/soc/arcs/ls26xx/ls2684/`）。
> 链接见 [../reference/README.md](../reference/README.md)。

## 1. SoC：LS2684L0U（LS26 系列 / ARCS）

| 项目 | 规格 | 来源 |
|---|---|---|
| CPU | Nuclei N310 (RISC-V) ×2，主频最高 300 MHz（AP/CP 双核架构） | 官方-芯片 |
| NPU | LUNA NPU，内置 | 官方-芯片 |
| SRAM | 704 KB | 官方-芯片 |
| PSRAM | SIP 封装 4 / 8 / 16 MB 可选 | 官方-芯片 |
| Flash | 支持最多 2 个外挂 Flash；本开发板为 16 MB 板载 | 官方-芯片 / 官方-开发板 |
| 无线 | Wi-Fi 6 2.4 GHz（802.11 b/g/n/ax，1×1 20 MHz）、蓝牙 6.0 双模（BR/EDR/BLE） | 官方-芯片 |
| 安全 | AES/SHA/HMAC/RSA/ECC 硬件加速、TRNG、Secure Boot、Flash/PSRAM 在线加解密 | 官方-芯片 |
| 外设 | 最多 42 GPIO、USB 2.0 OTG、SD/MMC 3.0、3×UART、2×I2C、3×SPI、8×PWM、GPADC、IR、QDEC、DVP/QSPI/SPI 图像输入、RGB/QSPI/SPI 显示输出 | 官方-芯片 |

## 2. 开发板规格（Arcs-Mini）

| 项目 | 规格 | 来源 |
|---|---|---|
| 尺寸 | 46.4 × 42.0 × 24.2 mm（PCBA 38 × 38 mm） | 官方-开发板 |
| 屏幕 | 1.54 寸 240 × 240，驱动 IC 文档写 ST7789V，固件配置使用 ST7789P3 面板 | 官方-开发板 / 固件 |
| 摄像头 | GC0328，30 万像素，最高 1280×720@60fps，DVP 接口 | 官方-开发板 |
| 扬声器 | 8Ω 2W（可接 4Ω 3W，工作功率约 2–2.5W）；功放 IC NS4150B | 官方-开发板 |
| 麦克风 | 驻极体单麦，灵敏度 −32 dBV ±3 dB，信噪比 ≥65 dBA；有硬回采（AEC）通道 | 官方-开发板 |
| 用户 LED | `GPIOB_01` | 官方-开发板 |
| 主功能按键 | `GPIOB_04`（power-key） | 官方-开发板 |
| Flash | 16 MB | 官方-开发板 |
| USB | Type-C：供电/充电 + 烧录 + 数据传输（ADB） | 官方-开发板 |
| IO 扩展 | MX1.25 8P：VCC(3.3V)、GND、A04、A05、A06、A07、A08、A09（均支持 GPIO/UART/I2C/SPI/I2S/GPT/IR/VIC/QDEC） | 官方-开发板 |
| 电池 | 选配：3.7V 标称 / 4.2V 限充，500–1000 mAh，带 NTC 10K，≤31×43×7 mm | 官方-开发板 |
| 供电建议 | Type-C 5V/1A 以上（官方另建议 5V/2A 适配器） | 官方-开发板 |

### 2.1 GPIO 分配（官方表，节选小应用会用到的部分）

| 引脚 | 功能 | 说明 |
|---|---|---|
| `GPIOA_00` | CAM_RST | 摄像头 |
| `GPIOA_01` | PA_mute | 功放 |
| `GPIOA_02` / `GPIOA_03` | VDD_IO / GND | IO 扩展接口 |
| `GPIOA_04` … `GPIOA_09` | 可编程 GPIO | IO 扩展接口（PA04–PA09） |
| `GPIOA_10` … `GPIOA_20` | 摄像头 DVP（HSYNC/VSYNC/CLK/D4–D11） | 摄像头 |
| `GPIOA_21` … `GPIOA_27` | LCD（PWM 背光 / SPI0 CS / WR / MOSI / CLK / TE） | 屏幕 |
| `GPIOA_28` / `GPIOA_29` | MIC1 AEC_P / AEC_N | 硬回采 |
| `GPIOA_30` / `GPIOA_31` | MICO INP / INN | 麦克风 |
| `GPIOB_00` | USB_DET | USB 插入检测 |
| `GPIOB_01` | LED | 用户可编程 LED |
| `GPIOB_02` | uart2_txd | 预留烧录串口 |
| `GPIOB_03` | POW_EN | 电源锁存 |
| `GPIOB_04` | power-KEY | 主功能按键 |
| `GPIOB_05` | ADC_Bat_Vot | 电池电量检测 |
| `GPIOB_08` | CHARGE_DET | 充电状态检测 |
| `GPIOB_09` | LCD_RST | 屏幕复位 |

完整表见官方开发板文档（[../reference/README.md](../reference/README.md) 有入口）。

## 3. 固件可见的内存与外设预算

| 项目 | 取值 | 来源 |
|---|---|---|
| Flash 分区表终点 | `0x1000000`（16 MB） | 固件 `res/arcs-mini/partition_table.json` |
| PSRAM 基址 | `0x28800000` | 固件 `apps/arcs-mini/prj.conf` |
| PSRAM 映射大小 | `0x00800000`（8 MiB，应用侧配置） | 固件 `apps/arcs-mini/prj.conf` |
| PSRAM heap | `0x600000`（6 MiB） | 固件 `apps/arcs-mini/prj.conf` |
| SoC 默认 PSRAM 尺寸 | `0x01000000`（16 MB，LS2684 默认值） | 固件 `arcs-sdk/soc/arcs/ls26xx/ls2684/Kconfig.defconfig` |

> ⚠️ 已知差异：官方宣传 LS2684L0U"内置 16MB PSRAM"，而 Arcs-mini 应用侧把映射大小配成 8 MiB。
> 也就是"芯片总容量"和"固件可用窗口"不是同口径。写代码时不要依赖容量假设——用小应用能力接口
> （`runtime.lua_sdk`）给的额度，而不是"板子有多少 PSRAM"。

小应用实际可用的额度是**运行时下发的能力值**，不是上面的物理容量，见
[../development/miniapp-runtime.md](../development/miniapp-runtime.md)。

## 4. 小应用能触达的硬件

小应用只能通过 Lua API 使用能力；**硬件存在 ≠ Lua 能访问**。

| 硬件 | 小应用侧接口 | 条件 |
|---|---|---|
| 屏幕 | `screen.begin/rect/text/present` | 固件开启 `CONFIG_MINIAPP_SCREEN`（默认开，画布 240×240） |
| 状态灯 | `led.on/off/blink` | 固件开启 `CONFIG_MINIAPP_LED` |
| 扬声器（提示音） | `buzzer.play` | 固件开启 `CONFIG_MINIAPP_BUZZER` |
| 主功能键 | `on_button_click("function")` | 按键能力启用 |
| 网络 | `http.*` | `hardware.network == true` 且 `runtime.lua_sdk.http` 存在 |
| 语音播报 | `tts.speak` | 有扬声器且 `runtime.lua_sdk.tts` 存在 |
| 时间 | `clock.now/localtime` | API ≥ 3 |
| 存档 | `storage.load/save/clear` | API ≥ 3 |

**不能**从 Lua 直接访问：摄像头、麦克风、TF 卡、GPIO/PWM/I2C/UART 等引脚级外设、文件系统、
原始 socket。这些要改固件（见 [../reference/README.md](../reference/README.md)）。
