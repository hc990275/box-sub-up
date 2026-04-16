#!/system/bin/sh
# Box-sub-up v2.1.1
# 基于 Clash API 的订阅自动更新守护进程
# 读取 /data/adb/box/settings.ini 中的 bin_name 来检测当前运行的核心类型
# 支持核心：mihomo / sing-box（其余核心无 Clash API，跳过更新）

MODDIR=${0%/*}
LOG_FILE="/storage/emulated/0/Android/sub.log"
DEBUG_LOG="/storage/emulated/0/Android/sub_debug.log"
SETTINGS="/data/adb/box/settings.ini"
# 更新间隔（分钟）- 已写死为 30 分钟
UPDATE_INTERVAL=30
LOG_MAX_LINES=10

API="http://127.0.0.1:9090"
SECRET=""
CURL="curl"
MODE="daemon"

[ "$1" = "--once" ] && MODE="once"

# ═══════════════════════════════════════
# 日志函数（日志保留最近 10 条）
# ═══════════════════════════════════════
write_log() {
    local entry="[$(date '+%m-%d %H:%M:%S')] $1"
    if [ -f "$LOG_FILE" ]; then
        # 新条目插入顶部，只保留 LOG_MAX_LINES 行
        echo "$entry" | cat - "$LOG_FILE" | head -n "$LOG_MAX_LINES" > "${LOG_FILE}.tmp"
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
# 初始化 curl
# ═══════════════════════════════════════
init_curl() {
    if command -v curl > /dev/null 2>&1; then
        CURL="curl"
        debug_log "curl: 使用系统 curl"
    elif [ -x "/data/adb/box/bin/curl" ]; then
        CURL="/data/adb/box/bin/curl"
        debug_log "curl: 使用 Box 内置 curl"
    else
        write_log "❌ 未找到 curl，无法执行更新"
        debug_log "curl: 致命错误，找不到任何 curl"
        return 1
    fi
}

# ═══════════════════════════════════════
# Clash API 封装
# ═══════════════════════════════════════
api_get() {
    local url="${API}${1}"
    if [ -n "$SECRET" ]; then
        $CURL -s --connect-timeout 5 -H "Authorization: Bearer $SECRET" "$url"
    else
        $CURL -s --connect-timeout 5 "$url"
    fi
}

api_put() {
    local url="${API}${1}"
    if [ -n "$SECRET" ]; then
        $CURL -s -o /dev/null -w "%{http_code}" -X PUT --max-time 30 \
            -H "Authorization: Bearer $SECRET" "$url" -d ""
    else
        $CURL -s -o /dev/null -w "%{http_code}" -X PUT --max-time 30 "$url" -d ""
    fi
}

# ═══════════════════════════════════════
# 读取 settings.ini，检测核心类型并自动配置 API
# ═══════════════════════════════════════
detect_api_config() {
    debug_log "======= 开始检测 API 配置 ======="

    if [ ! -f "$SETTINGS" ]; then
        debug_log "❌ settings.ini 不存在: $SETTINGS"
        write_log "❌ 未找到 Box settings.ini，无法检测核心类型"
        return 1
    fi

    # 从 settings.ini 中读取变量
    . "$SETTINGS" 2>/dev/null

    # 清理 Windows 换行符（\r）
    bin_name=$(echo "$bin_name" | tr -d '\r')
    mihomo_config=$(echo "$mihomo_config" | tr -d '\r')
    sing_config=$(echo "$sing_config" | tr -d '\r')

    debug_log "检测到核心类型: bin_name=${bin_name}"

    # 根据 bin_name 确定 proxy_provider 目录（记录日志用）
    case "$bin_name" in
        mihomo)
            PROVIDER_DIR="/data/adb/box/mihomo/proxy_provider"
            ;;
        sing-box)
            PROVIDER_DIR="/data/adb/box/sing-box/proxy_provider"
            ;;
        *)
            # xray / v2fly / hysteria 等核心没有 Clash API，无法用 API 更新
            debug_log "核心 ${bin_name} 不支持 Clash API，跳过更新"
            write_log "⚠️ 核心 [${bin_name}] 不支持 Clash API，无需更新"
            return 2
            ;;
    esac

    debug_log "Provider 目录: ${PROVIDER_DIR}"

    # ── 解析核心配置文件获取 API 地址和 Secret ──
    local ec="" sc=""

    case "$bin_name" in
        mihomo)
            if [ -f "$mihomo_config" ]; then
                # NOTE: mihomo yaml 格式：external-controller: "127.0.0.1:9090"
                ec=$(awk '/^external-controller:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
                sc=$(awk '/^secret:/{print $2}' "$mihomo_config" 2>/dev/null | tr -d "'\"")
                debug_log "Mihomo 配置解析: controller=${ec}, secret=${sc:0:3}***"
            else
                debug_log "Mihomo 配置文件不存在: $mihomo_config"
            fi
            ;;
        sing-box)
            if [ -f "$sing_config" ]; then
                # NOTE: sing-box json 格式："external_controller": "127.0.0.1:9090"
                ec=$(awk -F'[:,]' '/"external_controller"/{gsub(/[ "]/,"",$2); gsub(/[ "]/,"",$3); print $2":"$3}' "$sing_config" 2>/dev/null | head -1)
                sc=$(awk -F'"' '/"secret"/{print $4}' "$sing_config" 2>/dev/null | head -1)
                debug_log "Sing-box 配置解析: controller=${ec}, secret=${sc:0:3}***"
            else
                debug_log "Sing-box 配置文件不存在: $sing_config"
            fi
            ;;
    esac

    # 更新全局 API 和 SECRET
    if [ -n "$ec" ]; then
        API="http://$ec"
        # 将 0.0.0.0 替换为 127.0.0.1
        API=$(echo "$API" | sed 's/0\.0\.0\.0/127.0.0.1/g')
    fi
    [ -n "$sc" ] && SECRET="$sc"

    debug_log "最终 API 端点: ${API}"
    return 0
}

# ═══════════════════════════════════════
# 检测 Box 核心是否正在运行
# ═══════════════════════════════════════
check_box_running() {
    # 优先通过 PID 文件判断
    if [ -f "/data/adb/box/run/box.pid" ]; then
        debug_log "check_box_running: box.pid 存在"
        return 0
    fi
    # 通过进程名检查
    for core in mihomo sing-box xray v2fly hysteria; do
        if pidof "$core" > /dev/null 2>&1; then
            debug_log "check_box_running: 进程 $core 存在"
            return 0
        fi
    done
    # 最后兜底：尝试请求 API
    if api_get "/version" > /dev/null 2>&1; then
        debug_log "check_box_running: API /version 探测成功"
        return 0
    fi
    debug_log "check_box_running: Box 未运行"
    return 1
}

# ═══════════════════════════════════════
# 通过 Clash API 刷新全部 Provider
# ═══════════════════════════════════════
update_all_providers() {
    debug_log "开始刷新所有 Provider..."

    local resp
    resp=$(api_get "/providers/proxies" 2>/dev/null)

    if [ -z "$resp" ]; then
        write_log "❌ API 无响应，跳过本次更新 (${API})"
        debug_log "更新失败: /providers/proxies 返回空数据"
        return 1
    fi

    debug_log "API 响应片段: $(echo "$resp" | head -c 200 | tr '\n' ' ')"

    # 提取 Provider 名称：找含有 ",\"proxies\"" 的项，过滤掉 default
    local names
    names=$(echo "$resp" | sed 's/"name":"/\n/g' | grep '","proxies"' | awk -F'"' '{print $1}' | grep -v 'default')
    debug_log "提取到的 Provider 列表: $(echo "$names" | tr '\n' ' ')"

    if [ -z "$names" ]; then
        write_log "⚠️ 未发现任何订阅项目（Provider 列表为空）"
        debug_log "Provider 列表为空"
        return 1
    fi

    local ok=0 fail=0 total=0 detail=""

    # 使用 Here-Doc 避免管道子 shell 导致计数器失效
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        total=$((total + 1))

        # URL 编码常见特殊字符
        local safe_name
        safe_name=$(echo "$name" | sed -e 's/ /%20/g' -e 's/|/%7C/g' -e 's/!/%21/g')

        local code
        code=$(api_put "/providers/proxies/$safe_name")
        debug_log "PUT /providers/proxies/$safe_name -> HTTP $code"

        if [ "$code" = "204" ] || [ "$code" = "200" ] || [ "$code" = "202" ]; then
            ok=$((ok + 1))
            detail="$detail $name:✓"
        else
            fail=$((fail + 1))
            detail="$detail $name:✗(${code})"
        fi
        sleep 0.5
    done <<EOF
$names
EOF

    local interval_val=30
    write_log "✅ 刷新完成 核心:[${bin_name}] 成功:${ok}/${total} $(echo "$detail" | sed 's/^ //')"
    debug_log "更新汇总: total=${total}, ok=${ok}, fail=${fail}, detail=${detail}"

    # 更新 module.prop 状态描述
    sed -i "s|^description=.*|description=[💎 运行中 | 核心:${bin_name} | 订阅:${ok}/${total} | 周期:${interval_val}min | $(date '+%H:%M')] 自动更新|" "$MODDIR/module.prop"

    [ "$fail" -gt 0 ] && return 1
    return 0
}

# ═══════════════════════════════════════
# 主流程
# ═══════════════════════════════════════
run_once() {
    debug_log "==== 单次更新模式启动 ===="
    init_curl || exit 1
    detect_api_config
    local detect_ret=$?
    # detect_api_config 返回 2 表示核心不支持 API，正常退出
    [ "$detect_ret" -eq 2 ] && exit 0
    [ "$detect_ret" -ne 0 ] && exit 1

    if check_box_running; then
        update_all_providers
    else
        write_log "⏸ Box 未运行，跳过本次更新"
        debug_log "Box 未运行，跳过更新"
    fi
    debug_log "==== 单次更新结束 ===="
}

run_daemon() {
    debug_log "==== 守护进程启动 ===="

    # 1. 等待系统启动完成
    until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
    debug_log "系统已就绪，准备检测 Box..."

    # 2. 开机阶段强力等待（每 10s 检测一次，最多等 5 分钟）
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        detect_api_config >/dev/null 2>&1
        if check_box_running; then
            debug_log "检测到 Box 已启动 (等待了 $((wait_count * 10))s)"
            break
        fi
        wait_count=$((wait_count + 1))
        # 在面具描述里实时展示准备进度
        sed -i "s|^description=.*|description=[⏳ 等待启动 | ${wait_count}/30] 正在等待 Box 核心就绪...|" "$MODDIR/module.prop"
        sleep 10
    done

    init_curl || exit 1

    # 3. 进入主循环
    while true; do
        detect_api_config
        local detect_ret=$?

        if [ "$detect_ret" -eq 2 ]; then
            # 不支持 API 的核心，等待下个大周期再重新扫描（核心可能切换）
            debug_log "当前核心不支持 API，进入大周期休眠"
            sleep $(( 30 * 60 ))
        elif [ "$detect_ret" -eq 0 ]; then
            if check_box_running; then
                update_all_providers
                # 核心正常运行：执行 30 分钟休眠周期
                sleep $(( 30 * 60 ))
            else
                # ！！！核心未运行：不执行大周期休眠，改为 1 分钟短轮询 ！！！
                write_log "⏸ Box 未运行，1分钟后重试"
                debug_log "Box 未运行，进入短周期重试模式"
                sed -i "s|^description=.*|description=[❌ Box未运行 | 核心:${bin_name:-未知} | 1min后重试]|" "$MODDIR/module.prop"
                sleep 60
            fi
        else
            # 异常情况（如检测环境失败），等 5 分钟再完全重试环境初始化
            debug_log "环境检测异常，5分钟后重试"
            sleep 300
        fi
    done
}

if [ "$MODE" = "once" ]; then
    run_once
else
    run_daemon
fi
