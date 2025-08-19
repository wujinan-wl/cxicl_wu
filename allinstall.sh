#!/bin/bash
set -e

# 顏色（純 echo 用，whiptail 不吃 ANSI）
GREEN="\033[32m"; 
YELLOW="\033[33m"; 
RED="\033[31m"; 
RESET="\033[0m"

# 上線後新安裝
NEW_SCRIPT_BASE_URL="https://raw.githubusercontent.com/wujinan-wl/cxicl_wu/main"
run_preinstall()       { bash <(curl -sSL $NEW_SCRIPT_BASE_URL/preinstall.sh); }
run_uninstall_all()    { bash <(curl -sSL $NEW_SCRIPT_BASE_URL/pt_uninstall.sh); }
run_only_docker()      { bash <(curl -sSL $NEW_SCRIPT_BASE_URL/preinstall_only_docker.sh); }
run_docker_portainer() { bash <(curl -sSL $NEW_SCRIPT_BASE_URL/preinstall_docker_portainer.sh); }
run_https_test()       { bash <(curl -sSL $NEW_SCRIPT_BASE_URL/https_test.sh); }

# 舊安裝
run_legacy_install()   { collect_user_input_old_install; }
run_legacy_uninstall() { wget ftp://jengbo:KHdcCNapN6d2FNzK@211.23.160.54/agent_uninstall.sh && chmod +x agent_uninstall.sh && mv agent_uninstall.sh /opt/agent_uninstall.sh && bash /opt/agent_uninstall.sh; }

# 統一的完成提示
pause_choice() {
  local msg="${1:-已完成，請選擇後續動作}"
  if whiptail --backtitle "Excalibur && Stella" --title "完成" \
      --yesno "$msg\n\nYes = 返回選單\nNo = 結束腳本" 12 60; then
    return 0   # Yes → 返回選單
  else
    exit 0     # No → 結束腳本
  fi
}

# 舊安裝方法
collect_user_input_old_install() {
  IP_LIST=$(ip -4 addr | grep inet | awk '{print $2}' | cut -d/ -f1 | grep -vE '^(127|10|172\.1[6-9]|172\.2[0-9]|172\.3[0-1]|192\.168|169\.254)\.')
  NODE_IP=$(echo "$IP_LIST" | head -n1)
  DATE=$(date +%Y%m%d)
  NODE_NAME="${NODE_IP}_${DATE}"

  declare -A CMD_MAP
  CMD_MAP["CDNMASTER"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 203.69.59.134 --es-ip 203.69.59.134 --es-pwd cPPgonzfIe"
  CMD_MAP["CDNMASTER2"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 61.66.110.131 --es-ip 61.66.110.131 --es-pwd vIPU1jHpCi"
  CMD_MAP["CDNVIP"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 122.146.115.2 --es-ip 122.146.115.2 --es-pwd liaz8OAhmx"
  CMD_MAP["CDNVIP01"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.151 --es-ip 211.21.100.151 --es-pwd pDCR7MwqVo"
  CMD_MAP["CDNVIP02"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.152 --es-ip 211.21.100.152 --es-pwd 894QMh0dw2"
  CMD_MAP["CDNVIP03"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.153 --es-ip 211.21.100.153 --es-pwd R8dNi5DZjQ"
  CMD_MAP["CDNVIP04"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.154 --es-ip 211.21.100.154 --es-pwd gwCvT5PY2K"
  CMD_MAP["CDNVIP05"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.155 --es-ip 211.21.100.155 --es-pwd mn7wBIxt8n"
  CMD_MAP["CDNVIP06"]="curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh || curl -m 5 https://cxhilcdn.noctw.com/httpcdnfly/agent.sh -o agent.sh  && chmod +x agent.sh && ./agent.sh --master-ver v5.2.1 --master-ip 211.21.100.156 --es-ip 211.21.100.156 --es-pwd 7z7fi1tbnC"

  PLATFORM=$(whiptail --backtitle "Excalibur && Stella" \
    --title "舊版：選擇主控" --menu "請選擇要連線的主控平台" 22 78 12 \
    "CDNMASTER"  "" \
    "CDNMASTER2" "" \
    "CDNVIP"     "" \
    "CDNVIP01"   "" \
    "CDNVIP02"   "" \
    "CDNVIP03"   "" \
    "CDNVIP04"   "" \
    "CDNVIP05"   "" \
    "CDNVIP06"   "" \
    "返回"       "" 3>&1 1>&2 2>&3) || return 0

  [ "$PLATFORM" = "返回" ] && return 0

  CONFIRM_MSG="請確認：\n\n主控平台：$PLATFORM\n節點主IP：$NODE_IP\n"
  if whiptail --backtitle "Excalibur && Stella" --title "資料確認" --yesno "$CONFIRM_MSG" 12 60; then
    if [[ -n "${CMD_MAP[$PLATFORM]}" ]]; then
      echo -e "${GREEN}開始部署：$PLATFORM${RESET}"
      eval "${CMD_MAP[$PLATFORM]}"
      pause_choice "舊版安裝流程已執行完成。"
    else
      echo -e "${RED}未知主控：$PLATFORM${RESET}"
      pause_choice "未知主控：$PLATFORM"
    fi
  fi
}

# 分組子選單
menu_install_remove() {
  while true; do
    CH=$(whiptail --backtitle "Excalibur && Stella" \
      --title "安裝流程" --menu "選擇安裝步驟" 18 70 8 \
      "1" "（新）安裝腳本" \
      "2" "（新）卸載腳本" \
      "B" "返回主選單" 3>&1 1>&2 2>&3) || return
    case "$CH" in
      1)
        run_preinstall
        pause_choice "安裝腳本已完成。"
        ;;
      2)
        run_uninstall_all
        pause_choice "卸載腳本已完成。"
        ;;
      B) return ;;
    esac
  done
}

menu_legacy() {
  while true; do
    CH=$(whiptail --backtitle "Excalibur && Stella" \
      --title "舊版工具" --menu "舊版安裝/卸載" 18 70 8 \
      "A" "（舊）安裝節點" \
      "R" "（舊）卸載節點" \
      "B" "返回主選單" 3>&1 1>&2 2>&3) || return
    case "$CH" in
      A)
        run_legacy_install
        pause_choice "（舊）安裝節點流程已完成。"
        ;;
      R)
        run_legacy_uninstall
        pause_choice "（舊）卸載節點流程已完成。"
        ;;
      B) return ;;
    esac
  done
}

menu_tools() {
  while true; do
    CH=$(whiptail --backtitle "Excalibur && Stella" \
      --title "小工具" --menu "輔助腳本" 20 70 10 \
      "D" "僅安裝 Docker" \
      "P" "僅安裝 Docker + Portainer" \
      "H" "安裝 https_test" \
      "B" "返回主選單" 3>&1 1>&2 2>&3) || return
    case "$CH" in
      D)
        run_only_docker
        pause_choice "僅安裝 Docker 已完成。"
        ;;
      P)
        run_docker_portainer
        pause_choice "安裝 Docker + Portainer 已完成。"
        ;;
      H)
        run_https_test
        pause_choice "https_test 已完成。"
        ;;
      B) return ;;
    esac
  done
}

# 主選單：只放分組
main_menu() {
  while true; do
    SEL=$(whiptail --backtitle "Excalibur && Stella" \
      --title "主選單" --menu "請選擇動作分類" 20 78 10 \
      "1" "（新版PT）節點安裝 / 卸載" \
      "2" "（舊版）節點安裝 / 卸載" \
      "3" "小工具（Docker/Portainer/https_test）" \
      "Q" "退出" 3>&1 1>&2 2>&3) || exit 1

    case "$SEL" in
      1) menu_install_remove ;;
      2) menu_legacy  ;;
      3) menu_tools   ;;
      Q) exit 0       ;;
    esac
  done
}

main_menu
