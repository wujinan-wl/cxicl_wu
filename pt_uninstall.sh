
#!/bin/bash

# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

#################################################

# 設定 Portainer 認證資訊
PORTAINER_URL="http://61.219.175.113:9101"
USERNAME="twnwdcxicl"
PASSWORD="%s#ytx6WUH\$f*kF6"   # $ 要 escape

#################################################

# 安裝必要套件jq、curl、wget
preinstall_packages() {
    if ! command -v curl >/dev/null 2>&1; then
        yum install -y curl || {
            echo -e "${RED}安裝 curl 失敗${RESET}"
            echo -e "${YELLOW}請更新源或是確認 yum.repos 配置是否異常${RESET}"
            exit 1
        }
    else
        echo -e "${GREEN}curl 已存在，略過安裝${RESET}"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        yum install -y jq || {
            echo -e "${RED}安裝 jq 失敗${RESET}"
            echo -e "${YELLOW}請更新源或是確認 yum.repos 配置是否異常${RESET}"
            exit 1
        }
    else
        echo -e "${GREEN}jq 已存在，略過安裝${RESET}"
    fi
    
    if ! command -v wget >/dev/null 2>&1; then
        yum install -y wget || {
            echo -e "${RED}安裝 wget 失敗${RESET}"
            echo -e "${YELLOW}請更新源或是確認 yum.repos 配置是否異常${RESET}"
            exit 1
        }
    else
        echo -e "${GREEN}wget 已存在，略過安裝${RESET}"
    fi
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

# 刪除 Portainer Environment
delete_portainer_environment() {
    echo -e "${YELLOW}刪除 Portainer Environment${RESET}"
    hostname -I
    echo -e "${YELLOW} 請輸入要刪除的IP: ${RESET}"
    read TARGET_NAME

    # Step 1: 取得 JWT Token
    TOKEN=$(curl -s -X POST "$PORTAINER_URL/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"Username\":\"$USERNAME\", \"Password\":\"$PASSWORD\"}" | jq -r '.jwt')

    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo -e "${RED} 無法登入 Portainer，請檢查帳密或 URL ${RESET}"
    fi

    # Step 2: 查詢所有 Endpoints，找出符合名稱的 ID
    ENDPOINT_ID=$(curl -s -X GET "$PORTAINER_URL/api/endpoints" \
    -H "Authorization: Bearer $TOKEN" | jq -r ".[] | select(.Name==\"$TARGET_NAME\") | .Id")

    if [ -z "$ENDPOINT_ID" ]; then
    echo -e "${RED} 找不到名稱為 \"$TARGET_NAME\" 的 Endpoint ${RESET}"
    exit 1
    fi

    echo -e "${GREEN} 找到 Endpoint \"$TARGET_NAME\"，ID 為：$ENDPOINT_ID ${RESET}"

    # Step 3: 刪除 Endpoint
    DELETE_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$PORTAINER_URL/api/endpoints/$ENDPOINT_ID" \
    -H "Authorization: Bearer $TOKEN")

    if [ "$DELETE_RESULT" == "204" ]; then
    echo -e "${GREEN} 已成功刪除 Endpoint \"$TARGET_NAME\" (ID: $ENDPOINT_ID) ${RESET}"
    else
    echo -e "${RED} 刪除失敗，HTTP 狀態碼：$DELETE_RESULT ${RESET}"
    exit 1
    fi
}

# 刪除現有portainer，包含container及image
delete_portainer() {
    echo -e "${YELLOW} 開始刪除 Portainer 所有相關 container 與 image${RESET}"

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
}

# 安裝監控：下載並執行LibreNMS監控安裝腳本（允許失敗跳過）
remove_lnms() {

    REMOTE_URL="ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/LibreNMS/"
    BASE_URL="/opt"

    echo -e "${YELLOW}下載 LibreNMS 卸載腳本...${RESET}"
    wget "$REMOTE_URL/remove_LibreNMS_device.py" -O "$BASE_URL/remove_LibreNMS_device.py"
    if [ ! -s "$BASE_URL/remove_LibreNMS_device.py" ]; then
        error "下載 remove_LibreNMS_device.py 失敗。"
        exit 1
    fi
    python2 "$BASE_URL/remove_LibreNMS_device.py"
    sleep 30
    echo -e "${GREEN} 全都處理完成，可通知機房下架 ${RESET}"
}

preinstall_packages
docker_stop_and_remove_containers_other
docker_remove_images_other
delete_portainer_environment
delete_portainer
install_python
remove_lnms
cd /opt/ && rm -rf remove_LibreNMS_device.py
rm -rf /root/pt_uninstall.sh
rm -rf /root/preinstall.sh

