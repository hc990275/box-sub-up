# Box-sub-up

这是一个专为 **Box for Root** (Magisk/KernelSU/APatch 模块) 打造的订阅自动更新扩展工具。它能够智能识别您的 Box 配置，并根据您的选择，精准、定时地自动刷新订阅内容。

## 🚀 核心功能

- **智能配置关联**：自动读取 `settings.ini` 并解析指向的 `config.json` 或 `config.yaml`。
- **机场精准映射**：自动扫描配置文件内的 `providers`，提取项目名称及其专属文件路径。
- **自定义监控列表**：支持在 WebUI 中勾选需要自动守护的机场项目，实现按需更新。
- **实时状态感知**：动态显示 Box 运行内核、网络模式、代理模式及进程 PID。
- **分钟级定时逻辑**：支持自定义更新频率，并在每次更新前强制检测 Box 运行状态。
- **精准 Mtime 监控**：不再盲目提示成功，只有当对应的订阅文件确实发生写入时才记为更新。

## 🛠️ 工作原理

1. **侦测阶段**：脚本启动或 WebUI 加载时，会解析 Box 系统的 `settings.ini`，确定活跃的核心 (bin_name) 及其主配置文件。
2. **解析阶段**：解析主配置文件，获取订阅项目的 `tag` 与具体的 `path`（文件存储位置）。
3. **循环阶段**：后台守护进程 `box-sub-up.sh` 根据设定的 `INTERVAL` 周期运行。
4. **校验阶段**：
   - 检查 Box 是否正在运行。
   - 记录订阅文件当前的时间戳 (mtime)。
   - 调用 Clash API 触发 `PUT` 更新。
   - 等待同步后，再次校验时间戳，确保订阅已真实写入硬盘。
5. **反馈阶段**：将更新结果记录至 `/sdcard/Android/sub.log`，并推送到 WebUI 可视化面板。

## 📦 安装说明

1. 确保已安装 **Box for Root** 模块并正常运行
2. 在 Magisk/KernelSU/APatch 中刷入本模块的 zip 包
3. 重启设备
4. 在面具模块列表中点击本模块的"设置"图标进入 WebUI
5. 选择需要监视的订阅项目，设置更新间隔，点击"保存配置并启动监控"

## 📋 版本日志

### v1.6.0 (2026-04-07)
- **fix**: 添加 `META-INF` + `customize.sh` 标准 Magisk 安装架构，修复面具无法显示更新按钮的问题
- **fix**: 修复 WebUI 中 `settings.ini` 路径错误（`/data/adb/box/box/` → `/data/adb/box/`），解决无法获取机场映射的问题
- **fix**: 修复 mihomo `proxy-providers` YAML 解析正则，正确提取标准格式的订阅项
- **fix**: 修复 `sub_config.conf` 默认间隔从 1800 分钟改为 30 分钟
- **fix**: 增加 sing-box `outbound_providers` 兼容解析
- **fix**: 添加 DOM 元素引用声明，解决潜在的 JS 变量未定义问题
- **fix**: 清理 HTML 中多余的 `</script>` 标签

### v1.5.2 (2026-04-07)
- **feat**: 初始版本，支持 WebUI 可视化配置
- **feat**: 智能侦测 Box 核心与配置文件
- **feat**: 支持 mihomo/sing-box 双内核解析
