#!/system/bin/sh
# Magisk 模块服务脚本

MODDIR=${0%/*}

# 启动订阅更新进程
nohup sh "$MODDIR/singbox_sub_update.sh" > /dev/null 2>&1 &
