#!/system/bin/sh
# Box-sub-up 卸载清理脚本
# 该脚本会在用户从面具/KernelSU管理器卸载本模块时自动执行，用于清理残留的配置文件和日志

# 定义配置和日志路径
CONF_FILE="/storage/emulated/0/Android/sub_config.conf"
LOG_FILE="/storage/emulated/0/Android/sub.log"
DEBUG_LOG_FILE="/storage/emulated/0/Android/sub_debug.log"
BAK_DIR="/storage/emulated/0/Android/box_config_bak"

echo "开始清理 Box-sub-up 残留文件..."

# 删除配置文件
if [ -f "$CONF_FILE" ]; then
    rm -f "$CONF_FILE"
    echo "已删除: $CONF_FILE"
fi

# 删除运行日志
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    echo "已删除: $LOG_FILE"
fi

# 删除调试日志
if [ -f "$DEBUG_LOG_FILE" ]; then
    rm -f "$DEBUG_LOG_FILE"
    echo "已删除: $DEBUG_LOG_FILE"
fi

# 如果存在旧版或备份文件夹也一并清理
if [ -d "$BAK_DIR" ]; then
    rm -rf "$BAK_DIR"
    echo "已删除旧版备份文件夹: $BAK_DIR"
fi

echo "Box-sub-up 残留垃圾文件清理完毕！"
