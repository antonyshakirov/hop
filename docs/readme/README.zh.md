<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop 应用图标 — 四线星号">

# Hop

**macOS 菜单栏里的小巧全能助手：计时器、时间跟踪、待办、防休眠、
系统监控、剪贴板历史、文件转换器、窗口管理器和轻量 BT 客户端——
分布在图标上多达四个标签里。轻轻一点——你需要的一切都在眼前。**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · **中文** · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/zh/panel.png" width="420" alt="Hop 面板 — 菜单栏计时器，点阵显示屏、预设与工作-休息循环">

</div>

Hop 常驻在 Mac 的菜单栏中，一个应用顶替一把小工具：
番茄钟式计时器、带待办清单的时间跟踪、caffeinate 式防休眠、系统监控、
剪贴板管理器、拖放式文件转换器、窗口吸附和轻量 BT 客户端——
一个轻量的原生应用，把你常用的模块分布在图标上多达四个标签里。

## 下载

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — 打开后把 `Hop.app` 拖入「应用程序」即可（推荐）
- `Hop-x.y.z.zip` — 同一应用的普通压缩包（供内置更新器使用）；见[最新版本](https://github.com/antonyshakirov/hop/releases/latest)
- 高速镜像：[hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

首次启动：右键点击 `Hop.app` → **打开** → 确认
（应用尚未经过公证）。需要 macOS 14 或更高版本。

## 功能

### 空间

图标上最多可放四个标签，你可以把每个模块拖到想要的标签里：计时器放一个，
监控放另一个，不常用的收到一旁。「不活跃」搁架会保留你搁置的模块，而不删除它们。

### 计时器与循环

点阵倒计时，一个手势即可设定：拖动数字、像微波炉那样直接输入时间，
或选一个预设。工作-休息循环（25/5 番茄钟、52/17、90/15——也可以自定义）、
秒表、可在试用另一个计时器时暂存正在运行的那个，
以及结束提醒——还能顺便帮你暂停正在播放的媒体。倒计时结束时会响一声，
数字会一直闪烁，直到你复位。

### 时间跟踪与待办

在一份扁平的任务列表上记录时间：每行显示今天的用时和累计总量，今天的
数字也可以手动修正。若某项跑得太久，满八小时会有横幅提醒。旁边还有一份
独立的待办清单，完成的项目会沉到底部。

### 防休眠

让 Mac 保持清醒 15 分钟、8 小时或永久——一次点击，无需密码。
可选择让屏幕常亮，或者合上盖子继续工作
（下载、长时间编译和外接显示器时特别好用）。

### 系统监控

CPU 与 GPU 的负载和温度、内存与交换分区、网络、磁盘、电池健康度
和功耗——实时数值配迷你曲线图，颜色阈值由你自己设定，支持 °C/°F，
还有一行开机时长。数据直接来自 macOS，且仅在标签页打开时更新。

### 剪贴板历史

最近复制的 100 条（最多 300 条）内容——文字、图片和文件，一键复制回来，
或直接粘贴到上一个应用。复制的文件会按文件名记住（多个文件显示为
「名称 +N」），粘贴时会还原文件本身。密码等隐藏输入绝不会被记录。

### 文件转换器

把一批图片、PDF、视频或音频拖到面板上：输出 JPEG、PNG、
HEIC、AVIF 和 WebP；压缩 PDF；HEVC 视频瘦身，转换前就能看到
实时且诚实的体积预估。所有处理均在本地完成。

### 窗口管理器

点击区域图标或按 ⌃⌥ 快捷键，即可把窗口吸附到二分之一、四分之一、
三分之一或居中——无需额外安装任何应用。

### 种子下载

同一面板里的轻量 BT 客户端：拖入 .torrent 文件或粘贴 magnet 链接，
精确挑选要下载的文件——下载开始前甚至进行中都可以——支持暂停、
恢复和做种，还可选择在分享率达到 1.0 时自动停止。该模块默认关闭；
启用后会单独下载开源引擎（约 26 MB，经签名校验），它只通过本地
端口与 Hop 通信。Hop 还可以成为 .torrent 文件和 magnet 链接的
默认应用。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/zh/torrents.png" width="420" alt="Hop 种子下载 — 菜单栏面板中的轻量 BT 客户端">
</div>

### 其他

图标上小巧的状态指示器——时间、防休眠、警示和种子活动，彩色或单色——
内置测速（Apple 的 networkQuality）、带胶片颗粒质感的深浅两套主题、
全局快捷键、登录时启动，以及能从崩溃循环中恢复应用的安全模式。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/zh/system.png" width="280" alt="Hop 系统监控 — CPU、GPU、内存、网络、磁盘、电池图表">
<img src="https://www.antonshakirov.com/products/hop/screens/zh/converter.png" width="280" alt="Hop 文件转换器 — 批量转换图片、PDF、视频和音频">
<img src="https://www.antonshakirov.com/products/hop/screens/zh/settings.png" width="280" alt="Hop 设置 — 主题、模块、快捷键、18 种语言">
</div>

## 18 种语言

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — 应用开箱即用，自动跟随系统语言。

## 隐私

一切都在本地运行：没有服务器、没有分析统计、没有账号。
应用仅在检查更新、运行内置测速，以及启用 BT 模块后一次性下载引擎
和传输 BT 流量本身时才会访问网络。更新和 BT 引擎均以签名压缩包
形式分发，安装前会用 Ed25519 签名进行校验。

官网：[antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## 为什么免费

Hop 完全免费：没有试用期，没有专业版，没有内购。没有广告，不收集数据，没有账户——没有什么可变现的，也没有什么可出售的。这是一个个人项目：我为自己做了 Hop，每天都在用，只是分享出来而已。如果它对你有用，就分享给别人吧。如果你愿意出一份力，现在也可以支持 Hop——纯粹是一份心意，没有任何附加回报。

## 从源码构建

Swift Package Manager，macOS 14+，零外部依赖：

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

开发流程、发布流水线和行为规范见
[docs/development.md](../development.md) 和 [docs/spec.md](../spec.md)。

## 支持这个项目

如果 Hop 帮你省下了哪怕一两次点击，**[给仓库点个星](https://github.com/antonyshakirov/hop/stargazers)**——
星标是别人发现它的方式。欢迎在 [Issues](https://github.com/antonyshakirov/hop/issues)
提交 Bug 报告和功能建议。

## 作者与许可

由 [Anton Shakirov](https://www.antonshakirov.com/en) 打造。基于
[MIT 许可证](../../LICENSE)发布：可自由使用和修改，但需保留版权声明——
把这个应用冒充为你自己的作品即违反许可证。
