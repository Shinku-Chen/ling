# 设备行为实测记录（2026-10-02）

记录的是**实测观察 + 源码依据**，不是推断。未解释清楚的部分明确标注为"待验证"。

## 1. 黑屏 + ADB 掉线：空闲休眠（hibernate）

**源码依据**（`apps-ui/apps/llm/presenters/home_presenter.c:594`，官方固件仓库）：

```c
static void home_enter_hibernate(scr_data)
{
    model_common_brightness_set_temp(HOME_HIBERNATE_BRIGHTNESS);  // = 0，背光熄
    model_common_display_set_blanked(true);                        // 屏幕 blanking 打开
    model_common_usb_set_suspended(true);                          // ★ USB 被挂起
    model_common_power_experiment_set_suspended(true);             // 相机/USB/DAC/logger 挂起
    lisa_ui_handler_suspend();                                     // LVGL 停
}
```

一次解释三个现象：**黑屏**、**ADB 不应答**、**控制台无日志**。

**时序**（设备启动日志原文）：

```
Initialized: idle=30s, hibernate=5min, shutdown=15min total (hibernate+10min)
```

- 空闲 30 s → 降亮度（`idle`）
- 空闲 5 min → hibernate
- 空闲 15 min → 关机倒计时（仅在**未接外部电源**且电量 ≤30% 时）

**唤醒**：用户活动（按键 / 语音）。唤醒路径 `home_restore_standby_brightness()` 会恢复亮度、解除 blanking、恢复 USB 与 LVGL。

**关键推论**：小应用运行期间**抑制** display idle 与 hibernate（固件文档与 `service_power_policy.c:555` 注释均写明）。
→ 这就是"今天早些时候设备一直好用、没有小应用之后开始黑屏掉线"的原因。

**电源策略还写明**（`service_power_policy.c`）：

```c
if ((state == HIBERNATE || SHUTDOWN_PENDING) && external_power) {
    // 插着 USB → 退回 IDLE/NORMAL，不休眠
}
```

即**插电时不应进入 hibernate**。实测中仍观察到黑屏，说明当时的状态与这条规则的关系**待验证**（可能是 USB 检测信号、供电不足或 boot 状态异常）。

## 2. `ERR:Failed to halt the peer core` / `ERR:Halt mutex is not owned`

- 出处：`arcs-sdk/soc/arcs/hal/chip/arcs/ipc/utils/ipc_utils.c:142,171`（**核间 IPC 工具**，CP 尝试复位/halt AP 核失败）。
- 出现情况：**官方原版固件同样打印**，且在一天中多次抓取里持续出现（约每 5～8 秒一对）。
- 结论：**与我们的固件改动无关**，是设备/固件既有现象。是否会阻塞 UI 启动**待验证**（这是目前"屏幕不亮"的候选原因之一）。

## 3. ADB 通道的不对称故障

| 操作 | 结果 |
|---|---|
| `adb shell <短命令>`（如 `version`） | ✅ 12/12 成功，0～1 s 返回 |
| `adb push` / `adb pull`（sync 通道） | ❌ 12/12 失败，`connect failed: closed` |

- 同一时刻：**命令通道好、传输通道坏**。
- 这种"小命令通、大传输断"的形态，典型原因是 **USB 链路/供电边缘化**（线材、Hub、供电不足），或设备侧 sync 服务异常。
- 后续设备在 Windows 里**完全消失**（连 `VID_0483` 都不在），指向同一方向：**物理链路问题**。

## 4. 实测时间线（官方原版固件的一次稳定窗口）

从 recovery 干净重启进正常模式后，连续 5 分钟、每 15 秒探测一次：

```
t+0s   listed=YES  shell=[3.0.2-5f2bb183]  (1s)
t+16s  listed=YES  shell=[3.0.2-5f2bb183]  (0s)
...（共 20 轮，全部正常）
t+292s listed=YES  shell=[3.0.2-5f2bb183]  (0s)

应答成功 20/20；不应答 0；列表不可见 0
```

控制台时间戳 5 分 26 秒，与观测窗口吻合 → **期间没有重启**。

结论：**官方固件在"有活动/刚启动"的窗口内是稳定的**；长时间无活动会进入休眠态（第 1 节）。

## 5. 观察到的其他现象

| 现象 | 说明 |
|---|---|
| 烧录后设备曾自行重启一次（uptime 归零） | 原因未知，可能与 recovery 退出/电源状态有关 |
| 用户在设备侧看到"反复重启进入 ADB" | 疑似 boot/recovery 状态异常（`boot_control` 标记或 app 分区内容异常），**待恢复后验证** |
| 烧录 recovery 的 `recovery exit` 返回 `Command not Found` | 该版 recovery shell 无此命令，可忽略；其后 `reboot hard` 正常 |

## 6. 对开发的直接影响（重要约定）

1. **测试期间必须让设备保持"有活动"状态**，否则会进休眠，表现为"黑屏 + ADB 掉线"：
   - 首选：保持一个小应用在运行（小应用会抑制休眠）；
   - 或：定期短按功能键。
2. **不要把"黑屏/ADB 掉线"当作固件 bug**——先按休眠排查。
3. **USB 链路要留一手**：单独准备一根确认能传数据的线；并保留串口烧录这条兜底通道
   （见 [../development/flashing-and-recovery.md](../development/flashing-and-recovery.md)）。
