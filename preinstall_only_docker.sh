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

#換源
change_yum_repos() {
    echo -e "${YELLOW}更換 yum 源...${RESET}"
    echo -e "${YELLOW}準備更換源環境中...${RESET}"
    sleep 5
    bash <(curl -sSL https://linuxmirrors.cn/main.sh)
    echo -e "${GREEN}yum 源更換完成！${RESET}"
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
    if ! command -v whiptail >/dev/null 2>&1; then
        yum install -y whiptail || {
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

    # 確認是否安裝ntpdate
    if ! command -v ntpdate >/dev/null 2>&1; then
        yum install -y ntpdate || {
            echo -e "${RED}安裝 ntpdate 失敗${RESET}"
            echo -e "${RED}請更新源或是確認 yum.repos 配置是否異常${RESET}"
        }
    else
        echo -e "${GREEN}ntpdate 已存在，略過安裝${RESET}"
        sleep 2
    fi

    echo -e "${YELLOW}準備同步時間...${RESET}"
    ntpdate time.stdtime.gov.tw || { echo -e "${RED}同步時間失敗，請確認網路是否正常${RESET}"; exit 1; }
    sleep 5
    echo -e "${GREEN}時間同步完成！${RESET}"
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

# 主程式
echo -e "${YELLOW}已選擇僅安裝 Docker 模式！${RESET}"
check_selinux
change_yum_repos
preinstall_yum
install_docker
echo -e "${GREEN}模式所有安裝步驟執行完成！${RESET}"