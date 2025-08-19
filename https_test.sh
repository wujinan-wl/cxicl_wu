#!/bin/bash
set -e

# 顏色定義
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 設定變數
MAIN_DIR="/opt/https_test"
WORKDIR="$MAIN_DIR/ssl"
CONTAINER_NAME="https_test"
IP_LIST=$(ip -4 addr | grep inet | awk '{print $2}' | cut -d/ -f1 | grep -vE '^(127|10|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]|192\.168|169\.254)\.')
CN_IP=$(hostname -I | awk '{print $1}')  # 用第一個 IP 做為憑證 CN

# 1. 建立工作目錄
create_dir(){
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

    echo -e "${YELLOW}建立主目錄：$MAIN_DIR${RESET}"
    mkdir -p "$WORKDIR" # 建立工作目錄
    sleep 2

    #上線
    wget -O /root/https_test_data.tar.gz "ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/https_test/https_test_data.tar.gz"
    
    mv /root/https_test_data.tar.gz $MAIN_DIR/
    tar -xzvf $MAIN_DIR/https_test_data.tar.gz -C $MAIN_DIR/
}

# 2. 建立自簽憑證
create_ssl_cert() {
    
    echo -e "${YELLOW}建立自簽憑證(CN=$CN_IP)...${RESET}"
    openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$WORKDIR/selfsigned.key" \
    -out "$WORKDIR/selfsigned.crt" \
    -subj "/CN=$CN_IP"
    sleep 5
}

# 3. 建立 Nginx HTTPS 設定
create_nginx_conf() {
    
    echo -e "${YELLOW}產生 Nginx 設定檔...${RESET}"
    cat > "$MAIN_DIR/nginx.conf" << EOF
    events {}

    http {
        server {
            listen 443 ssl;
            server_name localhost;

            ssl_certificate     /etc/nginx/certs/selfsigned.crt;
            ssl_certificate_key /etc/nginx/certs/selfsigned.key;

            location / {
                root /home/www;
                index test.html;
            }
        }
    }
EOF
    sleep 2
}

# 4.產生測試網頁
create_ip_test_web(){
    python $MAIN_DIR/mtr/mtr_analysis.py
}

# 5. 啟動 Docker container
docker_run() {
    echo -e "${YELLOW}啟動 Docker 容器...${RESET}"
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
    docker run -d --name $CONTAINER_NAME \
    -v "$MAIN_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
    -v "$MAIN_DIR/html/:/home/www/" \
    -v "$WORKDIR/selfsigned.crt:/etc/nginx/certs/selfsigned.crt:ro" \
    -v "$WORKDIR/selfsigned.key:/etc/nginx/certs/selfsigned.key:ro" \
    -p 443:443 \
    nginx:alpine
    sleep 3
}

# 6. 顯示所有 IP 可測試清單
output_test_list() {
    echo -e "${GREEN}HTTPS 測試服務已啟動！${RESET}"
    echo -e "${GREEN}可測試以下 IP 是否被屏蔽：${RESET}"
    echo
    echo
    for ip in $IP_LIST; do
        echo -e "https://$ip"
    done
    echo
    echo
    echo -e "${RED}若需要更換IP，請更換完後，再次執行腳本${RESET}"
    echo -e "${GREEN}測試完成請按Enter 卸載此次測試${RESET}"
    read
}

# 7. 卸載 Docker container
test_remove() {
    echo -e "${YELLOW}刪除工作目錄、容器、鏡像...${RESET}"
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
    docker rmi nginx:alpine 2>/dev/null || true
    rm -rf /opt/https_test 2>/dev/null || true
}

# 主程式
bash <(curl -sSL https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main/preinstall_only_docker.sh)
create_dir
create_ssl_cert
create_nginx_conf
create_ip_test_web
docker_run
output_test_list
test_remove

