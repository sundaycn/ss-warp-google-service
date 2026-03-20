#!/bin/bash

# sing-box 一键脚本
# 基于 sing-box + TUN 模式，解锁 Google, Netflix, Disney+ 等流媒体
# 支持 Geosite 域名识别、UDP/QUIC、内置路由引擎、内置 WireGuard 协议
# 新增: 地理数据每日自动更新

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
ARCH=$(uname -m)
OS=$(source /etc/os-release && echo $ID)
OS_VERSION=$(source /etc/os-release && echo $VERSION_ID)
SING_BOX_VERSION="1.9.0" # 你可以修改为最新的版本
WGCF_VERSION="2.2.19"
SING_BOX_DIR="/etc/sing-box"
SING_BOX_EXEC="/usr/local/bin/sing-box"
WGCF_EXEC="/usr/local/bin/wgcf"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
CONFIG_FILE="${SING_BOX_DIR}/config.json"
GEOIP_FILE="${SING_BOX_DIR}/geoip.db"
GEOSITE_FILE="${SING_BOX_DIR}/geosite.db"
UPDATE_SCRIPT="/usr/local/bin/update-geodata.sh"
CRON_FILE="/etc/cron.daily/sing-box-geodata-update"

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        🚀 sing-box + WARP 一键安装脚本 (TUN 模式) v2.0         ║"
    echo "║                                                              ║"
    echo "║  - Geosite 域名路由  -  UDP/QUIC 支持  -  每日自动更新数据     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查 root
check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}错误: 请使用 root 用户运行此脚本！${NC}"; exit 1; }
}

# 检查系统和依赖
check_system() {
    echo -e "${YELLOW}正在检查系统环境...${NC}"
    case "$ARCH" in
        "x86_64") ARCH_L="amd64" ;;
        "aarch64") ARCH_L="arm64" ;;
        "armv7l") ARCH_L="armv7" ;;
        *) echo -e "${RED}错误: 不支持的系统架构: $ARCH${NC}"; exit 1 ;;
    esac

    # 安装依赖
    if ! command -v curl &>/dev/null || ! command -v tar &>/dev/null || ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}正在安装必要的依赖 (curl, tar, jq)...${NC}"
        case "$OS" in
            ubuntu|debian)
                apt-get update -y && apt-get install -y curl tar jq cron
                ;;
            centos|rhel|fedora|rocky|almalinux)
                yum install -y curl tar jq cronie || dnf install -y curl tar jq cronie
                ;;
            *)
                echo -e "${RED}错误: 无法在此系统上自动安装依赖。请手动安装 curl, tar, jq, cron。${NC}"
                exit 1
                ;;
        esac
    fi
    echo -e "${GREEN}✓ 系统环境检查通过${NC}"
}

# 下载并安装 sing-box
install_sing_box() {
    echo -e "
${CYAN}[1/7] 正在安装 sing-box...${NC}"
    
    # 构造下载链接
    SING_BOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH_L}.tar.gz"

    echo -e "下载链接: ${SING_BOX_URL}"
    
    # 下载并解压
    curl -sSL -o /tmp/sing-box.tar.gz "$SING_BOX_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: sing-box 下载失败，请检查网络或链接。${NC}"
        exit 1
    fi
    
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    
    # 移动到执行目录
    mv /tmp/sing-box-${SING_BOX_VERSION}-linux-${ARCH_L}/sing-box ${SING_BOX_EXEC}
    chmod +x ${SING_BOX_EXEC}
    
    # 清理
    rm -rf /tmp/sing-box*
    
    if ! command -v sing-box &> /dev/null; then
        echo -e "${RED}错误: sing-box 安装失败。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ sing-box v$(${SING_BOX_EXEC} version | head -n 1 | awk '{print $3}') 安装成功${NC}"
}

# 下载地理数据
download_geodata() {
    echo -e "
${CYAN}[2/7] 正在下载 Geosite 和 GeoIP 数据...${NC}"
    mkdir -p ${SING_BOX_DIR}
    
    # Geosite
    GEOSITE_URL="https://github.com/SagerNet/sing-box-geodata/releases/latest/download/geosite.db"
    curl -sSL -o ${GEOSITE_FILE} "$GEOSITE_URL"
    if [ ! -f "$GEOSITE_FILE" ]; then
        echo -e "${RED}错误: Geosite.db 下载失败。${NC}"
        exit 1
    fi
    
    # GeoIP
    GEOIP_URL="https://github.com/SagerNet/sing-box-geodata/releases/latest/download/geoip.db"
    curl -sSL -o ${GEOIP_FILE} "$GEOIP_URL"
    if [ ! -f "$GEOIP_FILE" ]; then
        echo -e "${RED}错误: GeoIP.db 下载失败。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 地理数据下载完成${NC}"
}

# 获取 WARP WireGuard 配置
get_warp_config() {
    echo -e "
${CYAN}[3/7] 正在获取 WARP WireGuard 配置...${NC}"
    
    # 下载 wgcf
    WGCF_URL="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_linux_${ARCH_L}"
    curl -sSL -o ${WGCF_EXEC} "$WGCF_URL"
    chmod +x ${WGCF_EXEC}
    
    # 注册并生成配置
    echo | ${WGCF_EXEC} register --accept-tos
    if [ ! -f "wgcf-account.toml" ]; then
        echo -e "${RED}错误: WARP 账户注册失败。${NC}"
        exit 1
    fi
    
    ${WGCF_EXEC} generate
    if [ ! -f "wgcf-profile.conf" ]; then
        echo -e "${RED}错误: WARP WireGuard 配置生成失败。${NC}"
        exit 1
    fi
    
    # 提取配置信息
    PRIVATE_KEY=$(grep "PrivateKey" wgcf-profile.conf | awk '{print $3}')
    IPV4_ENDPOINT=$(grep "Endpoint" wgcf-profile.conf | awk '{print $3}' | sed 's/\[2606:4700:d0::a29f:c001\]/162.159.192.1/')

    if [ -z "$PRIVATE_KEY" ] || [ -z "$IPV4_ENDPOINT" ]; then
        echo -e "${RED}错误: 无法从 wgcf-profile.conf 提取必要的 WireGuard 信息。${NC}"
        exit 1
    fi

    # 清理 wgcf 文件
    mv wgcf-profile.conf wgcf-account.toml ${SING_BOX_DIR}/
    
    echo -e "${GREEN}✓ WARP 配置获取成功${NC}"
}

# 创建 sing-box 配置文件
create_config() {
    echo -e "
${CYAN}[4/7] 正在创建 sing-box 配置文件...${NC}"
    
    PRIVATE_KEY=$(grep "PrivateKey" ${SING_BOX_DIR}/wgcf-profile.conf | awk '{print $3}')
    IPV4_ENDPOINT=$(grep "Endpoint" ${SING_BOX_DIR}/wgcf-profile.conf | awk '{print $3}' | sed 's/\[2606:4700:d0::a29f:c001\]/162.159.192.1/')
    
    cat > ${CONFIG_FILE} << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "tun", "tag": "tun-in", "interface_name": "warp",
      "inet4_address": "172.19.0.1/30", "mtu": 1280, "auto_route": true,
      "strict_route": true, "stack": "gvisor", "endpoint_independent_nat": true
    }
  ],
  "outbounds": [
    {
      "type": "wireguard", "tag": "warp-out", "server": "${IPV4_ENDPOINT}",
      "server_port": 2408, "local_address": ["172.16.0.2/32"],
      "private_key": "${PRIVATE_KEY}", "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SsoKiNYeminrTyLbcidao=", "mtu": 1280
    },
    { "type": "direct", "tag": "direct-out" },
    { "type": "block", "tag": "block-out" }
  ],
  "route": {
    "rules": [
      { "geosite": "category-ads-all", "outbound": "block-out" },
      { "geosite": "cn", "outbound": "direct-out" },
      { "geoip": "cn", "outbound": "direct-out" },
      { "geosite": ["netflix", "disney", "google", "youtube", "openai"], "outbound": "warp-out" },
      { "network": "udp,tcp", "outbound": "warp-out" }
    ],
    "geosite": { "path": "${GEOSITE_FILE}" },
    "geoip": { "path": "${GEOIP_FILE}" },
    "auto_detect_interface": true
  },
  "experimental": {
    "clash_api": { "external_controller": "127.0.0.1:9090", "secret": "" }
  }
}
EOF
    
    echo -e "${GREEN}✓ 配置文件创建成功: ${CONFIG_FILE}${NC}"
}

# 创建并启动 systemd 服务
setup_service() {
    echo -e "
${CYAN}[5/7] 正在设置并启动 systemd 服务...${NC}"
    
    cat > ${SERVICE_FILE} << EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
Type=simple
ExecStart=${SING_BOX_EXEC} run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=10
LimitNPROC=500
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✓ sing-box 服务已成功启动${NC}"
    else
        echo -e "${RED}错误: sing-box 服务启动失败。请运行 'journalctl -u sing-box' 查看日志。${NC}"
    fi
}

# 创建地理数据更新脚本
create_update_script() {
    echo -e "
${CYAN}[6/7] 正在创建地理数据更新脚本...${NC}"
    cat > ${UPDATE_SCRIPT} << 'EOF'
#!/bin/bash
# sing-box geodata update script

LOG_FILE="/var/log/sing-box-geodata-update.log"
SING_BOX_DIR="/etc/sing-box"
GEOSITE_FILE="${SING_BOX_DIR}/geosite.db"
GEOIP_FILE="${SING_BOX_DIR}/geoip.db"

echo " " >> $LOG_FILE
echo "====== $(date) ======" >> $LOG_FILE
echo "Starting geodata update for sing-box..." >> $LOG_FILE

# Download to temp
curl -sSL -o /tmp/geosite.db.tmp "https://github.com/SagerNet/sing-box-geodata/releases/latest/download/geosite.db"
curl -sSL -o /tmp/geoip.db.tmp "https://github.com/SagerNet/sing-box-geodata/releases/latest/download/geoip.db"

if [ -s "/tmp/geosite.db.tmp" ] && [ -s "/tmp/geoip.db.tmp" ]; then
    echo "Geodata downloaded successfully." >> $LOG_FILE
    mv /tmp/geosite.db.tmp ${GEOSITE_FILE}
    mv /tmp/geoip.db.tmp ${GEOIP_FILE}
    
    if systemctl is-active --quiet sing-box; then
        echo "Restarting sing-box service..." >> $LOG_FILE
        systemctl restart sing-box
        echo "sing-box service restarted." >> $LOG_FILE
    fi
    echo "Geodata update completed." >> $LOG_FILE
else
    echo "Error: Failed to download geodata files." >> $LOG_FILE
    rm -f /tmp/geosite.db.tmp /tmp/geoip.db.tmp
fi
EOF
    chmod +x ${UPDATE_SCRIPT}
    echo -e "${GREEN}✓ 地理数据更新脚本创建成功: ${UPDATE_SCRIPT}${NC}"
}

# 设置每日更新的 Cron 任务
setup_cron_job() {
    echo -e "
${CYAN}[7/7] 正在设置每日自动更新任务...${NC}"
    cat > ${CRON_FILE} << EOF
#!/bin/bash
/bin/bash ${UPDATE_SCRIPT}
EOF
    chmod +x ${CRON_FILE}
    echo -e "${GREEN}✓ 每日自动更新任务创建成功: ${CRON_FILE}${NC}"
}


# 创建管理脚本
create_management_script() {
    cat > /usr/local/bin/sb << 'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
case "$1" in
    start) systemctl start sing-box; echo -e "${GREEN}sing-box 服务已启动${NC}";;
    stop) systemctl stop sing-box; echo -e "${GREEN}sing-box 服务已停止${NC}";;
    restart) systemctl restart sing-box; echo -e "${GREEN}sing-box 服务已重启${NC}";;
    status) systemctl status sing-box --no-pager | grep -E "Loaded|Active|Main PID";;
    log) journalctl -u sing-box -f --no-pager;;
    test)
        echo -e "${CYAN}=== 测试 IP 地址 ===${NC}"
        DIRECT_IP=$(curl -s --max-time 5 ip.sb)
        echo -e "直连 IP: ${YELLOW}${DIRECT_IP}${NC}"
        if ip link show warp &> /dev/null; then
            WARP_IP=$(curl -s --max-time 10 --interface warp ip.sb)
            if [ -n "$WARP_IP" ]; then echo -e "WARP IP: ${GREEN}${WARP_IP}${NC}"; else echo -e "WARP IP: ${RED}获取失败${NC}"; fi
        else echo -e "WARP IP: ${RED}TUN 'warp' 接口不存在${NC}"; fi;;
    update-geo)
        echo "正在手动更新地理数据..."
        /bin/bash /usr/local/bin/update-geodata.sh
        echo "更新完成，请查看日志: /var/log/sing-box-geodata-update.log";;
    uninstall)
        bash <(curl -sL https://raw.githubusercontent.com/sundial-dreams/one-click-scripts/main/sing-box-warp.sh) uninstall;;
    *)
        echo -e "用法: ${CYAN}sb <命令>${NC}"
        echo "命令:"
        echo "  start, stop, restart  控制服务"
        echo "  status                查看状态"
        echo "  log                   查看实时日志"
        echo "  test                  测试 IP 地址"
        echo "  update-geo            手动更新地理数据"
        echo "  uninstall             卸载";;
esac
EOF
    chmod +x /usr/local/bin/sb
}

# 安装主流程
do_install() {
    check_root
    check_system
    install_sing_box
    download_geodata
    get_warp_config
    create_config
    setup_service
    create_update_script
    setup_cron_job
    create_management_script
    
    echo -e "
${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          🎉 安装完成！享受你的网络吧！🎉            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "
${YELLOW}系统流量现已通过 WARP 接管，地理数据将每日自动更新。${NC}"
    echo -e "
管理命令: ${CYAN}sb {start|stop|restart|status|log|test|update-geo|uninstall}${NC}
"
}

# 卸载
do_uninstall() {
    check_root
    echo -e "${YELLOW}正在卸载 sing-box 和相关配置...${NC}"
    systemctl stop sing-box
    systemctl disable sing-box
    rm -f ${SERVICE_FILE}
    rm -f ${SING_BOX_EXEC}
    rm -rf ${SING_BOX_DIR}
    rm -f /usr/local/bin/sb
    rm -f ${WGCF_EXEC}
    rm -f ${UPDATE_SCRIPT}
    rm -f ${CRON_FILE}
    rm -f /var/log/sing-box-geodata-update.log
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成。${NC}"
}

# 显示菜单
show_menu() {
    echo -e "${YELLOW}请选择操作:${NC}
"
    echo -e "  ${GREEN}1.${NC} 安装/更新 sing-box + WARP"
    echo -e "  ${GREEN}2.${NC} 卸载"
    echo -e "  ${GREEN}0.${NC} 退出
"
    
    read -p "请输入选项 [0-2]: " choice
    
    case $choice in
        1) do_install ;;
        2) do_uninstall ;;
        0) echo -e "
${GREEN}再见！${NC}
"; exit 0 ;;
        *) echo -e "
${RED}无效选项${NC}
" ;;
    esac
}

# 主入口
main() {
    show_banner
    if [[ "$1" == "uninstall" ]]; then
        do_uninstall
        exit 0
    fi
    show_menu
}

main "$@"
