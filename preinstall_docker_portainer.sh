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

# 確認 SELinux 狀態
check_selinux() {
    echo -e "${YELLOW}檢查 SELinux 狀態...${RESET}"
    sleep 1
    if command -v getenforce >/dev/null 2>&1; then
        STATUS=$(getenforce)
        if [[ "$STATUS" == "Enforcing" ]]; then
            echo -e "${YELLOW}偵測到 SELinux 為 Enforcing，將修改為 Permissive${RESET}"
            setenforce 0 || {
                echo -e "${RED}無法暫時關閉 SELinux${RESET}"
                echo -e "${RED}請手動關閉或是請機房協助關閉 SELinux${RESET}"
                exit 1
            }
            sed -i 's/^SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        else
            echo -e "${GREEN}SELinux 狀態：$STATUS${RESET}"
            sleep 2
        fi
    else
        echo -e "${YELLOW}系統未安裝 SELinux，略過檢查${RESET}"
    fi
}

# 安裝必要套件及同步時區
preinstall_yum() {
    echo -e "${YELLOW}準備安裝必要套件...${RESET}"

    # 確認是否安裝wget
    if ! command -v wget >/dev/null 2>&1; then
        yum install -y wget || {
            echo -e "${RED}安裝 wget 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
            exit 1
        }
    else
        echo -e "${GREEN}wget 已存在，略過安裝${RESET}"
        sleep 2
    fi

    # 確認是否安裝curl
    if ! command -v curl >/dev/null 2>&1; then
        yum install -y curl || {
            echo -e "${RED}安裝 curl 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
        }
    else
        echo -e "${GREEN}curl 已存在，略過安裝${RESET}"
        sleep 2
    fi

    # 確認是否安裝whiptail
    if ! command -v newt >/dev/null 2>&1; then
        yum install -y newt || {
            echo -e "${RED}安裝 whiptail 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
        }
    else
        echo -e "${GREEN}whiptail 已存在，略過安裝${RESET}"
        sleep 2
    fi

    # 確認是否安裝mtr
    if ! command -v mtr >/dev/null 2>&1; then
        yum install -y mtr || {
            echo -e "${RED}安裝 mtr 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
        }
    else
        echo -e "${GREEN}mtr 已存在，略過安裝${RESET}"
        sleep 2
    fi

    # 確認是否安裝chrony
    if ! command -v chrony >/dev/null 2>&1; then
        yum install -y chrony || {
            echo -e "${RED}安裝 chrony 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
        }
    else
        echo -e "${GREEN}chrony 已存在，略過安裝${RESET}"
        sleep 2
    fi

    echo -e "${YELLOW}準備同步時間...${RESET}"
    sudo systemctl start chronyd
    sudo systemctl enable chronyd
    echo -e "${YELLOW}設定時區中...${RESET}"
    timedatectl set-timezone Asia/Taipei
    sleep 3
    echo -e "${YELLOW}正在同步時間...${RESET}"
    chronyc sources
    sleep 3
    tdc=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if [[ "$tdc" == "Asia/Taipei" ]]; then
        echo -e "${GREEN}時間同步完成！${RESET}"
    else
        error_exit "時間同步失敗，請稍後手動確認"
    fi
}

# 處理防火牆：關閉firewalld防火牆並驗證其狀態
disable_firewalld() {
    echo -e "${YELLOW}關閉 firewalld 防火牆...${RESET}"
    STATE=$(systemctl is-active firewalld 2>/dev/null || true)
    sleep 3

    if [[ "$STATE" == "inactive" ]]; then
        echo -e "${GREEN}firewalld 防火牆已關閉${RESET}"
    elif [[ "$STATE" == "unknown" ]]; then
        echo -e "${GREEN}firewalld 未安裝，視同已關閉${RESET}"
    elif [[ "$STATE" == "active" ]]; then
        echo -e "${RED}firewalld 防火牆仍在運作中，關閉中請等待其關閉...${RESET}"
        systemctl stop firewalld || error_exit "無法停止 firewalld"
        systemctl disable firewalld || error_exit "無法停用 firewalld"
        sleep 3
        echo -e "${GREEN}firewalld 防火牆已關閉${RESET}"
    else
        error_exit "firewalld 防火牆未成功關閉，請稍後手動確認"
    fi
}

# 安裝 Docker (指定版本)
install_docker() {
    echo -e "${YELLOW}準備安裝 Docker (指定版本)...${RESET}"

    local DOCKER_VERSION="24.0.7-1.el7"

    if command -v docker >/dev/null 2>&1; then
        local INSTALLED_VERSION
        INSTALLED_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        if [[ "$INSTALLED_VERSION" == "${DOCKER_VERSION%%-*}"* ]]; then
            echo -e "${GREEN}Docker 已安裝版本：$INSTALLED_VERSION，符合要求，略過安裝。${RESET}"
            return 0
        else
            echo -e "${YELLOW}檢測到不同版本的 Docker ($INSTALLED_VERSION)，將先移除舊版本。${RESET}"
            yum remove -y docker docker-* || true
        fi
    fi

    yum install -y yum-utils || {
        echo -e "${RED}安裝 yum-utils 失敗${RESET}"
        echo -e "${YELLOW}請確認網路或 yum 鏡像設定是否正確${RESET}"
        exit 1
    }

    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || {
        echo -e "${RED}新增 Docker repo 失敗${RESET}"
        echo -e "${YELLOW}請確認 DNS 或 download.docker.com 是否可連線${RESET}"
        exit 1
    }

    echo -e "${YELLOW}安裝 Docker ${DOCKER_VERSION}...${RESET}"
    yum install -y \
        docker-ce-${DOCKER_VERSION} \
        docker-ce-cli-${DOCKER_VERSION} \
        containerd.io || {
        echo -e "${RED}安裝 Docker ${DOCKER_VERSION} 失敗${RESET}"
        echo -e "${YELLOW}請確認版本是否存在，或考慮手動更換版本${RESET}"
        exit 1
    }

    systemctl start docker || error_exit "無法啟動 Docker"
    systemctl enable docker || error_exit "無法設定 Docker 開機自動啟動"

    local FINAL_VERSION
    FINAL_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "${GREEN}Docker ${FINAL_VERSION} 安裝完成！${RESET}"
}

# 同步 portainer container
sync_portainer(){
    
    # 刪除先前資料初始化
    echo -e "${YELLOW}刪除現有 container，除了 portainer_agent${RESET}"
    CONTAINERS=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep -v "portainer_agent" | awk '{print $1}')
    if [ -n "$CONTAINERS" ]; then
        docker stop $CONTAINERS || true
        docker rm -f $CONTAINERS || true
    else
        echo -e "${GREEN} 沒有需要刪除的 container（portainer_agent 除外 ${RESET}"
    fi

    # 刪除所有現有 image
    echo -e "${YELLOW} 刪除所有現有 image，排除 portainer/agent ${RESET}"
    IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | \
             grep -v "portainer/agent" | awk '{print $2}' | sort -u)
    if [ -n "$IMAGES" ]; then
        docker rmi -f $IMAGES || true
    else
        echo -e "${GREEN} 沒有可刪除的 image，排除 portainer/agent 除外 ${RESET}"
    fi

    echo -e "${YELLOW}同步 portainer container...${RESET}"
    if docker ps -a --format '{{.Names}}' | grep -w portainer_agent >/dev/null 2>&1; then
        echo -e "${YELLOW}portainer_agent container 已存在，先移除再重建...${RESET}"
        docker rm -f portainer_agent || error_exit "無法移除舊的 portainer_agent container"
    fi

    docker run -d \
        -p 9101:9001 \
        --name portainer_agent \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes \
        -v /:/host \
        portainer/agent:2.27.8 || {
        echo -e "${RED}portainer_agent container 建立失敗${RESET}"
        echo -e "${YELLOW}請通知飛書客服組群組${RESET}"
        exit 1
    }

    if ! docker ps | grep -w portainer_agent >/dev/null 2>&1; then
        error_exit "portainer_agent container 啟動失敗"
    else
        echo -e "${GREEN}portainer_agent container 啟動成功！${RESET}"
    fi
}

# 主程式
echo -e "${YELLOW}已選擇安裝 Docker 及 Portainer 模式！${RESET}"
check_selinux
preinstall_yum
disable_firewalld
install_docker
sync_portainer
echo -e "${GREEN}模式所有安裝步驟執行完成！${RESET}"
