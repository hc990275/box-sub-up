#!/system/bin/sh
# Magisk 模块 Action 脚本

MODDIR=${0%/*}
LOG_FILE="/storage/emulated/0/Android/sub.log"

# 显示当前日志信息
if [ -f "$LOG_FILE" ]; then
    echo "最近更新状态："
    cat "$LOG_FILE"
else
    echo "暂无运行记录，请确保 sing-box 已启动且 API 正常。"
fi

# 手动触发一次
echo "\n正在尝试触发即时更新..."
/system/bin/sh "$MODDIR/box-sub-up.sh" &
echo "请求已发出，后台正在刷新。"
