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
    fi

    # 强制预检：每次自动更新前必须检测 Box 状态
    CURRENT_TIME=$(date "+%m-%d %H:%M:%S")
    CHECK_FILE="/data/adb/box/sing-box/config.json"
    
    if ! check_box_running; then
        SUMMARY_LOG="[$CURRENT_TIME] Box未运行，跳过当次更新。"
        if [ -f "$LOG_FILE" ]; then
            echo "$SUMMARY_LOG" | cat - "$LOG_FILE" | head -n 10 > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
        else
            echo "$SUMMARY_LOG" > "$LOG_FILE"
        fi
        # 按分钟周期进入下一次等待
        sleep $((INTERVAL * 60))
        continue
    fi

    # 获取更新前的修改时间
    PRE_MTIME=0
    [ -f "$CHECK_FILE" ] && PRE_MTIME=$(stat -c %Y "$CHECK_FILE")

    # 精准提取机场名
    PROVIDERS=$(curl -s "$API/providers/proxies" | sed 's/"name":"/\n/g' | grep '","proxies"' | awk -F'"' '{print $1}' | grep -v 'default')
    
    if [ -n "$PROVIDERS" ]; then
        SUMMARY_LOG="[$CURRENT_TIME]"
        
        for p in $PROVIDERS; do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$API/providers/proxies/$p" -d "" --max-time 30)
            
            # 后置校验：给系统 1 秒同步并获取新时间戳
            sleep 1
            POST_MTIME=0
            [ -f "$CHECK_FILE" ] && POST_MTIME=$(stat -c %Y "$CHECK_FILE")
            
            if { [ "$STATUS" = "204" ] || [ "$STATUS" = "200" ]; } && [ "$POST_MTIME" -gt "$PRE_MTIME" ]; then
                SUMMARY_LOG="$SUMMARY_LOG $p:更新成功"
                PRE_MTIME=$POST_MTIME
            else
                RESULT="失败($STATUS)"
                [ "$POST_MTIME" -le "$PRE_MTIME" ] && RESULT="配置未刷新"
                SUMMARY_LOG="$SUMMARY_LOG $p:$RESULT"
            fi
        done
        
        # 保持日志文件较小（10行）
        if [ -f "$LOG_FILE" ]; then
            echo "$SUMMARY_LOG" | cat - "$LOG_FILE" | head -n 10 > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
        else
            echo "$SUMMARY_LOG" > "$LOG_FILE"
        fi
    fi
    
    # 按分钟单位 sleep
    sleep $((INTERVAL * 60))
done
