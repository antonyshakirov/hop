<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop 应用图标 — 四线星号">

# Hop

**macOS 菜单栏里的小巧全能助手：计时器、时间跟踪、待办、防休眠、
系统监控、剪贴板历史、文件转换器、窗口管理器和轻量 BT 客户端。
你只打开需要的，再分布到图标上多达四个标签里。轻轻一点——你需要的一切都在眼前。**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · **中文** · [日本語](README.ja.md)

<img src="https://hop.tools/screens/zh/overview.webp" width="360" alt="Hop 面板 — 菜单栏计时器，点阵显示屏、预设与工作-休息循环">

</div>

Hop 常驻在 Mac 的菜单栏中，一个应用顶替一把小工具：
番茄钟式计时器、带待办清单的时间跟踪、caffeinate 式防休眠、系统监控、
剪贴板管理器、拖放式文件转换器、窗口吸附和轻量 BT 客户端——
一个轻量的原生应用，把你常用的模块分布在图标上多达四个标签里。

## 下载

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — 打开后把 `Hop.app` 拖入「应用程序」即可（推荐）
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — 同一应用的普通压缩包（供内置更新器使用）；见[最新版本](https://github.com/antonyshakirov/hop/releases/latest)
- 高速镜像：[hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Hop 使用 Apple Developer ID 签名并通过 Apple 公证，macOS 会像打开任何其他应用一样打开它。源代码公开，内置更新使用
Ed25519 验证。需要 macOS 14 或更高版本。

## 功能

### 空间

图标上最多可放四个标签，你可以把每个模块拖到想要的标签里：计时器放一个，
监控放另一个，不常用的收到一旁。模块旁的电源按钮可以关闭它：它保留原位，但不再运行 —— 没有快捷键、没有标记，后台也不再收集任何东西。

### 计时器与循环

点阵倒计时，一个手势即可设定：拖动数字、像微波炉那样直接输入时间，
或选一个预设。工作-休息循环（25/5 番茄钟、52/17、90/15——也可以自定义）、
秒表、可在试用另一个计时器时暂存正在运行的那个，
以及结束提醒——还能顺便帮你暂停正在播放的媒体。倒计时结束时会响一声，
数字会一直闪烁，直到你复位。

<div align="center">
<img src="https://hop.tools/screens/zh/timer.webp" width="420" alt="Hop — 计时器与循环">
</div>

→ [Pomodoro timer for Mac](https://hop.tools/features/pomodoro-timer/)

### 时间跟踪与待办

任务可以归进项目，每个项目带着自己的合计，列表上方的开关切换今天、
本周或全部。任务运行时，行里数的是正在进行的这一段，从零开始；
旁边的✓结束这一段，行里重新显示区间合计。展开任务就能看到它的每一段时间：
改时长、改时刻、补一段没人按开始的工作，或删掉某条；手动修正也在同一个列表里，
所以每行加起来始终等于上面的总计。若某项跑得太久，满八小时会有横幅提醒。
旁边还有一份独立的待办清单，完成的项目会沉到底部。

点按任务即可展开：第一行是完整标题，下面是描述，星标表示收藏。待办事项还可以设置提醒——
选择日期、时间，以及任意重复的星期几——到点时 Hop 会提示你：带「稍后提醒」和「完成」的横幅、
声音、菜单栏标记，三者可分别开关。

**你的 AI 助手也能添加任务。** 列表就是一个普通的 JSON 文件，Hop 在运行时会实时读取它的改动。
Hop 还会执行命令文件并支持 `hop://` 链接：同一个助手，或者围绕这些链接做的快捷指令，
都可以启动计时器、添加带提醒的任务，或读取当前运行状态。详见
[docs/automation.md](../automation.md)。

<div align="center">
<img src="https://hop.tools/screens/zh/tracker.webp" width="420" alt="Hop — 时间跟踪与待办">
</div>

→ [Time tracker for Mac](https://hop.tools/features/time-tracker/)

### 防休眠

让 Mac 保持清醒 15 分钟、8 小时或永久——一次点击，无需密码。
可选择让屏幕常亮，或者合上盖子继续工作
（下载、长时间编译和外接显示器时特别好用）。

<div align="center">
<img src="https://hop.tools/screens/zh/awake.webp" width="420" alt="Hop — 防休眠">
</div>

→ [Keep your Mac awake](https://hop.tools/features/keep-mac-awake/)

### 系统监控

CPU 与 GPU 的负载和温度、内存与交换分区、网络、磁盘、电池健康度 和功耗——实时数值配迷你曲线图，颜
色阈值由你自己设定，支持 °C/°F， 还有一行开机时长。数据直接来自 macOS，且仅在标签页打开时更新。
内存这一行在大量内存被换到硬盘时也会提醒，而不只是在 macOS 自己报告吃紧的时候。

<div align="center">
<img src="https://hop.tools/screens/zh/system.webp" width="420" alt="Hop — 系统监控">
</div>

→ [System monitor for Mac](https://hop.tools/features/system-monitor/)

### 剪贴板历史

最近复制的 100 条（最多 300 条）内容——文字、图片和文件，一键复制回来，
或直接粘贴到上一个应用。复制的文件会按文件名记住（多个文件显示为
「名称 +N」），粘贴时会还原文件本身。密码等隐藏输入绝不会被记录。

<div align="center">
<img src="https://hop.tools/screens/zh/clipboard.webp" width="420" alt="Hop — 剪贴板历史">
</div>

→ [Clipboard history for Mac](https://hop.tools/features/clipboard-history/)

### 文件转换器

把一批图片、PDF、视频或音频拖到面板上：输出 JPEG、PNG、 HEIC、AVIF 和 WebP；压缩 PDF；HEVC 视频瘦身，转换前就能看到 实时且诚实的体积预估。所有处理均在本地完成。 视频还能在转换时重新构图 —— 9:16、4:5、正方形或 16:9，可裁切、加黑边，或叠在自身的模糊副本上 —— 压缩也有了自己的级别，转换前承诺的大小就是得到的大小。

一个按钮就把片子调成投放地要的样子— reels、feed、
tiktok、shorts 或 youtube —按平台自己的建议设定画幅、
分辨率和压缩强度，滑块旁写着对应的比特率。MKV 和 WebM 会先被重新封装成
 MP4（macOS 两个都打不开），由一个很小的辅助程序完成，
只下载一次。Pages、Numbers 和 Keynote 的文稿由这些应用自己
批量导出：PDF，或 docx、xlsx 和 pptx。

<div align="center">
<img src="https://hop.tools/screens/zh/converter.webp" width="480" alt="Hop — 文件转换器">
</div>

→ [File converter for Mac](https://hop.tools/features/file-converter/)

### 窗口管理器

点击区域图标或按 ⌃⌥ 快捷键，即可把窗口吸附到二分之一、四分之一、
三分之一或居中——无需额外安装任何应用。

<div align="center">
<img src="https://hop.tools/screens/zh/windows.webp" width="420" alt="Hop — 窗口管理器">
</div>

→ [Window manager for Mac](https://hop.tools/features/window-manager/)

### 种子下载

同一面板里的轻量 BT 客户端：拖入 .torrent 文件或粘贴 magnet 链接，
精确挑选要下载的文件——下载开始前甚至进行中都可以——支持暂停、
恢复和做种，还可选择在分享率达到 1.0 时自动停止。该模块默认关闭；
启用后会单独下载开源引擎（约 26 MB，经签名校验），它只通过本地
端口与 Hop 通信。Hop 还可以成为 .torrent 文件和 magnet 链接的
默认应用。

<div align="center">
<img src="https://hop.tools/screens/zh/torrents.webp" width="420" alt="Hop 种子下载 — 菜单栏面板中的轻量 BT 客户端">
</div>

→ [Lightweight torrent client for Mac](https://hop.tools/features/torrent-client/)

### 文件压缩包

模块那一行会打开一个窗口，拖放就在那个窗口里进行 —— ⌘V 也可以，一次多个文件。加进来的文件会先排成
一份列表，直到你按下按钮：压缩包会被解压，其余文件会打包成一个压缩包。结果默认放到桌面，也可以放在
原件旁边或任何你选择的文件夹。支持 zip、rar、7z、tar、tar.gz、tar.bz2、tar.xz 和 gz；遇到 rar 和 7z
时会在第一次下载一个约 6 MB 的小助手，并校验签名。Hop 能解 rar，但从不创建它 —— 这个格式是专有的。
设置里的「Hop 作为压缩包的默认程序」只会在没有 Apple 应用接管时提供 rar，并可从第三方应用手里收回 rar；
zip、7z 和原生格式仍留给「归档实用工具」。模块隐藏时同样有效，卡片显示的是真实状态。 在访达里双击压缩包，会就地在文件旁边解压，并单独弹出一个小的进度窗口；即使失败也不会留下任何隐藏的东西。由 Hop 打开的文件都带有自己的图标，上面写着格式，一整个文件夹一眼就能看清。

<div align="center">
<img src="https://hop.tools/screens/zh/archives.webp" width="480" alt="Hop — 文件压缩包">
</div>

→ [Unzip rar, 7z and zip on your Mac](https://hop.tools/features/archive-manager/)

### 文档

转换器学会了文档：markdown → PDF 由 Hop 自己排版，Word 文件（.docx、.doc、.rtf）
→ PDF 或 markdown，以及把 PDF 里的文字提取成 markdown——扫描页由 Apple 的 Vision
识别。全部原生、离线，不捆绑办公套件，也不需要下载。

→ [Document conversion on Mac](https://hop.tools/features/file-converter/)

### 颜色取色器

用系统放大镜取屏幕上的任意颜色，它会留在列表里：每一行的 hex、rgb 和 hsl 各占一列，点哪一个就复制
哪一种写法。顺序不会在光标下变动，保留多少颜色、显示几行都可设置，也不需要录屏权限：放大镜只返回
一个颜色。

<div align="center">
<img src="https://hop.tools/screens/zh/colors.webp" width="420" alt="Hop — 颜色取色器">
</div>

→ [Color picker for Mac](https://hop.tools/features/color-picker/)

### 文字识别

框选屏幕上的一块区域，或者把图片拖进窗口、用 ⌘V 粘贴：其中的文字和二维码会出现在一个可阅读、可
编辑、可复制的窗口里，同时进入剪贴板历史。换行会保留，表格依然可读。识别用的是 Apple 的 Vision，
全部在这台 Mac 上完成。

如果识别结果里有网址，会出现「打开链接」按钮：账单二维码里的链接直接在浏览器中打开，不用再掏手机
。只认网址：扫来的码是外来输入，所以电话号码、Wi-Fi 密码或名片仍然只是普通文本。

<div align="center">
<img src="https://hop.tools/screens/zh/recognition.webp" width="480" alt="Hop — 文字识别">
</div>

→ [Text recognition for Mac](https://hop.tools/features/text-recognition/)

→ [Scan a QR code on your Mac](https://hop.tools/features/scan-qr-code-on-mac/)

### 键盘锁定

点 1、5 或 15 分钟 —— 或者 ∞ —— 整块键盘就不再响应，方便擦拭，而不必关机或合盖。一层遮罩会说明
正在发生什么，菜单栏图标也会变成键盘。四种解除方式：遮罩上的按钮、面板里的按钮、打开面板，或者
长按 esc + shift 五秒。电源键的短按同样被吞掉；长按仍会强制关机，因为那是硬件负责的。

<div align="center">
<img src="https://hop.tools/screens/zh/keyboard.webp" width="480" alt="Hop — 键盘锁定">
</div>

→ [Lock your Mac keyboard](https://hop.tools/features/keyboard-lock/)

### 网速测试

一次点按就用 macOS 自带的 networkQuality 对着 Apple 的服务器测一遍——下行、上行和响应，最后一次结果留在这一行里。

<div align="center">
<img src="https://hop.tools/screens/zh/speed.webp" width="420" alt="Hop — 网速测试">
</div>

→ [Internet speed test for Mac](https://hop.tools/features/internet-speed-test/)

### 菜单栏图标

图标上带着小小的标记：正在走的时间、防休眠、响过的提醒、VPN 连着时的圆点（什么都不通时变橙），以及torrent 传输时的箭头——彩色或单色，每个都能单独关掉。Hop 自己的窗口在打开时会出现在程序坞里，点一下就把窗口叫回来，而不是先打开面板；最后一个窗口关掉，图标也随之离开。

### 主题、快捷键与安全模式

深色与浅色主题，带胶片颗粒质感；全局快捷键；登录时启动；还有把应用从崩溃循环里救出来的安全模式——全都在同一个设置窗口里。

<div align="center">
<img src="https://hop.tools/screens/zh/settings.webp" width="480" alt="Hop — 设置">
</div>

### VPN

你的 Mac 知道的所有 VPN，每个一个开关，不论出自哪家。Hop 直接从系统设置读取这份列表：
昨天装的客户端会自动出现，卸载的会消失。这里没有什么要添加，也不用等待对某一家的适配。

不用打开任何窗口就能连上或断开。只要有一条隧道在跑，菜单栏图标一角就会亮起一个小圆点，和其他指示灯并排，面板关着也看得见。有东西在通时是绿色；隧道开着却什么也回不来时变成橙色，悄悄断掉的连接不再看着像正常的，面板还会标出是哪一行。点一下名称，就会打开那个 VPN 自己的窗口，用完关掉，
Hop 会把它退出。连接不会断——隧道由系统维持，而不是应用。

这一行显示的是客户端自己报告的内容：它的名字，以及括号里配置附加的信息，通常是国家。
Hop 从不根据服务器地址猜测国家：地址注册表说明的是号段在哪里注册，而不是机器在哪里。

这个绿点可以在设置里关掉，模块和开关照常工作。

<div align="center">
<img src="https://hop.tools/screens/zh/vpn.webp" width="420" alt="Hop — VPN 开关">
</div>

→ [VPN switcher for Mac](https://hop.tools/features/vpn-switcher/)

### 应用

一整天都在开的程序摆成网格，一键可达，不必再去应用程序文件夹。按 + 挑选，或从访达拖进来；每行九个，最多八行。

拖动图标即可挪位：黄色竖线显示它将插入到哪两个图标之间，其余图标自动让位，就像主屏幕一样。编辑按钮启动轻轻摇摆，每个图标带一个 ✕，网格也可以自己命名；如果您本来就认得这些应用，还可以在那里关掉图标下方的名称。网格想要几个就有几个——工作放一个空间，其余放另一个，各有各的应用。

网格在您排列模块的地方创建和删除：设置里，或者模块表格本身——表格里网格方块上的 ✕ 会把它彻底删掉。新网格一开始是空的，在您填满之前会这样写着。

<div align="center">
<img src="https://hop.tools/screens/zh/apps.webp" width="420" alt="Hop — 应用格子">
</div>

→ [App launcher for Mac](https://hop.tools/features/app-launcher/)

### 卸载应用

把应用拖到这一行，或者从已安装列表里挑一个，它会连同散落在大约三十处的东西一起离开：application support、缓存、偏好设置、容器、launch agents、插件、安装回执等等。列表里每个应用都标着它有多大，应用本体和数据分开列出。已经进了废纸篓的应用同样能认出来：标识符从废纸篓里的包中读取，或者从写着它名字的残留里推断。

什么都不会被直接删除。一切先进废纸篓，所以出错的代价是恢复一次，而不是丢一个文件；macOS 不肯交出的部分会连同原因一起点名，而不是悄悄跳过。

<div align="center">
<img src="https://hop.tools/screens/zh/uninstall.webp" width="480" alt="Hop — 连同应用留下的一切一起卸载">
</div>

同一个模块也能只整理、不卸载：所有占着缓存的应用，大的在前；留在下载、桌面和文稿里的安装包；多年前删掉的应用留下的数据；还有废纸篓和它的大小。一个勾选拿走一整节。它有意不碰的东西也列在那里——缓存和数据挤在同一个文件夹里的容器，比如某个即时通讯的二十多 GB：哪一半可以丢，只有那个应用自己知道。

<div align="center">
<img src="https://hop.tools/screens/zh/clean.webp" width="480" alt="Hop — 清理缓存、安装包、残留和废纸篓">
</div>

→ [Uninstall apps on your Mac](https://hop.tools/features/app-uninstaller/)

## 22 种语言

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — 应用开箱即用，自动跟随系统语言。

## 支持这个项目

Hop 是免费的，而且会一直免费。如果它在你的菜单栏里挣到了一个位置，自愿的一点支持能帮助
继续做新功能、把已有的打磨得更好 —— 它买的是时间，别无他用。

**[→ 支持 Hop](https://web.tribute.tg/d/Nvk)**

## 隐私 —— 以及为什么这些权限可以放心给

**Hop 不收集任何东西。现在不会，以后也不会。** 没有自己的服务器，没有分析统计，没有遥测，
没有账号，不上报崩溃。下面的每一项权限，都只有在你真正使用需要它的功能时才由 macOS 询问，
而且它存在的唯一目的就是让那个功能能用 —— 不会顺手收集任何数据。这一点不用你信我的话：
应用是开源的，那种用来收集数据的代码根本不存在。在这个仓库里搜一搜追踪 SDK 或分析调用，
你找不到。

一切都在本地运行：没有服务器、没有分析统计、没有账号。
应用仅在检查更新、运行内置测速，以及启用 BT 模块后一次性下载引擎
和传输 BT 流量本身时才会访问网络。检查更新时只会发送你正在使用的
版本，不包含任何能识别你或你的 Mac 的信息。更新和 BT 引擎均以签名
压缩包形式分发，安装前会用 Ed25519 签名进行校验。

## 权限

只有当你真正使用某个功能时，Hop 才会申请它需要的权限；应用的设置窗口里列出了全部
权限及其当前状态：

- **网络 — hop.tools** — 检查并下载更新，以及两个可选辅助程序（torrent
  引擎与 7-Zip 压缩工具）
- **网络 — torrent、测速** — 开启 torrent 模块时与其他用户的流量；测速使用 macOS
  自带的 networkQuality，对 Apple 的服务器进行
- **辅助功能** — 粘贴到下面那个应用、窗口管理器和键盘锁定
- **录屏** — 仅文字识别模块需要，而且只在框选区域时；颜色取色器不需要
- **通知** — 计时结束提醒和 torrent 完成提示
- **管理员密码** — 一次，用于合盖模式（pmset 需要 root）
- **登录时启动** — 默认关闭，你可以自行打开

启动时不申请任何权限，也不会为你没有打开的模块申请权限。没有分析统计、没有遥测、没有账号、不上报崩溃：
访问 hop.tools 只是为了询问是否有新版本 —— 以及在你同意时下载它，或下载两个可选小助手之一。
其余一切都留在这台 Mac 上：剪贴板历史、记录的时间、待办清单、识别出的文字和取到的颜色。

上面每一项权限都只是为了让某个功能能用，没有别的用途。这一点不用你信我的话：Hop 是开源的，
那种用来收集数据的代码根本不存在 —— 就在这个仓库里读它。应用的设置窗口里有「应用权限」页面，
列着同样的清单和每项权限的当前状态。

升级到 1.10.0 会把所有权限清空一次并重新申请。权限绑定在代码签名上，而 Hop 的签名在
Apple 为它签名时变了：授予旧签名的权限仍留在列表里，却已经不起作用。从 1.10.0 起，
权限能挺过更新。

官网：[hop.tools](https://hop.tools)

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

三种方式，每一种都欢迎：

- **[用一份支持帮助 Hop](https://web.tribute.tg/d/Nvk)** —— 它会直接变成新功能和
  修复。完全自愿，没有回报档位，也没有任何付费内容：每个模块对所有人都一样。
- **[给仓库点个 star](https://github.com/antonyshakirov/hop/stargazers)** —— 别人
  正是通过 star 找到它的。
- **[提一个 issue](https://github.com/antonyshakirov/hop/issues)** —— 一份缺陷
  报告或一个想法，价值同样不小。

## 作者与许可

由 [Anton Shakirov](https://www.antonshakirov.com/en) 打造。基于
[MIT 许可证](../../LICENSE)发布：可自由使用和修改，但需保留版权声明——
把这个应用冒充为你自己的作品即违反许可证。
