# 硬件事实

本目录是小应用开发所需的**硬件事实唯一真相源**。

## 真相优先级

1. 实测结果 / 官方规格（聆思文档中心、原理图）→
2. 本目录文档 →
3. 固件仓库（`apps/arcs-mini/prj.conf`、`arcs-sdk/boards/arcs_mini/`）→
4. 博客、二手资料。

新增或修改硬件事实时，必须写清来源（URL 或"仓库路径 + 文件"）。查不到的就问用户，不要猜。

## 文件

| 文件 | 内容 |
|---|---|
| [board-arcs-mini.md](board-arcs-mini.md) | LS26/Arcs-mini 的 SoC、板级规格、GPIO 分配、固件可见的内存与外设预算 |

## 与本仓库的关系

小应用**只**通过 `miniapp_runtime.md` 里那套 Lua API 访问硬件。引脚级操作（PWM、I2C、GPIO 直控、
屏幕 panel 切换）不属于小应用能力范围——那属于固件开发（见 [../reference/README.md](../reference/README.md)）。
