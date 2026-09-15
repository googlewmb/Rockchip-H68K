#!/bin/bash
#
# DIY2
# H68K + OpenWrt 24.10
#

set -e

cd "$GITHUB_WORKSPACE/openwrt"

echo "OpenWrt Root:"
pwd

if [ ! -f .config ]; then
    echo "ERROR: .config 不存在，DIY2 终止"
    exit 1
fi

echo ".config OK"

# 默认 IP
# sed -i 's/192.168.1.1/192.168.50.5/g' \
# package/base-files/files/bin/config_generate

# 删除官方冲突网络组件
echo "删除官方冲突网络组件"

rm -rf ./feeds/packages/net/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata}
rm -rf ./feeds/packages/net/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./feeds/packages/net/{sing-box,v2ray-plugin,xray-core,smartdns,lucky}

# 删除官方 LuCI 网络组件
rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-passwall2}
rm -rf ./feeds/luci/applications/{luci-app-openclash,luci-app-homeproxy}
rm -rf ./feeds/luci/applications/{luci-app-lucky,luci-app-timecontrol}
rm -rf ./feeds/luci/applications/{luci-app-mosdns,luci-app-nikki}
rm -rf ./feeds/luci/applications/{luci-app-momo,luci-app-daed}

# 删除官方 feeds 安装链接
rm -rf ./package/feeds/packages/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata}
rm -rf ./package/feeds/packages/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./package/feeds/packages/{sing-box,v2ray-plugin,xray-core,smartdns,lucky}

rm -rf ./package/feeds/luci/{luci-app-smartdns,luci-app-mosdns}

# Golang 27.x
echo "安装 Golang 27.x"

rm -rf feeds/packages/lang/golang
rm -rf package/feeds/packages/golang

git clone --filter=blob:none --depth 1 --single-branch \
https://github.com/sbwml/packages_lang_golang \
-b 27.x \
feeds/packages/lang/golang

echo "Golang 目录:"
ls -la feeds/packages/lang/golang || true

echo "Golang Makefile:"
find feeds/packages/lang/golang \
-maxdepth 4 \
-type f \
-name 'Makefile' \
-print || true

echo "Golang 版本:"
grep -R -E '^(PKG_VERSION|PKG_RELEASE):=' \
feeds/packages/lang/golang \
2>/dev/null | head -20 || true

echo "Host Go:"
go version || true

echo "安装 Golang:"
./scripts/feeds install -p packages golang || true

echo "Golang Feed Link:"
readlink -f package/feeds/packages/golang 2>/dev/null || true

if [ -d package/feeds/packages/golang ]; then
    echo "Golang feed link OK"
else
    echo "WARNING: package/feeds/packages/golang 不存在"
fi

# V2Ray GeoData
echo "安装 V2Ray GeoData"

mkdir -p package/small

cd package/small

rm -rf v2ray-geodata

git clone --depth 1 \
https://github.com/sbwml/v2ray-geodata.git \
v2ray-geodata

cd "$GITHUB_WORKSPACE/openwrt"

# SmartDNS
echo "安装 SmartDNS"

mkdir -p package/small

cd package/small

rm -rf luci-app-smartdns
rm -rf smartdns

git clone -b master --depth 1 \
https://github.com/pymumu/luci-app-smartdns.git \
luci-app-smartdns

git clone -b master --depth 1 \
https://github.com/pymumu/smartdns.git \
smartdns

# 修复 SmartDNS Rust Makefile
if [ -f smartdns/package/openwrt/Makefile ]; then
    sed -i \
    's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
    smartdns/package/openwrt/Makefile
fi

cd "$GITHUB_WORKSPACE/openwrt"

# MosDNS
echo "安装 MosDNS"

mkdir -p package/small

cd package/small

rm -rf mosdns

git clone -b v5 --depth 1 \
https://github.com/sbwml/luci-app-mosdns.git \
mosdns

cd "$GITHUB_WORKSPACE/openwrt"

# AdGuardHome
# git clone -b 2024.09.05 --depth 1 \
# https://github.com/XiaoBinin/luci-app-adguardhome.git \
# package/small/luci-app-adguardhome

# 自动添加 LuCI 中文语言包
echo "自动添加 LuCI 中文语言包"

cd "$GITHUB_WORKSPACE/openwrt"

for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config | \
    sed 's/^CONFIG_PACKAGE_//;s/=y//'); do

    trans="luci-i18n-${pkg#luci-app-}"

    if grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
    .config 2>/dev/null; then
        continue
    fi

    if grep -rq "Package.*${trans}-zh-cn" \
    feeds/luci feeds/*/* package 2>/dev/null; then

        echo "添加中文语言包: ${trans}-zh-cn"
        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

    fi
done

# WiFi 默认开启
echo "设置 WiFi 首次启动自动开启"

cd "$GITHUB_WORKSPACE/openwrt"

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

# 最终检查
echo "最终检查"

cd "$GITHUB_WORKSPACE/openwrt"

echo "OpenWrt Root:"
pwd

echo "Config:"
if [ -f .config ]; then
    echo ".config OK"
else
    echo "ERROR: .config NOT FOUND"
    exit 1
fi

echo "Golang:"
if [ -d feeds/packages/lang/golang ]; then
    echo "Golang feed directory OK"
else
    echo "WARNING: Golang feed directory 不存在"
fi

echo "Golang Makefile:"
find feeds/packages/lang/golang \
-maxdepth 4 \
-type f \
-name 'Makefile' \
-print || true

echo "V2Ray GeoData:"
if [ -d package/small/v2ray-geodata ]; then
    echo "v2ray-geodata OK"
else
    echo "WARNING: v2ray-geodata 不存在"
fi

echo "SmartDNS:"
if [ -d package/small/smartdns ]; then
    echo "SmartDNS OK"
else
    echo "WARNING: SmartDNS 不存在"
fi

echo "LuCI SmartDNS:"
if [ -d package/small/luci-app-smartdns ]; then
    echo "luci-app-smartdns OK"
else
    echo "WARNING: luci-app-smartdns 不存在"
fi

echo "MosDNS:"
if [ -d package/small/mosdns ]; then
    echo "MosDNS OK"
else
    echo "WARNING: MosDNS 不存在"
fi

echo "WiFi Startup Script:"
if [ -x files/etc/uci-defaults/zz-enable-wifi ]; then
    echo "zz-enable-wifi OK"
else
    echo "WARNING: zz-enable-wifi 不存在"
fi

echo "DIY2 OK"
