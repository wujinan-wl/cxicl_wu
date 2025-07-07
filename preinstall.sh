#!/bin/bash

#安裝
#curl -sSL https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/preinstall.sh | bash
#curl -sSL https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/preinstall.sh | sudo bash #root
#bash <(curl -sSL https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/preinstall.sh)

# 啟用錯誤即停
set -e
set -o pipefail

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
    if command -v getenforce >/dev/null 2>&1; then
        STATUS=$(getenforce)
        if [[ "$STATUS" == "Enforcing" ]]; then
            echo -e "${YELLOW}偵測到 SELinux 為 Enforcing，將修改為 Permissive${RESET}"
            setenforce 0 || error_exit "無法暫時關閉 SELinux"
            sed -i 's/^SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        else
            echo -e "${GREEN}SELinux 狀態：$STATUS${RESET}"
        fi
    else
        echo -e "${YELLOW}系統未安裝 SELinux，略過檢查${RESET}"
    fi
}

# 安裝必要套件
preinstall_yum() {
    echo -e "${YELLOW}準備安裝必要套件...${RESET}"
    if ! command -v wget >/dev/null 2>&1; then
        yum install -y wget || error_exit "安裝 wget 失敗"
    else
        echo -e "${GREEN}wget 已存在，略過安裝${RESET}"
    fi

    if ! command -v curl >/dev/null 2>&1; then
        yum install -y curl || error_exit "安裝 curl 失敗"
    else
        echo -e "${GREEN}curl 已存在，略過安裝${RESET}"
    fi
}

# 處理防火牆：關閉firewalld防火牆並驗證其狀態
disable_firewalld() {
    echo -e "${YELLOW}關閉 firewalld 防火牆...${RESET}"
    systemctl stop firewalld || error_exit "無法停止 firewalld"
    systemctl disable firewalld || error_exit "無法停用 firewalld"
    sleep 3

    STATE=$(systemctl is-active firewalld 2>/dev/null || true)

    if [[ "$STATE" == "inactive" ]]; then
        echo -e "${GREEN}firewalld 防火牆已關閉${RESET}"
    elif [[ "$STATE" == "unknown" ]]; then
    echo -e "${GREEN}firewalld 未安裝，視同已關閉${RESET}"
    else
        error_exit "firewalld 防火牆未成功關閉，請手動確認"
    fi
}

# 安裝python：安裝python2.7及其pip套件
install_python() {
    echo -e "${YELLOW}安裝 Python 2.7 及 pip...${RESET}"

    if ! command -v python2.7 >/dev/null 2>&1; then
        yum install -y python2 || error_exit "安裝 python2 失敗"
    else
        echo -e "${GREEN}Python 2.7 已存在，略過安裝${RESET}"
    fi

    if ! command -v pip2 >/dev/null 2>&1; then
        curl -O https://bootstrap.pypa.io/pip/2.7/get-pip.py || error_exit "下載 get-pip.py 失敗"
        python2.7 get-pip.py || error_exit "安裝 pip2 失敗"
        rm -f get-pip.py
        echo -e "${GREEN}pip2 安裝完成${RESET}"
    else
        echo -e "${GREEN}pip2 已存在，略過安裝${RESET}"
    fi
}

# 安裝監控：下載並執行LibreNMS監控安裝腳本
install_lnms() {
    echo -e "${YELLOW}下載 LibreNMS 安裝腳本...${RESET}"
    wget -O master_runner.sh ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/LibreNMS/master_runner.sh || error_exit "下載 LibreNMS 腳本失敗"
    chmod +x master_runner.sh || error_exit "無法賦予執行權限"
    mv master_runner.sh /opt/master_runner.sh || error_exit "無法搬移腳本至 /opt"
    echo -e "${YELLOW}執行 LibreNMS 安裝腳本...${RESET}"
    bash /opt/master_runner.sh || error_exit "執行 LibreNMS 安裝腳本失敗"
    rm -f /opt/master_runner.sh || error_exit "無法刪除腳本"
    echo -e "${GREEN}LibreNMS 安裝完成！${RESET}"
}

# 安裝 Docker (指定版本)
install_docker() {
    echo -e "${YELLOW}準備安裝 Docker (指定版本)...${RESET}"

    # 定義版本變數
    local DOCKER_VERSION="24.0.7-1.el7"

    # 先檢查是否已安裝正確版本
    if command -v docker >/dev/null 2>&1; then
        local INSTALLED_VERSION
        INSTALLED_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        if [[ "$INSTALLED_VERSION" == "${DOCKER_VERSION%%-*}"* ]]; then
            echo -e "${GREEN}Docker 已安裝版本：$INSTALLED_VERSION，符合要求，略過安裝。${RESET}"
            return 0
        else
            echo -e "${YELLOW}檢測到不同版本的 Docker ($INSTALLED_VERSION)，將先移除舊版本。${RESET}"
            yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
        fi
    fi

    # 安裝 yum-utils
    yum install -y yum-utils || error_exit "安裝 yum-utils 失敗"

    # 加入 Docker repo
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || error_exit "新增 Docker repo 失敗"

    # 查詢可用版本 (僅供參考，可刪掉)
    echo -e "${YELLOW}可用版本列表:${RESET}"
    yum list docker-ce --showduplicates | sort -r | head -20

    # 安裝指定版本
    echo -e "${YELLOW}安裝 Docker ${DOCKER_VERSION}...${RESET}"

    yum install -y \
        docker-ce-${DOCKER_VERSION} \
        docker-ce-cli-${DOCKER_VERSION} \
        containerd.io || error_exit "安裝 Docker ${DOCKER_VERSION} 失敗"

    systemctl start docker || error_exit "無法啟動 Docker"
    systemctl enable docker || error_exit "無法設定 Docker 開機自動啟動"

    local FINAL_VERSION
    FINAL_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')

    echo -e "${GREEN}Docker ${FINAL_VERSION} 安裝完成！${RESET}"
}

# 同步 portainer container
sync_portainer(){
    echo -e "${YELLOW}同步 portainer container...${RESET}"

    # 檢查 container 是否已存在
    if docker ps -a --format '{{.Names}}' | grep -w portainer_agent >/dev/null 2>&1; then
        echo -e "${YELLOW}portainer_agent container 已存在，先移除再重建...${RESET}"
        docker rm -f portainer_agent || error_exit "無法移除舊的 portainer_agent container"
    fi

    # 執行 docker run
    docker run -d \
        -p 9101:9001 \
        --name portainer_agent \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes \
        -v /:/host \
        portainer/agent:2.27.8 || error_exit "portainer_agent container 建立失敗"

    # 驗證 container 是否啟動
    if ! docker ps | grep -w portainer_agent >/dev/null 2>&1; then
        error_exit "portainer_agent container 啟動失敗"
    else
        echo -e "${GREEN}portainer_agent container 啟動成功！${RESET}"
    fi
}


#===========================MODE======================================

# mode-安裝節點
install_cdnfly_node_mode(){
    check_selinux
    preinstall_yum
    disable_firewalld
    install_python
    install_lnms
    install_docker
    sync_portainer
}

# mode-僅安裝 Docker
only_install_docker_mode(){
    check_selinux
    preinstall_yum
    install_docker
}

# mode-安裝 Docker 及 Portainer模式
install_docker_portainer_mode(){
    check_selinux
    preinstall_yum
    disable_firewalld
    install_docker
    sync_portainer
}

#===========================BRANCH=====================================

# branch-安裝節點
install_cdnfly_node_branch(){
    echo -e "${YELLOW}已選擇安裝節點模式！${RESET}"
    install_cdnfly_node_mode
    echo -e "${GREEN}模式所有安裝步驟執行完成！${RESET}"
}

# branch-安裝docker
install_docker_branch(){
    echo "1. 僅安裝 Docker模式"
    echo "2. 安裝 Docker 及 Portainer模式"
    read mode2

    if [ $mode2 -eq 1 ]
    then
        echo -e "${YELLOW}已選擇僅安裝 Docker 模式！${RESET}"
        only_install_docker_mode
        echo -e "${GREEN}模式所有安裝步驟執行完成！${RESET}"
    elif [ $mode2 -eq 2 ]
    then
        echo -e "${YELLOW}已選擇安裝 Docker 及 Portainer 模式！${RESET}"
        install_docker_portainer_mode
        echo -e "${GREEN}模式所有安裝步驟執行完成！${RESET}"
    else
        echo -e "${RED}無效的模式執行！${RESET}"
    fi
}

#===========================MASTER====================================

# master-主程式
echo "請選擇分支:"
echo "1. 安裝節點"
echo "2. 非安裝節點(docker、portainer)"
read mode

# 執行主幹內容，根據分支執行相關程式
if [ $mode -eq 1 ]
then
    echo -e "${YELLOW}已選擇安裝節點分支！${RESET}"
    install_cdnfly_node_branch
    echo -e "${GREEN}分支所有安裝步驟執行完成！${RESET}"
elif [ $mode -eq 2 ]
then
    echo -e "${YELLOW}已選擇非安裝節點(docker、portainer)分支！${RESET}"
    install_docker_branch
    echo -e "${GREEN}分支所有安裝步驟執行完成！${RESET}"
else
    echo -e "${RED}無效的分支！${RESET}"
fi
