# 烧录与恢复手册

> 本文记录本仓库实际用过的烧录路径与踩过的坑。硬件事实见 [../hardware/board-arcs-mini.md](../hardware/board-arcs-mini.md)；
> 官方的 skill 原文在固件仓库 `.agents/skills/flash/SKILL.md`，冲突时以固件仓库为准。

## 0. 三条烧录通道

| 通道 | 用途 | 现状 |
|---|---|---|
| **ADB recovery**（`adb push` → `/RAW/NAND/<addr>`） | 日常刷分区、恢复固件 | 正常工作（本文主力） |
| **串口 cskburn** | USB/ADB 起不来、救砖、boot 损坏 | 兜底通道 |
| 官方 cskburn desktop（GUI） | 用 `.lpk` 整包刷 | 官方推荐给普通用户 |

## 1. 进入 ADB recovery（烧录模式）

```
USB 保持连接
按住【功能键】不放  →  短按【RST】  →  松开【功能键】
```

成功后设备以 `BOOT-*` 出现在 adb 里（`product:mido model:listenai`）：

```powershell
adb devices -l
# BOOT-<serial>  device product:mido model:listenai device:mido transport_id:3
```

⚠️ 多设备（手机 + 开发板）同时插着时，**永远用 `-s <serial>` 明确指定**，不要裸跑 `adb push`。

## 2. ADB recovery 烧录（手工复刻 `adb_download.ps1`）

`app` 模式只烧 CP 应用，等价于：

```bash
adb -s <BOOT-serial> push <app.bin> /RAW/NAND/600000
adb -s <BOOT-serial> shell recovery exit      # 在某些版本上返回 "Command not Found"，可忽略
adb -s <BOOT-serial> shell reboot hard
```

要点：

- 远端路径 = `/RAW/NAND/` + **地址去掉 `0x` 与前置零**（`0x600000` → `600000`）。
- Git Bash 下必须加 `MSYS_NO_PATHCONV=1`，否则 `/RAW/NAND/...` 会被改写成 Windows 路径。
- 本地文件路径要用 **Windows 形式** 传给 adb（adb 是 Windows 程序）：`cygpath -w <file>`。
- 实测 recovery 传输速率约 **0.1 MB/s**（3.2 MB ≈ 42 秒），比正常模式慢得多，属正常。
- 校验方式：`adb push` 报出的字节数必须与本地文件大小**完全一致**。

## 3. 分区地址表（来自 `res/arcs-mini/partition_table.json`）

| 分区 | 地址 | 文件 | 大小（官方 3.0.2） |
|---|---|---|---|
| boot | `0x000000` | `res/arcs-mini/boot.bin` | 221,992 |
| boot_control | `0x03E000` | （保留，无 file） | 4,096 |
| ap | `0x040000` | `res/arcs-mini/ap.bin` | 380,884 |
| tone | `0x100000` | `res/arcs-mini/tone.bin` | 351,232 |
| wake_word | `0x200000` | `res/arcs-mini/wake_word.bin` | 1,432,576 |
| emoji | `0x380000` | `res/arcs-mini/emoji.bin` | 492,544 |
| respak | `0x440000` | `res/arcs-mini/respak.bin` | 983,040 |
| app（CP） | `0x600000` | `build/arcs-mini.bin` | 3,255,496（官方） |
| ota | `0xA00000` | （保留） | 5,242,880 |
| kv | `0xF00000` | （保留） | 1,048,576 |

- app 分区**没有显式 size**，上界 = 下一个分区 `ota`（`0xA00000`）→ 可用 **4 MiB**。
  当前官方镜像 3.11 MiB，余量约 914 KB。
- `boot_control` / `ota` / `kv` 是保留区，**不要手写**。

## 4. 官方固件（.lpk）从哪里来

聆思文档中心的固件更新日志页：

```
https://docs2.listenai.com/x/zNDNSNU9b
```

页面里的下载链接形如 `/zz/<id>.lpk?shortId=zNDNSNU9b`，**必须带 `shortId` 参数**，否则下载会失败：

```bash
curl -L -o arcs-mini-3.0.2.lpk "https://docs2.listenai.com/zz/13298.lpk?shortId=zNDNSNU9b"
```

`.lpk` 就是一个 zip：

```
manifest.json     # 各分区的 name / addr / md5
boot.bin  ap.bin  tone.bin  wake_word.bin  emoji.bin  respak.bin  arcs-mini.bin（app）
```

解压后可以：
- 用 `md5` 与仓库 `res/arcs-mini/` 里的文件比对（**3.0.2 实测全部一致**）；
- 直接按第 2 节把需要的分区推到对应地址。

## 5. 串口烧录（cskburn）—— USB 起不来时的兜底

硬件：USB-TTL 接开发板的**预留烧录串口**（`GPIOB_02 uart2_txd` 等），或官方串口适配器。

```bash
# 只更新 CP app（开发阶段）：必须同时写入开发 Boot，设备才能自动进业务
cskburn -C arcs -b 1500000 -s COM<port> --verify-all \
  0x0   res/arcs-mini/boot-dev-autostart.bin \
  0x600000 build/arcs-mini.bin
```

```bash
# 出厂原版整体恢复（救砖）：boot + 全部分区一次性写入
cskburn -C arcs -b 1500000 -s COM<port> --verify-all \
  0x0      boot.bin \
  0x40000  ap.bin \
  0x100000 tone.bin \
  0x200000 wake_word.bin \
  0x380000 emoji.bin \
  0x440000 respak.bin \
  0x600000 arcs-mini.bin
```

> **串口烧录强制闭环**（固件仓库 AGENTS.md 规定）：
> 开发阶段写 `boot-dev-autostart.bin` 到 `0x0`，功能验证完成后**必须把官方 `boot.bin` 写回 `0x0`**，
> 否则设备一直停在"开发 Boot"状态。

- 波特率默认 `1500000`；确认线材稳定后再试 `3000000`。
- Windows 下串口是 `COMx`（设备管理器或 `mode` 查）。

## 6. 故障对照表

| 现象 | 判断 | 处理 |
|---|---|---|
| `adb devices` 里没有开发板，Windows 里也没有 `VID_0483` 设备 | **USB 数据链路没通**（充电线/坏线/坏口） | 换线、换后置 USB 口；仍无 → 串口烧录 |
| 设备在 adb 里，`shell` 有响应，但 `push` 报 `connect failed: closed` | 传输通道异常 | 换线/换口重试；不行就走串口 |
| 设备编号变成 `BOOT-*` 且反复重启 | 卡在 recovery / boot 分区异常 | 进 recovery 重烧 app；仍循环 → 串口整体恢复 |
| 屏幕黑、但 ADB 正常 | 大概率是**空闲休眠**（见 `../reference/device-behavior-log.md`） | 短按功能键唤醒 |
| 长按功能键无反应、红灯不亮 | 没供电或已关机 | 长按功能键 3 秒开机；检查 USB 供电/电池 |

## 7. 一次成功烧录的时间线（实测参考）

```
1. 按住功能键 + 短按 RST            → adb 出现 BOOT-<serial>
2. adb -s BOOT push <img> /RAW/NAND/600000   → 3.2 MB / 42 s，字节数一致
3. adb -s BOOT shell recovery exit   → "Command not Found"（可忽略）
4. adb -s BOOT shell reboot hard     → 设备重启
5. 约 20 s 后 adb -s <serial> shell version → 版本号变成新固件
```
