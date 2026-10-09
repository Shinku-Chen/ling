# firmware/ —— 固件侧改动存档

这里放的是**不属于本仓库（小应用工作区）本体、但需要长期保存**的固件侧产物。

## radio-demo.patch

在固件里**内置一个最小网络电台**（用于验证音频链路；也是小应用路线的备选方案）。

| 项 | 值 |
|---|---|
| 基线 | 不依赖其他补丁，可直接打在上游 checkout 上 |
| 改动范围 | 9 个文件，+228 行 |
| 开关 | `CONFIG_RADIO_DEMO`（默认 n；演示构建在 `prj.conf` 里打开） |
| 行为 | 开机自动播第一个台；短按换台；双击暂停/继续；长按交给系统 |
| 播放通道 | 复用 `voice_player_comm` 的 `music_player`（焦点托管，被 TTS/唤醒抢占时暂停） |
| 实测 | 在 mini3 上编译通过并烧录运行（音频链路可用；音质与长时间稳定性未做完整验收） |

应用方式：

```bash
git apply firmware/radio-demo.patch
cmake -B build-radiodemo -G Ninja -S apps/arcs-mini -DBOARD=arcs_mini3   # 注意板型
cmake --build build-radiodemo -j
```

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
| **功能验证（能否播直播流）** | ✅ **已通过**：小应用连续播放直播流 **33 秒**、状态全程 `playing`、零错误（探针 `examples/radio-probe.lua`，结果从设备存档读回） |

### 当前结论与替代路线

- **小应用路线已验证可用**：补丁编译、烧录、实测均通过，因此当前主应用就是
  [`../src/app.lua`](../src/app.lua)（网络电台小应用）。
- 另一条路是固件内实现（见上方 `radio-demo.patch`）：不需要改小应用运行时，适合不想动运行时的场景。
- 若要提上游 MR：两份补丁都围绕公开固件仓库，提交时留意同步更新 `docs/miniapp.md`（设备侧契约）。
