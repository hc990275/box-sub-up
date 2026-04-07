#!/system/bin/sh

# Box Subscription Auto-Updater 安装脚本

SKIPUNZIP=1

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! 请在 Magisk/KernelSU/APatch Manager 中安装本模块"
  ui_print "! 不支持从 Recovery 安装"
  abort "-----------------------------------------------------------"
fi

ui_print " "
ui_print "==========================================================="
ui_print "==     Box Subscription Auto-Updater 安装中...            =="
ui_print "==========================================================="

# 检测面具环境
if [ "$KSU" = "true" ]; then
  ui_print "- 检测到 KernelSU 版本: $KSU_VER ($KSU_VER_CODE)"
elif [ "$APATCH" = "true" ]; then
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- 检测到 APatch 版本: $APATCH_VER"
else
  ui_print "- 检测到 Magisk 版本: $MAGISK_VER ($MAGISK_VER_CODE)"
fi

# 检查 Box for Root 是否已安装
if [ ! -d "/data/adb/box" ] && [ ! -d "/data/adb/modules/box_for_root" ]; then
  ui_print " "
  ui_print "⚠ 未检测到 Box for Root 模块！"
  ui_print "  本模块是 Box 的订阅更新扩展，需先安装 Box for Root。"
  ui_print "  安装将继续，但请确保之后安装 Box for Root。"
  ui_print " "
fi

# 解压模块文件
ui_print "- 正在安装模块文件..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

# 适配 service.d 目录 (为了更好的兼容性，部分管理器可能需要)
service_dir="/data/adb/service.d"
[ "$KSU" = "true" ] && [ "$KSU_VER_CODE" -lt 10683 ] && service_dir="/data/adb/ksu/service.d"

# 初始化或保护用户配置
CONF_PATH="/storage/emulated/0/Android/sub_config.conf"
if [ -f "$CONF_PATH" ]; then
  ui_print "- 检测到现有配置，正在保留..."
else
  ui_print "- 创建默认订阅配置..."
  mkdir -p "$(dirname "$CONF_PATH")"
  echo 'INTERVAL=30' > "$CONF_PATH"
fi

# 设置权限
ui_print "- 设置文件权限..."
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive $MODPATH/webroot 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/action.sh 0 0 0755
set_perm $MODPATH/box-sub-up.sh 0 0 0755

ui_print " "
ui_print "- ✅ 安装完成！"
ui_print "- 重启后模块将自动启动订阅更新守护进程。"
ui_print "- 请通过 WebUI 配置需要监视的订阅项目。"
ui_print "==========================================================="
