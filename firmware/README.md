# firmware/ —— 固件侧改动存档

这里放的是**不属于本仓库（小应用工作区）本体、但需要长期保存**的固件侧产物。

## miniapp-audio.patch

给 Arcs-mini 固件的小应用运行时**新增音频播放能力**（`audio.play/stop/pause/resume/state`）的补丁。

| 项 | 值 |
|---|---|
| 基线提交 | `620341ff`（上游公开仓库 `mini-v3.0.2-m3`，即官方 `3.0.2` 资源所在的版本线） |
| 补丁提交 | `3efeccac` |
| 改动范围 | 6 个文件，+277 / −5 行 |
| 新增 Lua API | `audio.play(url)` / `audio.stop()` / `audio.pause()` / `audio.resume()` / `audio.state()` |
| 能力上报 | `get_device_capabilities` 的 `runtime.lua_sdk.audio` |
| 固件侧开关 | `CONFIG_MINIAPP_AUDIO`（默认 y） |

改动文件：

```
apps/arcs-mini/miniapp/miniapp_runtime.c                 主体：audio 表 + 独立播放任务 + 候选启动延迟 + 退出清理
apps/arcs-mini/miniapp/miniapp.h                         MINIAPP_HAS_AUDIO / MINIAPP_AUDIO_URL_MAX
apps/arcs-mini/miniapp/Kconfig                           CONFIG_MINIAPP_AUDIO
apps/arcs-mini/mcp-tools/mcp_tool_device_capabilities.c   能力上报 runtime.lua_sdk.audio
src/category/comm/voice_player_comm.c                    播放器实例/焦点通道启用条件；miniapp 通道改 PAUSE（可自动续播）
docs/miniapp.md                                          设备侧契约文档新增"音频播放"一节
```

### 应用方式

```bash
# 在上游公开仓库的 checkout 里（基线 620341ff）
git checkout -b feat/miniapp-audio 620341ff
git am firmware/miniapp-audio.patch
```

### 编译与验证状态

| 项 | 状态 |
|---|---|
| 编译（`-DBOARD=arcs_mini`，Windows 原生工具链） | ✅ 通过，我们的三个文件零警告，符号与字符串都在产物里 |
| 体积代价 | +1,664 字节（app 镜像 3,256,960 → 3,258,624；app 分区 4 MiB，余量约 914 KB） |
| 烧录到真机 | ✅ 成功（`adb shell version` → `3.0.2-3efeccac`） |
| **功能验证（能否播直播流）** | ❌ **未完成** —— 设备在验证阶段出现 USB/供电故障，实验中断 |

### 当前结论与替代路线

- 该补丁**不再作为首选路线**：收音机改为走 **ARCS SDK 固件内实现**
  （不需要改 SDK、也不需要上游 MR），见
  [`../docs/development/radio-native-plan.md`](../docs/development/radio-native-plan.md)。
- 保留此补丁的用途：
  1. 若将来希望"小应用也能播音频"，这是一份可提上游的参考实现；
  2. 里面几条**踩坑结论**对任何音频相关改动都适用：
     - 底层解码器**保留 URL 指针** → 传入的字符串必须活到播放结束；
     - 候选实例启动阶段**不能产生副作用**（不能出声），要延迟到替换成功之后；
     - 播放/停止**不能阻塞 Lua 的 20 ms tick**，必须交给独立任务。
