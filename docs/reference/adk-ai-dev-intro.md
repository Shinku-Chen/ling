# ADK（聆思 AI 辅助开发套件）参考

- **官方文档**：https://docs2.listenai.com/x/RVkfzj5y2 （等同 https://docs2.listenai.com/zh/VibeCoding/AI辅助开发介绍 ）
- **文档标题**：AI辅助开发介绍 | 聆思文档中心
- **检索方式**：`ling wiki search ADK`
- **抓取日期**：2026-10-10（正文由预渲染 HTML 取得）
- **抓取提示**：该站点是 SPA；有时返回预渲染正文、有时只返回壳页面。抓不到时重试几次即可。

## 正文

### ¶ Vibe Coding 配套开发工具体系介绍
### ¶ 一、开发工具体系介绍
本工具体系包含面向AI编程助手的Skill：ling，面向嵌入式开发的设备端ADK和面向云侧业务开发的云侧ADK，开发者只需描述需求，就能完成端侧固件和云侧服务的开发、部署与验证。
-
ling skill：为端云交互开发工作流固化最佳实践，为编程助手提供端云全链路开发指引。
-
设备端ADK：内置coding、device、flash、run-log等端侧开发skill，并配套固件编译、ADB/串口烧录、日志采集等开发工具，实现端侧大模型开发调试闭环
-
云端ADK：包含ling CLI和业务功能模板。
- ling CLI：能够进行LSPlatform平台开发、部署、调试、配置的命令行工具。
- 业务功能模板：小聆AI Agent 的模板项目，包含端云协议处理和完整业务流程，可用于业务的二次开发。
### ¶ 开发流程图
### ¶ 二、 进入开发流程
参考文档《快速开始》，跑通一个agent开发的简单流程。

## 与本项目工作方式的关系

| ADK 组成 | 说明（官方） | 本项目的对应做法 |
|---|---|---|
| Skill：ling | 面向 AI 编程助手的端云交互开发最佳实践 | 已安装并使用（`ling` 1.0.1） |
| 设备端 ADK | 内置 coding / device / flash / run-log 等端侧 skill；配套固件编译、ADB/串口烧录、日志采集 | 自建近似工具链：`validate` / `build` / `upload` / `screenshot-device` / `screen-analyze` / `dev-restart` / `cskburn` |
| 云端 ADK | ling CLI + 业务功能模板 | 未使用（本项目产品形态是社区小应用 + 定向固件补丁） |

**结论**：本项目与 ADK 理念一致（描述需求 → 开发 → 部署 → 验证闭环），
但产物与发布路径不同（社区小应用 + 定向固件补丁，而非标准端侧固件/云侧服务）。
