# 外部资料索引

本仓库不复制外部正文，只给入口。查不到事实时的顺序：**官方文档 → 官方仓库源码 → 本仓库文档**。

## 1. 小应用（LingClaw）开发

| 资料 | 地址 | 用途 |
|---|---|---|
| LingClaw-SDK 仓库 | <https://github.com/LISTENAI/LingClaw-SDK> | 模拟器、示例、API 文档（本仓库运行时契约的上游） |
| LingClaw-SDK Releases | <https://github.com/LISTENAI/LingClaw-SDK/releases> | 下载模拟器（当前 0.1.0，唯一 release） |
| 本地已解压包 | `D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64\` | `docs/api/*.md` 是 API 逐条契约；`examples/` 可直接跑 |

## 2. Arcs-mini 设备与固件

| 资料 | 地址 | 用途 |
|---|---|---|
| 开发板简介（短链） | <https://docs2.listenai.com/x/Ml1uU-api> | 板级规格、GPIO 分配、配件参数 |
| 芯片介绍（LS26） | <https://docs2.listenai.com/x/b9A9VXa6V> | SoC 规格（CPU/NPU/PSRAM/Wi-Fi/BT/外设） |
| Agent 搭建开发环境 | <https://docs2.listenai.com/x/93s9alx8D> | 用 AI 助手搭 ARCS 开发环境（固件线） |
| 固件更新日志 | <https://docs2.listenai.com/x/zNDNSNU9b> | 各版本固件亮点与 `.lpk` 下载 |
| 固件烧录教程（ADB） | <https://docs2.listenai.com/x/IMbN1kL5H> | Recovery + cskburn desktop 烧录 |
| 固件仓库（公开） | `https://cloud.listenai.com/CSKG836746/arcs-sdk/public/arcs_mini` | 小应用运行时实现、`docs/miniapp.md`、板型配置 |
| 文档中心检索 | `ling wiki search <关键词>` | 官方文档中心全文搜索（CLI 自带，无需登录） |
| 提交工单 | <https://docs2.listenai.com/x/NdZewU-pL> | LSCloud 工单入口，问云端下发/上架流程 |
| 官方 Skills 合集 | <https://github.com/LISTENAI/skills> | `arcs-dev-tools`（固件工具链：编译/烧录/串口/JLink） |

> 固件仓库是**端侧开发**的真相源；小应用开发只需要它来查"设备能力与限制"，不需要编译它。

## 3. 平台与 CLI

| 资料 | 地址 | 用途 |
|---|---|---|
| 聆思平台 | <https://platform.listenai.com> | 应用、角色、唤醒词、知识库、API Key |
| API Key 页 | <https://platform.listenai.com/keys> | 生成 `ling login` 用的 Key |
| `ling` CLI 仓库 | <https://github.com/LISTENAI/ling> | CLI 源码与完整命令文档 |
| `ling` Agent Skill | `npx skills add LISTENAI/ling` | 让 AI 帮你操作平台（已装：`~\.agents\skills\ling`） |
| LSCloud | <https://cloud.listenai.com> | 工单与项目协作 |

## 4. 参考项目（文档组织方式）

| 资料 | 地址 | 用途 |
|---|---|---|
| FoloToy ai-passport | <https://github.com/FoloToy/ai-passport> | 本仓库文档分层的参考样式（AGENTS.md 做薄路由 + docs 分区） |

## 5. 本仓库的经验条目

踩过的坑、实测结论写进 `docs/reference/<主题>.md`（按主题命名，不用编号），
每条写清：**现象 → 根因/证据 → 正确做法 → 怎么验收**。写之前先确认它不是硬件事实
（那属于 `docs/hardware/`）也不是运行时契约（那属于 `development/miniapp-runtime.md`）。
