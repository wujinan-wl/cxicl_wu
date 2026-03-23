#!bin/bash


# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"


declare -A STATUS


# 目錄路徑
REMOTE_PATH="ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54"
SAVE_PATH="/opt/Portainer"


# 遠端下載路徑:postinstall
POST_SCRIPTS=(
    "portainer_register.py ${REMOTE_PATH}/Portainer/portainer_register.py"
    "get_yaml_2_container.py ${REMOTE_PATH}/Portainer/get_yaml_2_container.py"
    "check_container_info.py ${REMOTE_PATH}/Portainer/check_container_info.py"
    "sync_container_2_cdnfly.py ${REMOTE_PATH}/Portainer/sync_container_2_cdnfly.py"
    "mekanism.py ${REMOTE_PATH}/Portainer/mekanism.py"
    "cdnfly_api.json ${REMOTE_PATH}/Portainer/cdnfly_api.json"
)


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


# 輸入要清掉的IP
collect_ip_change_input() {
    yum install -y newt
    mkdir -p "$SAVE_PATH"

    # 從 user_input.json 讀取 node_ip 作為 OLD_IP
    OLD_IP=$(python -c "import json; print(json.load(open('$SAVE_PATH/user_input.json'))['node_ip'])" 2>/dev/null)

    if [ -z "$OLD_IP" ]; then
        whiptail --title "讀取失敗" --msgbox "無法從 user_input.json 讀取 node_ip，請確認檔案是否存在。" 8 60
        return 1
    fi

    # Step 1：輸入「更換後主 IP」
    NEW_IP=$(whiptail --title "IP 更換" \
        --inputbox "【更換前】主 IP：$OLD_IP\n\n請輸入【更換後】主 IP：" \
        10 60 "" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && echo -e "${YELLOW}✖ 使用者取消${RESET}" && return 1

    if ! [[ "$NEW_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        whiptail --title "格式錯誤" --msgbox "「更換後 IP」格式不正確，請重新輸入。" 8 50
        collect_ip_change_input
        return
    fi

    if [ "$OLD_IP" == "$NEW_IP" ]; then
        whiptail --title "輸入錯誤" --msgbox "更換前後 IP 不可相同，請重新輸入。" 8 50
        collect_ip_change_input
        return
    fi

    # Step 2：確認所有資訊
    CONFIRM_MSG="請確認以下 IP 更換設定：\n
  更換前主 IP ：$OLD_IP
  更換後主 IP ：$NEW_IP\n
確認後將寫入設定檔並執行後續流程。"

    if whiptail --title "資料確認" --yesno "$CONFIRM_MSG" 14 60; then
        cat > "$SAVE_PATH/user_input_for_changing_IP.json" <<EOF
{
  "old_ip": "$OLD_IP",
  "new_ip": "$NEW_IP"
}
EOF
        echo -e "${GREEN}✔ 資料已儲存至 $SAVE_PATH/user_input_for_changing_IP.json${RESET}"

    else
        echo -e "${RED}資料未確認，重新填寫…${RESET}"
        collect_ip_change_input
    fi
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


# 先清掉PT環境及container
clean_portainer_env_and_container() {
    
    docker ps -a --format '{{.Names}}' | while read CONTAINER_NAME; do
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME"
        echo "✔ 已刪除容器：$CONTAINER_NAME"
    done

    wget -O /opt/Portainer/remove_pt_enviroment_for_changing_IP.py ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/Portainer/remove_pt_enviroment.py
    chmod +x /opt/Portainer/remove_pt_enviroment_for_changing_IP.py
    python /opt/Portainer/remove_pt_enviroment_for_changing_IP.py

    # 重啟 Docker 重建 iptables chain
    echo -e "${YELLOW}重啟 Docker 以重建 iptables 規則...${RESET}"
    systemctl restart docker
    sleep 3
    echo -e "${GREEN}✔ Docker 重啟完成${RESET}"
}


# 重建PT專屬容器(Agent)
create_portainer_agent_container() {
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


postisntall() {
    run_post_script "portainer_register.py" || exit 1
    run_post_script "get_yaml_2_container.py" || exit 1
    run_post_script "check_container_info.py" || exit 1
    run_post_script "sync_container_2_cdnfly.py" || exit 1
}


# 主程式
disable_firewalld
collect_ip_change_input
echo -e "${GREEN}Portainer post install 1執行完畢${RESET}"
install_python
echo -e "${GREEN}Portainer post install 2執行完畢${RESET}"
clean_portainer_env_and_container
echo -e "${GREEN}Portainer post install 3執行完畢${RESET}"
create_portainer_agent_container
echo -e "${GREEN}Portainer post install 4執行完畢${RESET}"
postisntall
echo -e "${GREEN}Portainer post install 5執行完畢${RESET}"