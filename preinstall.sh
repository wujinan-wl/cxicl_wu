#!/bin/bash

# 顏色定義
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# GitHub PAT
NEW_SCRIPT_BASE_URL="https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main"

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

# 狀態記錄，總結用
declare -A STATUS

# 統一錯誤處理
error_exit() {
    echo -e "${RED}錯誤：$1${RESET}"
    exit 1
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

    systemctl restart docker
    echo -e "${YELLOW}等待 Docker 服務重啟完成...${RESET}"
    sleep 3

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

# 每天清除 Docker logs > cron 任務
clean_docker_log() {
    TARGET_SCRIPT="/var/lib/docker/containers/clean_docker_log.sh"
    CRON_CMD="/bin/bash $TARGET_SCRIPT"
    CRON_JOB="0 1 * * * $CRON_CMD"

    echo -e "${YELLOW}建立清除 Docker log 腳本...${RESET}"

    cat > "$TARGET_SCRIPT" <<'EOF'
#!/bin/bash

TARGET_SCRIPT_LOG="/var/lib/docker/containers/clean_docker_log.log"
echo "[$(date '+%F %T')] 開始清除 Docker logs" >> "$TARGET_SCRIPT_LOG"

find /var/lib/docker/containers/ -name "*-json.log" | while read log_file; do
    if [ -f "$log_file" ]; then
        echo "[$(date '+%F %T')] 清除 $log_file" >> "$TARGET_SCRIPT_LOG"
        > "$log_file"
    fi
done

echo "[$(date '+%F %T')] 清理結束" >> "$TARGET_SCRIPT_LOG"
EOF

    chmod +x "$TARGET_SCRIPT" || {
        echo -e "${RED}chmod 失敗${RESET}"
        return 1
    }

    echo -e "${YELLOW}檢查 crontab 排程是否已存在...${RESET}"
    crontab -l 2>/dev/null | grep -F "$CRON_CMD" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        tmp_cron="/tmp/cron_$$"
        crontab -l 2>/dev/null > "$tmp_cron" 2>/dev/null || touch "$tmp_cron"
        echo "$CRON_JOB" >> "$tmp_cron"
        crontab "$tmp_cron" && rm -f "$tmp_cron"
        echo -e "${GREEN}已加入 crontab 任務：$CRON_JOB${RESET}"
    else
        echo -e "${YELLOW}crontab 中已包含此任務，略過新增${RESET}"
    fi
}

# 下載清理容器nginx緩存
download_container_nginx_clean_for_volume(){
    echo -e "${YELLOW}下載 volume...${RESET}"
    wget -O /opt/clean_cache.sh https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/clean_cache.sh
    chmod +x /opt/clean_cache.sh
    echo -e "${GREEN}設置完成！${RESET}"
}

# 一次性收集 LNMS 選擇與平台資訊(包含是否穿牆)
collect_all_user_input() {
    mkdir -p "$SAVE_PATH"

    IP_LIST=$(ip -4 addr | grep inet | awk '{print $2}' | cut -d/ -f1 | \
        grep -vE '^(127|10|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]|192\.168|169\.254)\.')
    NODE_IP=$(echo "$IP_LIST" | head -n1)
    DATE=$(date +%Y%m%d)
    NODE_NAME="${NODE_IP}_${DATE}"

    # 問 LNMS
    if whiptail --title "LNMS 監控安裝" \
        --yesno "是否安裝 LNMS 監控？" 10 60; then
        LNMS_CHOICE="Yes"
    else
        LNMS_CHOICE="No"
    fi

    # 問 穿牆
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

    PLATFORM=$(whiptail --title "選擇 Portainer 主控" \
        --menu "請選擇上節點的主控：" 20 60 12 "${MENU_ITEMS[@]}" \
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
    CONFIRM_MSG="請確認以下設定：\n\n安裝 LNMS：$LNMS_CHOICE\n安裝 GOGO穿牆：$GOGO_CHOICE\n主控平台：$FORMATED_PLATFORMS\n節點名稱：$NODE_NAME\n節點 IP：$NODE_IP\n"
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

# 工作流
work_flow() {
    echo -e "${YELLOW}開始執行 Portainer post install 工作流...${RESET}"
    run_post_script "portainer_register.py" || exit 1
    run_post_script "get_yaml_2_container.py" || exit 1
    run_post_script "check_container_info.py" || exit 1
    run_post_script "sync_container_2_cdnfly.py" || exit 1
    echo
    echo -e "${GREEN}Portainer post install 工作流執行完畢${RESET}"
}

# 建立固定排程：02:00 起每 30 分鐘拉 1 個 Docker image
others_images_cron_once() {
    echo "建立分兩天 Docker images 拉取任務（Day1: 明天 NORMAL, Day2: 後天 GOGO）..."

    LOG_FILE="/var/log/docker_images_pull.log"
    mkdir -p /var/log
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    NORMAL_IMAGES=(
      "wujinan/cdn:cdnmaster-agent-1.0.0"
      "wujinan/cdn:cdnmaster02-agent-1.0.0"
      "wujinan/cdn:cdnvip-agent-1.0.0"
      "wujinan/cdn:cdnvip01-agent-1.0.0"
      "wujinan/cdn:cdnvip02-agent-1.0.0"
      "wujinan/cdn:cdnvip03-agent-1.0.0"
      "wujinan/cdn:cdnvip04-agent-1.0.0"
      "wujinan/cdn:cdnvip05-agent-1.0.0"
      "wujinan/cdn:cdnvip06-agent-1.0.0"
    )

    GOGO_IMAGES=(
      "wujinan/cdn:cdnmaster-gogo-agent-1.0.0"
      "wujinan/cdn:cdnmaster02-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip01-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip02-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip03-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip04-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip05-gogo-agent-1.0.0"
      "wujinan/cdn:cdnvip06-gogo-agent-1.0.0"
    )

    # 先刪除舊的排程
    tmp_cron="/tmp/cron_$$"
    crontab -l 2>/dev/null | grep -v -E '# docker_image_pull_|# daily_remove_' > "$tmp_cron" || true

    day1_day=$(date -d 'tomorrow' +%d)   # 明天
    day1_month=$(date -d 'tomorrow' +%m)
    day2_day=$(date -d '2 days' +%d)     # 後天
    day2_month=$(date -d '2 days' +%m)

    # Day 1 : NORMAL (明天)
    start_total_min=120  # 02:00
    idx=0
    for IMAGE in "${NORMAL_IMAGES[@]}"; do
        total=$(( start_total_min + idx * 30 ))
        hour=$(( (total / 60) % 24 ))
        min=$(( total % 60 ))
        tag="docker_image_pull_normal_${idx}"

        printf "%d %d %s %s * PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; " \
          "$min" "$hour" "$day1_day" "$day1_month" >> "$tmp_cron"
        printf '/bin/echo "===== $(/bin/date '\''+\\%%F \\%%T'\'') pull %s =====" >> %s 2>&1; ' \
          "$IMAGE" "$LOG_FILE" >> "$tmp_cron"
        printf '/usr/bin/flock -n /var/lock/docker_pull.lock -c "/usr/bin/docker pull %s >> %s 2>&1" # %s\n' \
          "$IMAGE" "$LOG_FILE" "$tag" >> "$tmp_cron"
        idx=$((idx + 1))
    done

    # 11:59 Day1 移除 NORMAL
    printf "59 11 %s %s * crontab -l | grep -v '# docker_image_pull_normal_' | crontab - # daily_remove_normal\n" \
      "$day1_day" "$day1_month" >> "$tmp_cron"

    # Day 2 : GOGO (後天)
    start_total_min=120  # 02:00
    idx=0
    for IMAGE in "${GOGO_IMAGES[@]}"; do
        total=$(( start_total_min + idx * 30 ))
        hour=$(( (total / 60) % 24 ))
        min=$(( total % 60 ))
        tag="docker_image_pull_gogo_${idx}"

        printf "%d %d %s %s * PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; " \
          "$min" "$hour" "$day2_day" "$day2_month" >> "$tmp_cron"
        printf '/bin/echo "===== $(/bin/date '\''+\\%%F \\%%T'\'') pull %s =====" >> %s 2>&1; ' \
          "$IMAGE" "$LOG_FILE" >> "$tmp_cron"
        printf '/usr/bin/flock -n /var/lock/docker_pull.lock -c "/usr/bin/docker pull %s >> %s 2>&1" # %s\n' \
          "$IMAGE" "$LOG_FILE" "$tag" >> "$tmp_cron"
        idx=$((idx + 1))
    done

    # 11:59 Day2 移除 GOGO
    printf "59 11 %s %s * crontab -l | grep -v '# docker_image_pull_gogo_' | crontab - # daily_remove_gogo\n" \
      "$day2_day" "$day2_month" >> "$tmp_cron"

    crontab "$tmp_cron" && rm -f "$tmp_cron"
    echo "已建立：Day1=明天 NORMAL、Day2=後天 GOGO。Log：$LOG_FILE"
}


#==========================================================================================================
# 主程式
#==========================================================================================================

# https_test
https_test_mode(){
    echo -e "${GREEN}開始（步驟1）預安裝腳本！${RESET}"
    bash <(curl -sSL $NEW_SCRIPT_BASE_URL/https_test.sh)
    if whiptail --title "https 測試結果" \
        --yesno "是否成功完成 https 測試？" 10 60; then
        echo -e "${GREEN}https 測試成功！${RESET}"
        echo -e "${GREEN}準備預安裝環境中！${RESET}"
        sleep 3
    else
        echo -e "${RED}https 測試失敗！${RESET}"
        exit 1
    fi
}

# 預安裝
preinstall_mode(){
    disable_firewalld
    install_python
    collect_all_user_input || exit 0
    sync_portainer
    clean_docker_log
    download_container_nginx_clean_for_volume
    echo -e "${GREEN}已完成預安裝！${RESET}"
    echo -e "${GREEN}稍後繼續（步驟2）事後安裝腳本${RESET}"
    sleep 3
}

# 事後安裝
postinstall_mode(){
    download_all_post_scripts
    work_flow
    if [ $? -ne 0 ]; then # 如果work_flow回傳是exit 1，表示有失敗，不進行後續步驟
        echo -e "${RED}事後安裝失敗！${RESET}"
        rm -rf /opt/Portainer
        exit 1
    fi
    others_images_cron_once
}

# 主程式
main(){
    # 安裝docker
    bash <(curl -sSL https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/preinstall_only_docker.sh)
    docker ps >/dev/null 2>&1 || { echo -e "${RED}docker 未啟動成功！${RESET}"; exit 1; }

    # 安裝portainer
    preinstall_mode
    docker ps -a | grep portainer >/dev/null 2>&1 || { echo -e "${RED}Portainer 未啟動成功！${RESET}"; exit 1; }

    # 裝容器 + 上節點
    postinstall_mode
    echo -e "${YELLOW}記得確認【節點同步】、【修改節點名子】、【增加子IP】！${RESET}"
    echo -e "${YELLOW}若選擇【穿牆版本】，記得用小工具裝GOGO穿牆${RESET}"
}

main
