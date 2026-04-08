#!/system/bin/sh
# Box-sub-up v2.0.3-20260408-100500 — 基于 Clash API 的订阅自动更新守护进程
# 开启了详细的 Debug 日志记录模式：/storage/emulated/0/Android/sub_debug.log

MODDIR=${0%/*}
LOG_FILE="/storage/emulated/0/Android/sub.log"
DEBUG_LOG="/storage/emulated/0/Android/sub_debug.log"
CONF_FILE="/storage/emulated/0/Android/sub_config.conf"
DEFAULT_INTERVAL=30
API="http://127.0.0.1:9090"
SECRET=""
CURL="curl"
MODE="daemon"

[ "$1" = "--once" ] && MODE="once"

# ═══════════════════════════════════════
# 日志函数
# ═══════════════════════════════════════
write_log() {
    local entry="[$(date '+%m-%d %H:%M:%S')] $1"
    if [ -f "$LOG_FILE" ]; then
        echo "$entry" | cat - "$LOG_FILE" | head -n 15 > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    else
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$entry" > "$LOG_FILE"
    fi
}

debug_log() {
    echo "[$(date '+%m-%d %H:%M:%S')] [DEBUG] $1" >> "$DEBUG_LOG"
}

# ═══════════════════════════════════════
# 核心功能加载
# ═══════════════════════════════════════
init_curl() {
    if command -v curl > /dev/null 2>&1; then
        CURL="curl"
        debug_log "curl: 系统 curl 可用"
    elif [ -x "/data/adb/box/bin/curl" ]; then
        CURL="/data/adb/box/bin/curl"
        debug_log "curl: 使用 Box 自带的 curl"
    else
        write_log "curl 未找到，无法执行更新"
        debug_log "curl: 致命错误，找不到任何 curl"
        return 1
    fi
}

api_get() {
    local cmd
    if [ -n "$SECRET" ]; then
        cmd="$CURL -s --connect-timeout 5 -H \"Authorization: Bearer $SECRET\" \"${API}${1}\""
    else
        cmd="$CURL -s --connect-timeout 5 \"${API}${1}\""
    fi
    debug_log "api_get 执行: $cmd"
    eval "$cmd"
}

api_put() {
    local cmd
    if [ -n "$SECRET" ]; then
        cmd="$CURL -s -o /dev/null -w \"%{http_code}\" -X PUT --max-time 30 -H \"Authorization: Bearer $SECRET\" \"${API}${1}\" -d \"\""
    else
        cmd="$CURL -s -o /dev/null -w \"%{http_code}\" -X PUT --max-time 30 \"${API}${1}\" -d \"\""
    fi
    debug_log "api_put 执行: $cmd"
    eval "$cmd"
}

detect_api_config() {
    debug_log "开始侦测 API 配置..."
    [ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null

    local bb_awk="awk"
    [ -x "/data/adb/magisk/busybox" ] && bb_awk="/data/adb/magisk/busybox awk"
    [ -x "/data/adb/ksu/bin/busybox" ] && bb_awk="/data/adb/ksu/bin/busybox awk"

    if [ ! -f "/data/adb/box/settings.ini" ]; then
        debug_log "settings.ini 不存在"
        return
    fi

    . /data/adb/box/settings.ini 2>/dev/null
    debug_log "探测到 core_name=${bin_name}"

    local ec="" sc=""
    case "$bin_name" in
        mihomo)
            if [ -f "$mihomo_config" ]; then
                ec=$($bb_awk '/^external-controller:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
                sc=$($bb_awk '/^secret:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
                debug_log "Mihomo: 获取到 external-controller=$ec, secret=${sc:0:3}***"
            else
                debug_log "Mihomo 配置未找到: $mihomo_config"
            fi
            ;;
        sing-box)
            if [ -f "$sing_config" ]; then
                ec=$($bb_awk -F'[:,]' '/"external_controller"/{print $2":"$3}' "$sing_config" 2>/dev/null | tr -d ' "')
                sc=$($bb_awk -F'"' '/"secret"/{print $4}' "$sing_config" 2>/dev/null | head -1)
                debug_log "Sing-box: 获取到 external_controller=$ec, secret=${sc:0:3}***"
            else
                debug_log "Sing-box 配置未找到: $sing_config"
            fi
            ;;
    esac

    [ -n "$ec" ] && API="http://$ec"
    [ -n "$sc" ] && SECRET="$sc"
    
    # 防止读取到的是 0.0.0.0
    API=$(echo "$API" | sed 's/0\.0\.0\.0/127.0.0.1/g')
    debug_log "最终确定的 API=$API"
}

check_box_running() {
    if [ -f "/data/adb/box/run/box.pid" ]; then
        debug_log "check_box_running: box.pid 存在"
        return 0
    fi
    for core in mihomo sing-box xray v2fly hysteria; do
        if pidof "$core" > /dev/null 2>&1; then
            debug_log "check_box_running: pidof $core 成功"
            return 0
        fi
    done
    if api_get "/version" > /dev/null 2>&1; then
        debug_log "check_box_running: API /version 探测成功"
        return 0
    fi
    debug_log "check_box_running: Box 未运行!"
    return 1
}

update_all_providers() {
    debug_log "开始更新所有 Provider..."
    
    local resp
    resp=$(api_get "/providers/proxies" 2>/dev/null)

    if [ -z "$resp" ]; then
        write_log "API无响应，跳过更新"
        debug_log "更新失败: /providers/proxies 无任何返回数据"
        return 1
    fi

    # 打印前 200 个字符的响应辅助排错
    debug_log "API 返回数据片段: $(echo "$resp" | head -c 200 | tr '\n' ' ')"

    # 【核心修复】引入你之前的提取逻辑：
    # 巧妙利用 sed 和 grep，提取带有 \",\"proxies\" 的顶级机场名，完美应对 sing-box/mihomo
    local names=""
    names=$(echo "$resp" | sed 's/"name":"/\n/g' | grep '","proxies"' | awk -F'"' '{print $1}' | grep -v 'default')
    debug_log "使用单行逻辑提取的 Provider 名称: $names"

    if [ -z "$names" ]; then
        write_log "未发现订阅项目"
        debug_log "提取 Provider 失败或本身为空配置"
        return 1
    fi

    local ok=0 fail=0 total=0 detail=""
    
    # 采用 Here-Doc 绕过管道子 shell 限制，既完美支持空格名称，又能正确返回外层计数器
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        total=$((total + 1))
        debug_log "开始触发 Provider 更新: $name"
        
        # 简单转换所有的常用空格
        local safe_name=$(echo "$name" | sed -e 's/ /%20/g' -e 's/|/%7C/g' -e 's/!/%21/g')
        
        local code
        code=$(api_put "/providers/proxies/$safe_name")
        debug_log "触发结果 $name -> HTTP Code: $code"
        
        if [ "$code" = "204" ] || [ "$code" = "200" ] || [ "$code" = "202" ]; then
            ok=$((ok + 1))
            detail="$detail $name:✓"
        else
            fail=$((fail + 1))
            detail="$detail $name:✗($code)"
            debug_log ">> 失败详情: URL 编码可能不匹配，原始名称为 [$name]"
        fi
        sleep 0.5
    done <<EOF
$names
EOF

    write_log "更新${ok}/${total}${detail}"
    debug_log "更新完成。总计: $total, 成功: $ok, 失败: $fail"

    local interval_val="${INTERVAL:-$DEFAULT_INTERVAL}"
    sed -i "s|^description=.*|description=[💎 运行中 | 订阅:${total}个 | 成功:${ok} | 周期:${interval_val}min | 更新:$(date "+%H:%M")] 基于 Clash API 的自动更新|" "$MODDIR/module.prop"

    [ "$fail" -gt 0 ] && return 1
    return 0
}

# ═══════════════════════════════════════
# 主流程
# ═══════════════════════════════════════

if [ "$MODE" = "once" ]; then
    debug_log "==== 单次更新模式启动 ($MODE) ===="
    init_curl || exit 1
    detect_api_config
    if check_box_running; then
        update_all_providers
    else
        write_log "Box未运行，跳过更新"
        debug_log "因 Box 未运行，取消本次更新操作"
    fi
    debug_log "==== 单次更新流程结束 ===="
    exit 0
fi

debug_log "==== 守护模式更新进程启动 ===="
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 15
debug_log "系统已就绪，进入守护循环"

init_curl || exit 1

while true; do
    detect_api_config

    if check_box_running; then
        update_all_providers
    else
        write_log "Box未运行，跳过更新"
        debug_log "守护循环中检测到 Box 未运行"
        sed -i "s|^description=.*|description=[❌ Box未运行 | 更新器待命] 基于 Clash API 的自动更新|" "$MODDIR/module.prop"
    fi

    sleep $(( ${INTERVAL:-$DEFAULT_INTERVAL} * 60 ))
done
