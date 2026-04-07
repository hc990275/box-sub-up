#!/system/bin/sh
# Box-sub-up v2.0 — 基于 Clash API 的订阅自动更新守护进程
# 通过 GET/PUT /providers/proxies 实现一键更新全部订阅

MODDIR=${0%/*}
LOG_FILE="/storage/emulated/0/Android/sub.log"
CONF_FILE="/storage/emulated/0/Android/sub_config.conf"
DEFAULT_INTERVAL=30
API="http://127.0.0.1:9090"
SECRET=""
CURL="curl"
MODE="daemon"

# 解析参数
[ "$1" = "--once" ] && MODE="once"

# ═══════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════

# 确保 curl 可用
init_curl() {
    if command -v curl > /dev/null 2>&1; then
        CURL="curl"
    elif [ -x "/data/adb/box/bin/curl" ]; then
        CURL="/data/adb/box/bin/curl"
    else
        write_log "curl 未找到，无法执行更新"
        return 1
    fi
}

# 带认证的 GET 请求
api_get() {
    if [ -n "$SECRET" ]; then
        $CURL -s --connect-timeout 5 -H "Authorization: Bearer $SECRET" "${API}${1}"
    else
        $CURL -s --connect-timeout 5 "${API}${1}"
    fi
}

# 带认证的 PUT 请求，返回 HTTP 状态码
api_put() {
    if [ -n "$SECRET" ]; then
        $CURL -s -o /dev/null -w "%{http_code}" -X PUT --max-time 30 -H "Authorization: Bearer $SECRET" "${API}${1}" -d ""
    else
        $CURL -s -o /dev/null -w "%{http_code}" -X PUT --max-time 30 "${API}${1}" -d ""
    fi
}

# 写入日志（保留最近 15 条）
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

# ═══════════════════════════════════════
# API 地址和密钥自动侦测
# ═══════════════════════════════════════
detect_api_config() {
    # 从用户配置加载间隔
    [ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null

    # 从 Box settings.ini 获取核心信息
    [ -f "/data/adb/box/settings.ini" ] && . /data/adb/box/settings.ini 2>/dev/null

    local ec="" sc=""
    case "$bin_name" in
        mihomo)
            [ -f "$mihomo_config" ] || return
            ec=$(busybox awk '/^external-controller:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
            sc=$(busybox awk '/^secret:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
            ;;
        sing-box)
            [ -f "$sing_config" ] || return
            ec=$(busybox awk -F'[:,]' '/"external_controller"/{print $2":"$3}' "$sing_config" 2>/dev/null | tr -d ' "')
            sc=$(busybox awk -F'"' '/"secret"/{print $4}' "$sing_config" 2>/dev/null | head -1)
            ;;
    esac

    [ -n "$ec" ] && API="http://$ec"
    [ -n "$sc" ] && SECRET="$sc"
}

# ═══════════════════════════════════════
# Box 运行状态检测（三保险）
# ═══════════════════════════════════════
check_box_running() {
    [ -f "/data/adb/box/run/box.pid" ] && return 0
    for core in mihomo sing-box xray v2fly hysteria; do
        pidof "$core" > /dev/null 2>&1 && return 0
    done
    api_get "/version" > /dev/null 2>&1 && return 0
    return 1
}

# ═══════════════════════════════════════
# 核心：一键更新全部订阅
# ═══════════════════════════════════════
update_all_providers() {
    # 获取全部 provider 列表
    local resp
    resp=$(api_get "/providers/proxies" 2>/dev/null)

    if [ -z "$resp" ]; then
        write_log "API无响应，跳过更新"
        return 1
    fi

    # 提取 provider 名称
    # 方法1: yq（精确）
    local names="" yq_bin="/data/adb/box/bin/yq"
    if [ -x "$yq_bin" ]; then
        names=$(echo "$resp" | "$yq_bin" -p json '.providers | keys | .[]' 2>/dev/null)
    fi

    # 方法2: grep 回退（通过 vehicleType 字段过滤出真正的 provider）
    if [ -z "$names" ]; then
        names=$(echo "$resp" | tr '{' '\n' | grep '"vehicleType"' | grep -oE '"name"\s*:\s*"[^"]+"' | cut -d'"' -f4)
    fi

    if [ -z "$names" ]; then
        write_log "未发现订阅项目"
        return 1
    fi

    # 逐个触发更新
    local ok=0 fail=0 total=0 detail=""
    for name in $names; do
        total=$((total + 1))
        local code
        code=$(api_put "/providers/proxies/$(echo "$name" | sed 's/ /%20/g')")
        if [ "$code" = "204" ] || [ "$code" = "200" ]; then
            ok=$((ok + 1))
            detail="$detail $name:✓"
        else
            fail=$((fail + 1))
            detail="$detail $name:✗($code)"
        fi
        sleep 0.5
    done

    write_log "更新${ok}/${total}${detail}"

    # 更新 module.prop 显示状态
    local last_time
    last_time=$(date "+%H:%M")
    local interval_val="${INTERVAL:-$DEFAULT_INTERVAL}"
    sed -i "s|^description=.*|description=[💎 运行中 | 订阅:${total}个 | 成功:${ok} | 周期:${interval_val}min | 更新:${last_time}] 基于 Clash API 的订阅自动更新|" "$MODDIR/module.prop"

    [ "$fail" -gt 0 ] && return 1
    return 0
}

# ═══════════════════════════════════════
# 主入口
# ═══════════════════════════════════════

# 单次模式（由 action.sh 调用）
if [ "$MODE" = "once" ]; then
    init_curl || exit 1
    detect_api_config
    if check_box_running; then
        update_all_providers
    else
        write_log "Box未运行，跳过更新"
    fi
    exit 0
fi

# 守护进程模式
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 15

init_curl || exit 1

while true; do
    detect_api_config

    if check_box_running; then
        update_all_providers
    else
        write_log "Box未运行，跳过更新"
        sed -i "s|^description=.*|description=[❌ Box未运行 | 更新器待命] 基于 Clash API 的订阅自动更新|" "$MODDIR/module.prop"
    fi

    sleep $(( ${INTERVAL:-$DEFAULT_INTERVAL} * 60 ))
done
