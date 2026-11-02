
#!/bin/bash
set -e

# ============================================================
# 1. 更改默认地址为 192.168.8.1
# ============================================================

for config_generate in package/base-files/{files,luci}/bin/config_generate; do
    if [ -f "$config_generate" ]; then
        sed -i 's/192.168.1.1/192.168.8.1/g' "$config_generate"
    fi
done


# ============================================================
# 2. 给 config 下的文件增加权限
# ============================================================

chmod 644 files/etc/config/*


# ============================================================
# 3. 默认开启无线
#    5GHz：信道 36
#    国家代码：US
# ============================================================

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-enable-wireless <<'EOF'
#!/bin/sh

# 遍历所有无线设备
for radio in $(uci -q show wireless | \
    sed -n 's/^wireless\.\(@wifi-device\[[0-9]*\]\)=wifi-device$/\1/p'); do

    [ -n "$radio" ] || continue

    band="$(uci -q get wireless.${radio}.band)"
    hwmode="$(uci -q get wireless.${radio}.hwmode)"

    # 默认开启无线
    uci set wireless.${radio}.disabled='0'

    # 仅设置 5GHz 无线参数
    if [ "$band" = "5g" ] || [ "$hwmode" = "11a" ]; then
        uci set wireless.${radio}.channel='36'
        uci set wireless.${radio}.country='US'

        echo "5GHz: channel 36, country US"
    fi

done

# 提交无线配置
uci commit wireless

exit 0
EOF

chmod 755 files/etc/uci-defaults/99-enable-wireless

echo "无线默认开启配置已添加"


# ============================================================
# 4. 设置最大连接跟踪数为 655500
# ============================================================

mkdir -p files/etc/sysctl.d

cat > files/etc/sysctl.d/99-conntrack.conf <<'EOF'
net.netfilter.nf_conntrack_max=655500
EOF

echo "最大连接跟踪数已设置为 655500"


# ============================================================
# 5. 更改 design 主题为白色
# ============================================================

# sed -i 's/dark/light/g' feeds/luci/applications/luci-app-design-config/root/etc/config/design


# ============================================================
# 6. HomeProxy 规则和 DNS 配置
# ============================================================

echo "开始处理 homeproxy 规则和 DNS 配置..."
echo "========================================"

HOMEPROXY_DIR="./package/small/homeproxy"

if [ ! -d "$HOMEPROXY_DIR" ]; then
    HOMEPROXY_DIR="./feeds/luci/applications/luci-app-homeproxy"
fi

DNS_CONFIG_FILE="${HOMEPROXY_DIR}/root/etc/config/homeproxy"

if [ ! -d "${HOMEPROXY_DIR}" ]; then
    echo "错误：luci-app-homeproxy 目录不存在！"
    exit 1
fi

HP_RULE="surge"
HP_PATH="root/etc/homeproxy"

rm -rf "${HOMEPROXY_DIR}/${HP_PATH}/resources/"*

git clone -q --depth=1 --single-branch --branch "release" \
  "https://github.com/Loyalsoldier/surge-rules.git" "./${HP_RULE}/"

cd "./${HP_RULE}/" && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

echo "${RES_VER}" | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver

awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt

sed 's/^\.//g' direct.txt > china_list.txt
sed 's/^\.//g' gfw.txt > gfw_list.txt

mv -f ./{china_*,gfw_list}.{ver,txt} "../${HOMEPROXY_DIR}/${HP_PATH}/resources/"

cd .. && rm -rf "./${HP_RULE}/"

echo "✅ homeproxy 规则已更新"


# ============================================================
# 7. 修改 HomeProxy DNS
# ============================================================

if [ -f "${DNS_CONFIG_FILE}" ]; then

    sed -i 's/option dns_server '\''8.8.8.8'\''/option dns_server '\''https:\/\/94.140.14.140\/dns-query'\''/g' "${DNS_CONFIG_FILE}"

    sed -i 's/option china_dns_server '\''223.5.5.5'\''/option china_dns_server '\''https:\/\/223.5.5.5\/dns-query'\''/g' "${DNS_CONFIG_FILE}"

    echo "✅ DNS 服务器已修改"

else

    echo "⚠️ 警告：DNS 配置文件 ${DNS_CONFIG_FILE} 不存在！"

fi


# ============================================================
# 8. 完成
# ============================================================

echo "========================================"
echo "HomeProxy 处理完成！"
echo "无线默认开启：是"
echo "5GHz 信道：36"
echo "无线国家代码：US"
echo "最大连接跟踪数：655500"
echo "默认 LAN IP：192.168.8.1"
echo "初始化设置执行成功!"
