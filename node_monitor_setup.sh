#!/bin/bash

# 獲取腳本完整路徑
CRIPT_PATH=$(realpath "$0")

# 日誌文件
LOG_FILE="/var/log/cdn_node_monitor_setup.log"

# 重定向日誌輸出
exec > >(tee -a "$LOG_FILE") 2>&1

# 安裝 wget
echo "安裝 wget..."
yum install -y wget

# 刪除舊的 cdn_node_monitor.py 文件（如果存在）
if [ -f /root/cdn_node_monitor.py ]; then
    echo "檢測到舊的 cdn_node_monitor.py，正在刪除..."
    rm -f /root/cdn_node_monitor.py
fi

# 下載新的監控程式
echo "下載新的 cdn_node_monitor.py..."
wget -O /root/cdn_node_monitor.py ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/cdn_node_monitor.py
chmod +x /root/cdn_node_monitor.py

# 刪除舊的服務文件（如果存在）
if [ -f /etc/systemd/system/cdn_node_monitor.service ]; then
    echo "檢測到舊的 cdn_node_monitor.service，正在刪除..."
    systemctl stop cdn_node_monitor.service
    systemctl disable cdn_node_monitor.service

    # 精確終止進程
    PID=$(pgrep -f "cdn_node_monitor.py")
    if [ -n "$PID" ]; then
        echo "正在終止 cdn_node_monitor.py 進程 (PID: $PID)..."
        kill "$PID"
    fi

    rm -f /etc/systemd/system/cdn_node_monitor.service
    systemctl daemon-reload
fi

# 創建新的服務文件
echo "創建新的 cdn_node_monitor.service..."
cat > /etc/systemd/system/cdn_node_monitor.service <<EOF
[Unit]
Description=CDN Node Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'source /opt/venv/bin/activate && python /root/cdn_node_monitor.py --bandwidth_limit 150 --load_limit 12'
KillMode=process
Restart=always
RestartSec=3s
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

# 載入並啟動服務
echo "啟動服務並設置開機自啟..."
systemctl daemon-reload
systemctl start cdn_node_monitor.service
systemctl enable cdn_node_monitor.service

# 確認服務狀態
echo "服務狀態："
systemctl status cdn_node_monitor.service

# 確保腳本僅在成功執行後刪除自身
if [ $? -eq 0 ]; then
    echo "刪除腳本文件..."
    rm -f "$SCRIPT_PATH"
else
    echo "腳本執行失敗，請檢查日誌：$LOG_FILE"
fi

