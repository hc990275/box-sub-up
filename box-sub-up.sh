#!/system/bin/sh
# sing-box 订阅后台自动定时更新脚本 (模块化适配版)

MODDIR=${0%/*}
API="http://127.0.0.1:9090"
LOG_FILE="/storage/emulated/0/Android/sub.log"
CONF_FILE="/storage/emulated/0/Android/sub_config.conf"

# 默认更新间隔（分钟）
DEFAULT_INTERVAL=30

# 等待系统启动完成
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
done
sleep 10 # 模块运行通常比脚本慢一点点，减少延迟

# 检测 Box 是否运行
check_box_running() {
    # 常用检测路径：Box 通常在 /data/adb/box/run/cache 记录状态，或检查核心进程 box
    if pidof box > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

while true; do
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        INTERVAL=$DEFAULT_INTERVAL
        CORE_TYPE=""
    fi

    CURRENT_TIME=$(date "+%m-%d %H:%M:%S")

    # 基础运行预检
    if ! check_box_running; then
        SUMMARY_LOG="[$CURRENT_TIME] Box未运行，跳过更新。"
        [ -f "$LOG_FILE" ] && echo "$SUMMARY_LOG" | cat - "$LOG_FILE" | head -n 15 > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" || echo "$SUMMARY_LOG" > "$LOG_FILE"
        sleep $((INTERVAL * 60))
        continue
    fi

    # 映射有效性预检
    if [ -z "$WATCH_MAP" ] || [ -z "$MAIN_CONF" ]; then
        SUMMARY_LOG="[$CURRENT_TIME] 未配置机场映射，请前往 WebUI 设置。"
        [ -f "$LOG_FILE" ] && echo "$SUMMARY_LOG" | cat - "$LOG_FILE" | head -n 15 > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" || echo "$SUMMARY_LOG" > "$LOG_FILE"
        sleep $((INTERVAL * 60))
        continue
    fi

    # 获取配置文件的基准目录 (用于处理相对路径 ./)
    CONF_BASE=$(dirname "$MAIN_CONF")
    SUMMARY_LOG="[$CURRENT_TIME]"

    # 解析映射并执行精准更新
    # 映射格式: tag1|path1;tag2|path2
    IFS=';'
    for pair in $WATCH_MAP; do
        TAG=$(echo "$pair" | cut -d'|' -f1)
        REL_PATH=$(echo "$pair" | cut -d'|' -f2)
        
        # 处理相对路径转换为绝对路径
        if [[ "$REL_PATH" == ./* ]]; then
            ABS_PATH="$CONF_BASE/${REL_PATH#./}"
        else
            ABS_PATH="$REL_PATH"
        fi

        # 记录更新前时间戳
        PRE_MTIME=0
        [ -f "$ABS_PATH" ] && PRE_MTIME=$(stat -c %Y "$ABS_PATH")

        # 触发 API 更新 (使用 TAG 作为标识)
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$API/providers/proxies/$TAG" -d "" --max-time 30)
        
        # 等待同步并检查
        sleep 1.5
        POST_MTIME=0
        [ -f "$ABS_PATH" ] && POST_MTIME=$(stat -c %Y "$ABS_PATH")

        if { [ "$STATUS" = "204" ] || [ "$STATUS" = "200" ]; } && [ "$POST_MTIME" -gt "$PRE_MTIME" ]; then
            SUMMARY_LOG="$SUMMARY_LOG $TAG:成功"
        else
            RESULT="失败($STATUS)"
            [ "$POST_MTIME" -le "$PRE_MTIME" ] && RESULT="文件未刷新"
            SUMMARY_LOG="$SUMMARY_LOG $TAG:$RESULT"
        fi
    done
    unset IFS

    # 写入日志
    if [ -f "$LOG_FILE" ]; then
        echo "$SUMMARY_LOG" | cat - "$LOG_FILE" | head -n 15 > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    else
        echo "$SUMMARY_LOG" > "$LOG_FILE"
    fi
    
    sleep $((INTERVAL * 60))
done
