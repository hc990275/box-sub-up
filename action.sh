#!/system/bin/sh
# Magisk Action：手动触发一次订阅更新 + 显示日志

MODDIR=${0%/*}
LOG_FILE="/storage/emulated/0/Android/sub.log"

echo "━━━ Box-sub-up 手动更新 ━━━"
echo ""

# 执行单次更新
echo "⏳ 正在通过 Clash API 更新全部订阅..."
sh "$MODDIR/box-sub-up.sh" --once
echo ""

# 显示最近日志
if [ -f "$LOG_FILE" ]; then
    echo "━━━ 最近更新记录 ━━━"
    cat "$LOG_FILE"
else
    echo "暂无运行记录"
fi
