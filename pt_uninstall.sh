
#!/bin/bash

# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 統一錯誤處理
error_exit() {
    echo -e "${RED}錯誤：$1${RESET}"
    exit 1
}

# 安裝python：安裝python2.7及其pip套件
install_python() {
    echo -e "${YELLOW}安裝 Python 2.7 及 pip...${RESET}"

    # 安裝python (阿里雲yum預設python版本為2.7)
    if ! command -v python2.7 >/dev/null 2>&1; then
        yum install -y python2 || error_exit "安裝 python2 失敗"
    else
        echo -e "${GREEN}Python 2.7 已存在，略過安裝${RESET}"
    fi

    # 手動配置python 2.7適配的pip2
    if ! command -v pip2 >/dev/null 2>&1; then
        curl -O https://bootstrap.pypa.io/pip/2.7/get-pip.py || error_exit "下載 get-pip.py 失敗"
        python2.7 get-pip.py || {
            echo -e "${RED}安裝 pip2 失敗${RESET}"
            echo -e "${YELLOW}請通知飛書客服組群組${RESET}"
            exit 1
        }
        rm -f get-pip.py
        echo -e "${GREEN}pip2 安裝完成${RESET}"
    else
        echo -e "${GREEN}pip2 已存在，略過安裝${RESET}"
    fi

    # pip2 (requests、netaddr、PyJWT)套件
    pip2 install requests netaddr  PyJWT==1.7.1|| { echo -e "${RED}安裝 python + pip2 失敗${RESET}"; exit 1; }
}

# 停止並移除所有 container，除了 portainer_agent
docker_stop_and_remove_containers_other() {
    echo -e "${YELLOW}刪除現有 container，除了 portainer_agent${RESET}"
    
    # 找出所有 container ID，排除 name 包含 portainer_agent 的
    CONTAINERS=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep -v "portainer_agent" | awk '{print $1}')

    if [ -n "$CONTAINERS" ]; then
        docker stop $CONTAINERS || true
        docker rm -f $CONTAINERS || true
    else
        echo -e "${GREEN} 沒有需要刪除的 container（portainer_agent 除外 ${RESET}"
    fi
}

# 刪除現有image，除了 portainer_agent
docker_remove_images_other() {
    echo -e "${YELLOW} 刪除所有現有 image，排除 portainer/agent ${RESET}"

    IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | \
             grep -v "portainer/agent" | awk '{print $2}' | sort -u)

    if [ -n "$IMAGES" ]; then
        docker rmi -f $IMAGES || true
    else
        echo -e "${GREEN} 沒有可刪除的 image，排除 portainer/agent 除外 ${RESET}"
    fi
}

# 刪除現有portainer，包含container及image
delete_portainer() {
    
    # 上線
    wget -O /root/remove_pt_enviroment.py ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/Portainer/remove_pt_enviroment.py

    chmod +x /root/remove_pt_enviroment.py
    python /root/remove_pt_enviroment.py

    echo -e "${YELLOW} 開始刪除 Portainer 所有相關 container 與 image ${RESET}"
    # 刪除 container（portainer 與 agent）
    for cname in portainer portainer_agent; do
        if docker ps -a --format '{{.Names}}' | grep -q "^$cname$"; then
            echo -e "${YELLOW}停止並刪除 container: $cname${RESET}"
            docker stop $cname || true
            docker rm -f $cname || true
        else
            echo -e "${GREEN} container \"$cname\" 不存在，略過${RESET}"
        fi
    done

    # 刪除 image：portainer/agent 與 portainer/portainer-ce 全部版本
    for repo in portainer/agent portainer/portainer-ce; do
        IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "^$repo:" | awk '{print $1}')
        if [ -n "$IMAGES" ]; then
            echo -e "${YELLOW}刪除 image: $repo 所有 tag${RESET}"
            echo "$IMAGES" | xargs docker rmi -f || true
        else
            echo -e "${GREEN} image \"$repo\" 不存在，略過${RESET}"
        fi
    done

    echo -e "${GREEN} Portainer 相關資源刪除完成${RESET}"
}

# 移除監控
remove_lnms() {
    echo -e "${YELLOW}下載 LibreNMS 卸載腳本...${RESET}"

    # 上線
    wget -O /root/remove_LibreNMS_device.py ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/LibreNMS/remove_LibreNMS_device.py

    chmod +x /root/remove_LibreNMS_device.py
    python "/root/remove_LibreNMS_device.py"
    echo -e "${GREEN} 全都處理完成，可通知機房下架 ${RESET}"
}

run_uninstall_all() {
    install_python
    docker_stop_and_remove_containers_other
    docker_remove_images_other
    delete_portainer
    remove_lnms
    rm -rf /opt/https_test
    rm -rf /opt/Portainer
    rm -rf /opt/LibreNMS
    rm -f /root/remove_LibreNMS_device.py
    rm -f /root/add_LibreNMS_device.py
    rm -f /root/remove_pt_enviroment.py
}

# 主程式
if whiptail --backtitle "Excalibur && Stella" --title "卸載提示" \
    --yesno $'此動作會卸載節點及 Portainer（請先處理 CDN 線路組）。\n確定要繼續？' 12 70; then
    run_uninstall_all
else
    echo -e "${RED}卸載已取消。${RESET}"
    exit 1
fi
