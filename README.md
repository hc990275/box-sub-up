# Box-sub-up

这是一个专为 **Box for Root** (Magisk/KernelSU/APatch 模块) 打造的订阅自动更新扩展工具。基于最新的 Clash API，提供极其简单、高效的无感全自动订阅更新体验。

## 🚀 核心功能 (v2.1.1)

- **无感适配**：完全抛弃繁琐的文件解析与路径映射，直接调用代理核心自带的 RESTful API 进行更新。
- **核心类型自动检测**：读取 `settings.ini` 中的 `bin_name` 字段自动识别当前运行的核心（mihomo / sing-box），不支持 API 的核心（xray / v2fly / hysteria）自动跳过，下个周期自动重新检测。
- **零配置，极简主义**：**更新间隔已写死为 30 分钟**，彻底移除了 `/sdcard` 目录下的外部配置文件，安装和运行更加纯粹。
- **一键全量更新**：自动遍历并刷新所有在线订阅项（Providers），无需手动配置。
- **动态发现机制**：每次更新时自动探测所有 Providers，核心配置改变后无需重新安装模块。
- **流量/到期可视化**：在 WebUI 面板中直接查看每个订阅的流量、更新时间和过期天数。
- **完全兼容 Box**：自动跟随 `settings.ini` 探测核心变动，自动读取控制端口和密钥，开箱即用。

## 🛠️ 工作原理

1. **侦测阶段**：读取 `/data/adb/box/settings.ini` 中的 `bin_name` 确定当前运行的核心类型。
   - `mihomo` → 订阅路径：`/data/adb/box/mihomo/proxy_provider/`
   - `sing-box` → 订阅路径：`/data/adb/box/sing-box/proxy_provider/`
2. **API 配置读取**：根据核心类型解析对应配置文件，提取 `external-controller` 端口和 `secret`。
3. **列表获取**：通过 `GET /providers/proxies` 请求代理核心，动态获取所有订阅项（Providers）名称。
4. **精准触发更新**：自动遍历所有项目，调用 `PUT /providers/proxies/{name}` 触发核心自行下载并热重载订阅节点。
5. **反馈阶段**：将结果记录至 `/sdcard/Android/sub.log`（保留最近 **10 条**），并在面具描述中动态展示核心类型与更新状态。

## 📦 安装说明

1. 确保已安装 **Box for Root** 模块并正常运行（核心必须支持 Clash API，推荐最新版 mihomo 或 sing-box）
2. 在 Magisk / KernelSU / APatch 中刷入本模块的 zip 包
3. 重启设备，模块开机自动启动守护进程
4. 在面具模块列表中点击本模块的"设置"图标进入 WebUI 面板
5. 可查看订阅状态、一键手动更新。后台自动更新周期已写死为 **30 分钟**。

日志文件：`/storage/emulated/0/Android/sub.log`（最近 10 条）
调试日志：`/storage/emulated/0/Android/sub_debug.log`

## 📋 版本日志

### v2.1.1 (2026-04-16)
* **feat:** 将更新间隔硬编码为 30 分钟，不再从外部文件读取。
* **refactor:** 彻底移除了 `/sdcard/Android/sub_config.conf` 配置文件及其相关逻辑，实现零配置交付。
* **chore:** 清理了 `customize.sh` 中的文件初始化代码，确保安装过程不产生额外垃圾文件。

### v2.1.0 (2026-04-16)
* **feat:** 读取 `settings.ini` 中的 `bin_name` 自动检测运行核心类型（mihomo / sing-box），根据核心确定 `proxy_provider` 目录路径并记录到调试日志。
* **feat:** xray / v2fly / hysteria 等不支持 Clash API 的核心自动跳过并打印提示，守护进程不中断，下个周期自动重新检测。
* **fix:** 日志保留条数从 15 条修正为 **10 条**。
* **fix:** 日志时间戳改为实时生成，不再使用启动时的静态时间。
* **refactor:** API 请求函数去掉 `eval`，改用直接调用，提升安全性和可读性。
* **refactor:** 主流程拆分为 `run_once` / `run_daemon` 两个函数，结构更清晰。
* **style:** `module.prop` 描述增加核心类型字段，在 Magisk/KSU 界面直接可见。
* **docs:** 更新 README 工作原理，补充核心类型与 proxy_provider 路径对应说明。

### v2.0.7 (2026-04-08)
* **fix:** 深层修复顶部信息显示 `(核心: 未知)` 问题（在读取 `settings.ini` 时主动剃除遗留的 Windows `\r` 换行符，避免正则匹配断裂）。
* **style:** 简化底部运行日志看板区，只展示更新时间与最终统计，隐藏过长的测速详情。

### v2.0.6 (2026-04-08)
* **fix:** 修复 KernelSU WebUI API 返回值解析错误导致的 `[[object Object]]` (KSU 采用 `.out` 而非预期的 `.stdout`)。

### v2.0.5 (2026-04-08)
* **chore:** 更新版本号为 `v2.0.5`，完善 `versionCode` 命名规范（采用 `YYYYMMDD + 当日序号`，防止整数溢出）。

### v2.0.4 (2026-04-08)
* **chore:** 精简版本号 (`v2.0.4`)，修复 `versionCode` 整数溢出导致无法挂载新界面的问题。

### v2.0.3-20260408 (2026-04-08)
* **fix:** 强制转换全量文件为 UNIX (LF) 换行符，根治 KSU 环境下因 CRLF 导致的无法加载/无 WebUI 问题。
* **feat:** 在安装界面动态读取并展示模块版本号。

### v2.0.2-20260408 (2026-04-08)
* **fix:** 根治 WebUI API 侦测失败问题 — 改用 shell 原生 source 解析 settings.ini 变量，彻底消除 JS 硬编码路径导致的端口连接失败。
* **fix:** 修复 Provider 名称含特殊字符时 WebUI 渲染崩溃和 XSS 风险，改用 data 属性 + 事件委托。
* **refactor:** WebUI 侦测逻辑与 box-sub-up.sh 后台脚本完全统一，共享同一套 awk 提取策略。

### v2.0.1 (2026-04-07)
* **fix:** 高度强化 WebUI 中的内核调用系统，完美解决部分纯净安卓系统因缺少 curl 引发的加载崩溃。
* **feat:** 新增 `uninstall.sh` 原生模块卸载钩子，卸载时自动清除配置和日志文件。

### v2.0.0 (2026-04-07)
* **refactor:** 彻底重构！全量迁移到 **Clash /providers API**，移除本地文件抓取与路径映射逻辑。
* **feat:** WebUI 全新改版，新增"一键更新全部"按钮，即显即用。
* **feat:** WebUI 中新增数据面板，展示订阅更新时间和内部类型。

### v1.6.0 (2026-04-07)
* **fix:** 尝试修复 WebUI 和环境的问题，优化文件树拦截等老版本解析问题。
