#!bin/bash

# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"


# 目錄路徑
REMOTE_PATH="ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54"
SAVE_PATH="/opt/Portainer"


# 平台清單
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


# 遠端下載路徑:postinstall
POST_SCRIPTS=(
    "get_yaml_2_container.py ${REMOTE_PATH}/Portainer/get_yaml_2_container.py"
    "check_container_info.py ${REMOTE_PATH}/Portainer/check_container_info.py"
    "sync_container_2_cdnfly.py ${REMOTE_PATH}/Portainer/sync_container_2_cdnfly.py"
    "mekanism.py ${REMOTE_PATH}/Portainer/mekanism.py"
    "cdnfly_api.json ${REMOTE_PATH}/Portainer/cdnfly_api.json"
    "delete_stack.py ${REMOTE_PATH}/Portainer/delete_stack.py"
)


# 一次性收集要搬移的平台資訊(包含是否穿牆)
collect_all_user_input() {
    mkdir -p "$SAVE_PATH"
    now_site=$(grep '"platform"' user_input.json)

    IP_LIST=$(ip -4 addr | grep inet | awk '{print $2}' | cut -d/ -f1 | \
        grep -vE '^(127|10|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]|192\.168|169\.254)\.')
    NODE_IP=$(echo "$IP_LIST" | head -n1)
    DATE=$(date +%Y%m%d)
    NODE_NAME="${NODE_IP}_${DATE}"


    # 問穿牆
    if whiptail --title "GOGO 穿牆安裝" \
        --yesno "是否安裝 GOGO 穿牆？" 10 60; then
        GOGO_CHOICE="Yes"
    else
        GOGO_CHOICE="No"
    fi

    
    # 主控平台選單
    MENU_ITEMS=()
    for p in "${PLATFORMS[@]}"; do
        MENU_ITEMS+=("$p" "")
    done
    MENU_ITEMS+=("退出    -->" "取消安裝")

    PLATFORM=$(whiptail --title "選擇要搬移去哪個主控" \
        --menu "選擇要搬移去哪個主控: $now_site" 20 60 12 "${MENU_ITEMS[@]}" \
        3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ "$PLATFORM" == "退出    -->" ]; then
        echo -e "${YELLOW}✖ 使用者選擇退出${RESET}"
        return 1
    fi

    if [ "$GOGO_CHOICE" == "Yes" ]; then
        PLATFORM="${PLATFORM}-GOGO"
    fi
    # 去掉-GOGO
    FORMATED_PLATFORMS=$(echo "$PLATFORM" | sed 's/-GOGO//')

    # 確認全部資訊
    CONFIRM_MSG="請確認以下設定：\n\n要搬去主控平台：$PLATFORM\n節點名稱：$NODE_NAME\n節點 IP：$NODE_IP\n"
    if whiptail --title "資料確認" --yesno "$CONFIRM_MSG" 15 60; then
        cat > "$SAVE_PATH/user_input.json" <<EOF
{
  "platform": "$PLATFORM",
  "node_name": "$NODE_NAME",
  "node_ip": "$NODE_IP"
}
EOF
        echo -e "${GREEN}資料已儲存至 $SAVE_PATH/user_input.json ${RESET}"

        if [ "$LNMS_CHOICE" == "Yes" ]; then
            install_lnms
        fi
    else
        echo -e "${RED}資料未確認，請重新選擇${RESET}"
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
            # STATUS["下載_${filename}"]="${RED}✖ 失敗${RESET}"
        else
            chmod +x "$SAVE_PATH/$filename"
            echo -e "${GREEN}下載並設權限：${filename}${RESET}"
            # STATUS["下載_${filename}"]="${GREEN}✔ 成功${RESET}"
        fi
    done
}


# 工作流
work_flow() {
    echo -e "${YELLOW}開始執行 搬主控 工作流...${RESET}"
    run_post_script "delete_stack.py" || exit 1
    run_post_script "get_yaml_2_container.py" || exit 1
    run_post_script "check_container_info.py" || exit 1
    run_post_script "sync_container_2_cdnfly.py" || exit 1
    echo
    echo -e "${GREEN}Portainer post install 工作流執行完畢${RESET}"
}


# 執行單一腳本
run_post_script() {
    filename=$1
    echo -e "${YELLOW}執行 ${filename}...${RESET}"
    python "$SAVE_PATH/$filename"
    result=$?
    if [[ $result -ne 0 ]]; then
        echo -e "${RED} ${filename} Failed （exit code: $result）${RESET}"
        return 1
    else
        echo -e "${GREEN} ${filename} Successed ${RESET}"
        return 0
    fi
}


collect_all_user_input || exit 0
download_all_post_scripts
work_flow


