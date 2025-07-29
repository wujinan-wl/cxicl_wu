#!/usr/bin/env bash
# cert.sh —— ZeroSSL 自動續簽所有 aaPanel 站點證書
# 直接寫驗證檔、保存 fullchain/privkey 到 site/ssl 及面板 cert 目錄、自動插入 443 server block、驗證實際啟用

set -euo pipefail

MAX_RETRY=2


# 檢查 jq/openssl 是否安裝，否則自動安裝
for bin in jq openssl; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "[INFO] 檢測到未安裝 $bin，自動安裝中..."
    if [ -f /etc/redhat-release ]; then
      yum install -y $bin
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
      apt-get update && apt-get install -y $bin
    else
      echo "[ERROR] 無法自動安裝 $bin，請手動安裝！"
      exit 1
    fi
  fi
done

# === 配置區 ===
PANEL_URL="https://147.92.46.113:40758"
PANEL_KEY="z9QPfKAwLjEGmL5yImKh0FAqzZpr5SSi"
ZERO_KEY="c783ceb5ee115d543b12cf683fbc10d5"
RENEW_THRESHOLD=30
WEBROOT="/www/wwwroot"

# --- 解析命令列參數 ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --panel-url)      PANEL_URL="$2"; shift 2 ;;
    --panel-key)      PANEL_KEY="$2"; shift 2 ;;
    --zero-key)       ZERO_KEY="$2"; shift 2 ;;
    --renew-threshold) RENEW_THRESHOLD="$2"; shift 2 ;;
    --webroot)        WEBROOT="$2"; shift 2 ;;
    --max-retry)      MAX_RETRY="$2"; shift 2 ;;
    -h|--help)
      echo "用法: $0 [--panel-url URL] [--panel-key KEY] [--zero-key KEY] [--renew-threshold N] [--webroot DIR] [--max-retry N]"
      exit 0
      ;;
    *)
      echo "[ERROR] 未知參數: $1"
      exit 1
      ;;
  esac
done

gen_token(){
  local ts md5 tk
  ts=$(date +%s)
  md5=$(echo -n "$PANEL_KEY" | md5sum | cut -d' ' -f1)
  tk=$(printf "%s%s" "$ts" "$md5" | md5sum | cut -d' ' -f1)
  echo "$ts" "$tk"
}

install_ssl_local(){
  local site="$1" crt_pem="$2" key_pem="$3"
  local cert_dir="/www/server/panel/vhost/cert/${site}"
  mkdir -p "$cert_dir"
  cp "$crt_pem" "$cert_dir/fullchain.pem"
  cp "$key_pem" "$cert_dir/privkey.pem"
  cp "$crt_pem" "$cert_dir/server.crt"
  cp "$key_pem" "$cert_dir/server.key"
  echo "  已複製證書到 $cert_dir（fullchain.pem, privkey.pem, server.crt, server.key）"
}

add_ssl_server_block(){
  local site="$1"
  local conf_file="/www/server/panel/vhost/nginx/${site}.conf"
  local cert_dir="/www/server/panel/vhost/cert/${site}"
  # 避免重複插入
  if grep -q "listen 443" "$conf_file"; then
    echo "  [$site] 已有 443 區塊，略過自動新增"
    return
  fi

  # 取得主站設定的 root、server_name
  local root_path server_name
  root_path=$(grep 'root ' "$conf_file" | head -1 | awk '{print $2}' | sed 's/;//')
  server_name=$(grep 'server_name ' "$conf_file" | head -1 | awk '{print $2}' | sed 's/;//')
  [ -z "$root_path" ] && root_path="/www/wwwroot/$site"
  [ -z "$server_name" ] && server_name="$site"

cat <<EOF >> "$conf_file"

# ---- cert.sh 自動加入 HTTPS 443 SSL server ----
server {
    listen 443 ssl http2;
    server_name $server_name;
    root $root_path;
    index index.php index.html index.htm default.php default.htm default.html;

    ssl_certificate      $cert_dir/fullchain.pem;
    ssl_certificate_key  $cert_dir/privkey.pem;
    ssl_session_timeout  10m;
    ssl_session_cache    shared:SSL:10m;
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH;
    ssl_prefer_server_ciphers on;
    add_header Strict-Transport-Security "max-age=63072000" always;

    include enable-php-00.conf;
    include /www/server/panel/vhost/rewrite/${site}.conf;

    access_log  /www/wwwlogs/${site}.ssl.log;
    error_log   /www/wwwlogs/${site}.ssl.error.log;
}
EOF

  echo "  [$site] 已自動插入 443 SSL 區塊"
}

get_local_cert_fingerprint(){
  local site="$1"
  local crt="/www/server/panel/vhost/cert/${site}/server.crt"
  if [ -f "$crt" ]; then
    openssl x509 -in "$crt" -noout -fingerprint -sha1 | awk -F= '{print $2}' | sed 's/://g'
  else
    echo ""
  fi
}

get_remote_cert_fingerprint(){
  local domain="$1"
  # 注意：這會連線到自己站台 443 取得遠端證書指紋
  openssl s_client -connect "$domain:443" -servername "$domain" -showcerts </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha1 | awk -F= '{print $2}' | sed 's/://g'
}

get_local_cert_expiry(){
  local site="$1"
  local crt="/www/server/panel/vhost/cert/${site}/server.crt"
  if [ -f "$crt" ]; then
    openssl x509 -in "$crt" -noout -enddate | cut -d= -f2
  else
    echo ""
  fi
}

get_remote_cert_expiry(){
  local domain="$1"
  openssl s_client -connect "$domain:443" -servername "$domain" -showcerts </dev/null 2>/dev/null \
    | openssl x509 -noout -enddate | cut -d= -f2
}

issue_cert(){
  local site="$1"
  echo "[INFO] 处理站點：$site"
  # 產生 CSR & 私鑰
  CSR="/tmp/${site}.csr"
  KEY="/tmp/${site}.key"
  cat > /tmp/csr_ext.cnf <<EOF
[req]
distinguished_name=req_distinguished_name
req_extensions=v3_req
prompt=no

[req_distinguished_name]
CN=${site}

[v3_req]
subjectAltName=@alt_names

[alt_names]
DNS.1=${site}
EOF
  openssl genrsa 2048 >"$KEY"
  openssl req -new -sha256 -key "$KEY" -config /tmp/csr_ext.cnf -out "$CSR"

  # 申請 ZeroSSL
  cert_json=$(curl -s -k -X POST \
    "https://api.zerossl.com/certificates?access_key=${ZERO_KEY}" \
    -d certificate_domains="$site" \
    -d validation_method="HTTP_CSR_HASH" \
    --data-urlencode certificate_csr@"$CSR")
  cert_id=$(jq -r '.id // empty' <<<"$cert_json")
  if [ -z "$cert_id" ]; then
    echo "  [ERROR] 申請失敗：$(jq -c . <<<"$cert_json")"
    return 1
  fi

  # 讀取驗證資訊
  validation=$(jq -r --arg d "$site" '.validation.other_methods[$d] // empty' <<<"$cert_json")
  filename=$(jq -r '.file_validation_url_http | split("/")[-1]' <<<"$validation")
  mapfile -t CONTENTS < <(jq -r '.file_validation_content[]' <<<"$validation")
  PKI_DIR="${WEBROOT}/${site}/.well-known/pki-validation"
  mkdir -p "$PKI_DIR"
  : > "$PKI_DIR/$filename"
  for line in "${CONTENTS[@]}"; do
    printf '%s\n' "$line" >> "$PKI_DIR/$filename"
  done
  echo "  已寫入驗證文件：$PKI_DIR/$filename"

  # 觸發驗證並輪詢
  curl -s -k -X POST "https://api.zerossl.com/certificates/${cert_id}/challenges?access_key=${ZERO_KEY}" \
    -d validation_method="HTTP_CSR_HASH" >/dev/null
  echo -n "  等待簽發"
  while true; do
    status=$(curl -s -k "https://api.zerossl.com/certificates/${cert_id}?access_key=${ZERO_KEY}" | jq -r '.status')
    echo -n "."
    [[ "$status" == "issued" ]] && break
    [[ "$status" == "cancelled" || "$status" == "expired" ]] && { echo " [ERROR] 簽發失敗：$status"; return 1; }
    sleep 5
  done
  echo " 完成"

  # 下載保存證書
  dl=$(curl -s -k "https://api.zerossl.com/certificates/${cert_id}/download/return?access_key=${ZERO_KEY}&certificate_format=pem")
  crt=$(jq -r '.certificate // .["certificate.crt"] // empty' <<<"$dl")
  ca=$(jq -r '.ca_bundle // .["ca_bundle.crt"] // empty' <<<"$dl")
  if [[ -z "$crt" || -z "$ca" || "$crt" == "null" || "$ca" == "null" ]]; then
    echo "[ERROR] 未正確取得證書，請檢查 ZeroSSL 憑證訂單/驗證檔案。"
    return 1
  fi
  SSL_DIR="${WEBROOT}/${site}/ssl"
  mkdir -p "$SSL_DIR"
  printf '%s\n%s\n' "$crt" "$ca" > "$SSL_DIR/fullchain.pem"
  cp "$KEY" "$SSL_DIR/privkey.pem"
  echo "  已保存證書和私鑰到 $SSL_DIR"

  install_ssl_local "$site" "$SSL_DIR/fullchain.pem" "$SSL_DIR/privkey.pem"
  echo "  ✅ ${site} 已更新"
  add_ssl_server_block "$site"
  return 0
}

check_and_reissue_cert(){
  local site="$1"
  # 取 server.conf 有沒有 443 block，沒的話直接判定需要處理
  local conf_file="/www/server/panel/vhost/nginx/${site}.conf"
  if ! grep -q "listen 443" "$conf_file"; then
    echo "  [$site] 未配置 443 SSL，標記為需重發"
    return 1
  fi

  # 指紋比對（本地/遠端都必須能拿到 fingerprint）
  local_fp=$(get_local_cert_fingerprint "$site")
  remote_fp=$(get_remote_cert_fingerprint "$site")
  local_exp=$(get_local_cert_expiry "$site")
  remote_exp=$(get_remote_cert_expiry "$site")
  echo "  [$site] 檢查 443 憑證內容..."
  if [[ -z "$local_fp" || -z "$remote_fp" ]]; then
    echo "    [警告] 指紋取得失敗，標記為需重發"
    return 1
  fi
  if [[ "$local_fp" == "$remote_fp" ]]; then
    echo "    已正確啟用 ✅"
    return 0
  else
    echo "    ❌ [警告] 網站未正確掛載新憑證！"
    echo "    [本地指紋] $local_fp"
    echo "    [遠端指紋] $remote_fp"
    echo "    [本地到期] $local_exp"
    echo "    [遠端到期] $remote_exp"
    echo "    自動刪除舊證書，重新部署..."
    rm -f /www/server/panel/vhost/cert/${site}/*.pem
    rm -f /www/server/panel/vhost/cert/${site}/*.crt
    rm -f /www/server/panel/vhost/cert/${site}/*.key
    rm -f /www/wwwroot/${site}/ssl/*
    return 1
  fi
}

echo "[INFO] 開始續簽流程 $(date '+%F %T')"

read ts tk <<<"$(gen_token)"
sites_json=$(curl -s -k -X POST "${PANEL_URL}/data?action=getData&table=sites" \
  -d request_time="$ts" -d request_token="$tk" \
  -d p=1 -d limit=200 -d order=id)
mapfile -t SITES < <(jq -r '.data[].name // empty' <<<"$sites_json")
if [ "${#SITES[@]}" -eq 0 ]; then
  echo "[WARN] 未找到站點，退出。"
  exit 0
fi

for site in "${SITES[@]}"; do
  # 直接檢查有效天數（以本地憑證為主）
  cert_path="/www/server/panel/vhost/cert/${site}/server.crt"
  if [ -f "$cert_path" ]; then
    expire=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    expire_ts=$(date -d "$expire" +%s 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    remain=$(( (expire_ts - now_ts) / 86400 ))
  else
    remain=0
  fi
  echo
  echo "[INFO] 处理站點：$site"
  echo "  剩餘證書天數：$remain"
  if (( remain > RENEW_THRESHOLD )); then
    echo "  跳過：有效期大於 ${RENEW_THRESHOLD} 天"
  else
    issue_cert "$site"
    nginx -t && nginx -s reload
    sleep 5
  fi

  # 443 指紋比對防掛錯，最多重簽 MAX_RETRY 次
  try=0
  ok=0
  while (( try < MAX_RETRY )); do
    if ! check_and_reissue_cert "$site"; then
      issue_cert "$site"
      nginx -t && nginx -s reload
      sleep 5
      ((try++))
    else
      ok=1
      break
    fi
  done
  if (( ok == 0 )); then
    echo "  [FATAL] $site 憑證異常，請手動檢查 nginx 與憑證配置！"
  fi
done

echo "[INFO] 全部站點續簽完成 $(date '+%F %T')"
nginx -t && nginx -s reload
