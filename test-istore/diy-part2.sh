#!/bin/bash
#
# DIY2 - H68K + OpenWrt
# feeds update/install + 加载 .config 后执行
#

# 默认 IP
# sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# 删除官方网络组件
rm -rf ./feeds/packages/net/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata}
rm -rf ./feeds/packages/net/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./feeds/packages/net/{sing-box,v2ray-plugin,xray-core,smartdns}

# 删除官方网络组件安装链接
rm -rf ./package/feeds/packages/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata}
rm -rf ./package/feeds/packages/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./package/feeds/packages/{sing-box,v2ray-plugin,xray-core,smartdns}

# 只删除需要直接替换的官方 LuCI 包
rm -rf ./package/feeds/luci/{luci-app-smartdns,luci-app-mosdns}

# Golang 26.x
rm -rf feeds/packages/lang/golang
rm -rf package/feeds/packages/golang

git clone --filter=blob:none --depth 1 --single-branch \
https://github.com/sbwml/packages_lang_golang \
-b 26.x \
feeds/packages/lang/golang

./scripts/feeds install -p packages golang

# 检查 Golang
echo "===== Golang Makefile ====="

grep -E '^(PKG_VERSION|PKG_RELEASE):=' \
feeds/packages/lang/golang/Makefile || true

echo "===== Host Go ====="

go version || true

echo "===== Golang Feed Link ====="

readlink -f package/feeds/packages/golang 2>/dev/null || true

# 自定义源码
mkdir -p package/small
cd package/small

# V2Ray GeoData
rm -rf v2ray-geodata
git clone --depth 1 \
https://github.com/sbwml/v2ray-geodata.git \
v2ray-geodata

# SmartDNS LuCI
rm -rf luci-app-smartdns
git clone -b master --depth 1 \
https://github.com/pymumu/luci-app-smartdns.git \
luci-app-smartdns

# SmartDNS
rm -rf smartdns
git clone -b master --depth 1 \
https://github.com/pymumu/smartdns.git \
smartdns

# 修复 SmartDNS Rust Makefile
sed -i \
's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
smartdns/package/openwrt/Makefile

# MosDNS
rm -rf mosdns
git clone -b v5 --depth 1 \
https://github.com/sbwml/luci-app-mosdns.git \
mosdns

# AdGuardHome
# rm -rf luci-app-adguardhome
# git clone -b 2024.09.05 --depth 1 \
# https://github.com/XiaoBinin/luci-app-adguardhome.git \
# luci-app-adguardhome

cd ../..

# 自动添加 LuCI 中文语言包
for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config | sed 's/^CONFIG_PACKAGE_//;s/=y//'); do
    trans="luci-i18n-${pkg#luci-app-}"

    grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" .config 2>/dev/null && continue

    if grep -rq "Package.*${trans}-zh-cn" feeds/luci feeds/*/* package 2>/dev/null; then
        echo "添加中文语言包: ${trans}-zh-cn"
        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config
    fi
done

# Wi-Fi 首次启动自动开启
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/zz-enable-wifi <<'EOF'
#!/bin/sh
. /lib/functions.sh

[ -s /etc/config/wireless ] || wifi config

if [ -s /etc/config/wireless ]; then
    config_load wireless

    enable_wifi() {
        local cfg="$1"
        uci -q set "wireless.${cfg}.disabled=0"
    }

    config_foreach enable_wifi wifi-device
    config_foreach enable_wifi wifi-iface

    uci -q commit wireless
fi

exit 0
EOF

chmod +x files/etc/uci-defaults/zz-enable-wifi

echo "DIY2 OK"
