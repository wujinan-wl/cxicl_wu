#!/bin/bash

# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 路徑
REMOTE_PATH="ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54"
SAVE_PATH="/opt/Portainer"
SAVE_FILE="$SAVE_PATH/user_input.json"

# 遠端下載路徑:postinstall
POST_SCRIPTS=(
    "portainer_register.py ${REMOTE_PATH}/Portainer/portainer_register.py"
    "get_yaml_2_container.py ${REMOTE_PATH}/Portainer/get_yaml_2_container.py"
    "check_container_info.py ${REMOTE_PATH}/Portainer/check_container_info.py"
    "sync_container_2_cdnfly.py ${REMOTE_PATH}/Portainer/sync_container_2_cdnfly.py"
    "mekanism.py ${REMOTE_PATH}/Portainer/mekanism.py"
    "cdnfly_api.json ${REMOTE_PATH}/Portainer/cdnfly_api.json"
)

# 狀態記錄，總結用
declare -A STATUS

# 平台清單 # NEW
PLATFORMS=(
    "CDNMASTER"
    "CDNMASTER02"
    "CDNVIP"
    "CDNVIP01"
    "CDNVIP02"
    "CDNVIP03"
    "CDNVIP04"
    "CDNVIP05"
    "CDNVIP06"
)

# 統一錯誤處理
error_exit() {
    echo -e "${RED}錯誤：$1${RESET}"
    exit 1
}

# 安裝python
install_python() {
    echo -e "${YELLOW}安裝 Python 2.7 及 pip...${RESET}"
    if ! command -v python2.7 >/dev/null 2>&1; then
        yum install -y python2 || error_exit "安裝 python2 失敗"
    else
        echo -e "${GREEN}Python 2.7 已存在，略過安裝${RESET}"
    fi

    if ! command -v pip2 >/dev/null 2>&1; then
        curl -O https://bootstrap.pypa.io/pip/2.7/get-pip.py || error_exit "下載 get-pip.py 失敗"
        python2.7 get-pip.py || { echo -e "${RED}安裝 pip2 失敗${RESET}"; exit 1; }
        rm -f get-pip.py
        echo -e "${GREEN}pip2 安裝完成${RESET}"
    else
        echo -e "${GREEN}pip2 已存在，略過安裝${RESET}"
    fi

    pip2 install requests netaddr PyJWT==1.7.1 || { echo -e "${RED}安裝 python + pip2 失敗${RESET}"; exit 1; }
}

# 安裝 LibreNMS
install_lnms() {
    echo -e "${YELLOW}下載 LibreNMS 安裝腳本...${RESET}"
    wget -O /root/add_LibreNMS_device.py ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/LibreNMS/add_LibreNMS_device.py
    chmod +x /root/add_LibreNMS_device.py
    python /root/add_LibreNMS_device.py
    rm -rf /root/add_LibreNMS_device.py
    echo
    echo -e "${YELLOW}LNMS監控安裝 未執行成功的話節點也能正常同步節點${RESET}"
    echo -e "${GREEN}LibreNMS 安裝處理完成（成功或已跳過）${RESET}"
}

# NEW: 一次性收集 LNMS 選擇與平台資訊
collect_all_user_input() {
    mkdir -p "$SAVE_PATH"

    IP_LIST=$(ip -4 addr | grep inet | awk '{print $2}' | cut -d/ -f1 | \
        grep -vE '^(127|10|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]|192\.168|169\.254)\.')
    NODE_IP=$(echo "$IP_LIST" | head -n1)
    DATE=$(date +%Y%m%d)
    NODE_NAME="${NODE_IP}_${DATE}"

    # 問 LNMS
    if whiptail --title "LNMS 監控安裝" \
        --yesno "是否安裝 LNMS 監控？）" 10 60; then
        LNMS_CHOICE="Yes"
    else
        LNMS_CHOICE="No"
    fi

    # 主控平台選單
    MENU_ITEMS=()
    for p in "${PLATFORMS[@]}"; do
        MENU_ITEMS+=("$p" "")
    done
    MENU_ITEMS+=("退出    -->" "取消安裝")

    PLATFORM=$(whiptail --title "選擇 Portainer 主控" \
        --menu "請選擇上節點的主控：" 20 60 12 "${MENU_ITEMS[@]}" \
        3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ "$PLATFORM" == "退出" ]; then
        echo -e "${YELLOW}✖ 使用者選擇退出${RESET}"
        return 1
    fi

    # 確認全部資訊
    CONFIRM_MSG="請確認以下設定：\n\n安裝 LNMS：$LNMS_CHOICE\n主控平台：$PLATFORM\n節點名稱：$NODE_NAME\n節點 IP：$NODE_IP\n"
    if whiptail --title "資料確認" --yesno "$CONFIRM_MSG" 15 60; then
        cat > "$SAVE_FILE" <<EOF
{
  "platform": "$PLATFORM",
  "node_name": "$NODE_NAME",
  "node_ip": "$NODE_IP"
}
EOF
        echo -e "${GREEN}✔ 資料已儲存至 $SAVE_FILE${RESET}"

        if [ "$LNMS_CHOICE" == "Yes" ]; then
            install_lnms
        fi
        return 0
    else
        echo -e "${YELLOW}↻ 資料未確認，請重新選擇${RESET}"
        collect_all_user_input
    fi
}

# 下載所有 postinstall python腳本
download_all_post_scripts() {
    echo -e "${YELLOW}下載所有 postinstall 腳本...${RESET}"
    for item in "${POST_SCRIPTS[@]}"; do
        IFS=" " read -r filename url <<< "$item"
        wget -O "$SAVE_PATH/$filename" "$url"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}下載 ${filename} 失敗${RESET}"
            STATUS["下載_${filename}"]="${RED}✖ 失敗${RESET}"
        else
            chmod +x "$SAVE_PATH/$filename"
            echo -e "${GREEN}下載並設權限：${filename}${RESET}"
            STATUS["下載_${filename}"]="${GREEN}✔ 成功${RESET}"
        fi
    done
}

# 執行單一腳本
run_post_script() {
    filename=$1
    echo -e "${YELLOW}執行 ${filename}...${RESET}"
    python "$SAVE_PATH/$filename"
    result=$?
    if [[ $result -ne 0 ]]; then
        echo -e "${RED}✖ ${filename} 執行失敗（exit code: $result）${RESET}"
        STATUS["執行_${filename}"]="${RED}✖ 失敗（$result）${RESET}"
        return 1
    else
        echo -e "${GREEN}✔ ${filename} 執行成功${RESET}"
        STATUS["執行_${filename}"]="${GREEN}✔ 成功${RESET}"
        return 0
    fi
}

# 總結顯示
work_flow_summary() {
    echo -e "\n${YELLOW}工作流程總結：${RESET}"
    for key in "${!STATUS[@]}"; do
        printf "%-30s %b\n" "$key" "${STATUS[$key]}"
    done
}

# 工作流
work_flow() {
    echo -e "${YELLOW}開始執行 Portainer post install 工作流...${RESET}"
    run_post_script "portainer_register.py" || exit 1
    run_post_script "get_yaml_2_container.py" || exit 1
    run_post_script "check_container_info.py" || exit 1
    run_post_script "sync_container_2_cdnfly.py" || exit 1
    work_flow_summary
    echo
    echo -e "${GREEN}Portainer post install 工作流執行完畢${RESET}"
    echo
    echo -e "${GREEN}請確認節點同步成功及增加子IP${RESET}"
}

# 主程式
install_python
collect_all_user_input || exit 0
download_all_post_scripts
work_flow
rm -rf /opt/Portainer
