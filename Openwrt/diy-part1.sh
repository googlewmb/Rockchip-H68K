#!/bin/bash
#
# DIY1
# H68K + ImmortalWrt/OpenWrt
#

# 设置 conntrack 最大连接数为 655550
sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' package/base-files/files/etc/sysctl.conf
echo 'net.netfilter.nf_conntrack_max=655550' >> package/base-files/files/etc/sysctl.conf

# 添加软件源
#sed -i '1i src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
#sed -i '2i src-git small https://github.com/kenzok8/small' feeds.conf.default
#sed -i '3i src-git smpackage https://github.com/kenzok8/small-package' feeds.conf.default
#sed -i '4i src-git op https://github.com/kiddin9/op-packages' feeds.conf.default

# 删除 feeds 中的官方冲突包
rm -rf ./feeds/packages/net/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata,lucky}
rm -rf ./feeds/packages/net/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./feeds/packages/net/{sing-box,v2ray-geodata,v2ray-plugin,xray-core}

rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-passwall2,luci-app-openclash,luci-app-homeproxy}
rm -rf ./feeds/luci/applications/{luci-app-lucky,luci-app-timecontrol,luci-app-mosdns}
rm -rf ./feeds/luci/applications/{luci-app-nikki,luci-app-momo,luci-app-daed}

# Golang
rm -rf feeds/packages/lang/golang

git clone --depth 1 -b 1.26 \
https://github.com/kenzok8/golang \
feeds/packages/lang/golang

# PassWall 依赖
rm -rf package/passwall-packages

git clone --depth 1 \
https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
package/passwall-packages

# 第三方软件源
mkdir -p package/small
cd package/small

# PassWall
git clone -b main --depth 1 \
https://github.com/Openwrt-Passwall/openwrt-passwall.git

# PassWall2
git clone -b main --depth 1 \
https://github.com/Openwrt-Passwall/openwrt-passwall2.git

# SmartDNS LuCI
git clone -b master --depth 1 \
https://github.com/pymumu/luci-app-smartdns.git

# MosDNS
git clone -b v5 --depth 1 \
https://github.com/sbwml/luci-app-mosdns.git

# OpenClash
git clone -b master --depth 1 \
https://github.com/vernesong/OpenClash.git

# HomeProxy
git clone -b master --depth 1 \
https://github.com/immortalwrt/homeproxy.git

# Lucky
git clone -b main --depth 1 \
https://github.com/gdy666/luci-app-lucky.git

# TimeControl
git clone -b main --depth 1 \
https://github.com/sirpdboy/luci-app-timecontrol.git

# NetSpeedTest
git clone -b master --depth 1 \
https://github.com/sirpdboy/luci-app-netspeedtest.git

# Nikki
git clone -b main --depth 1 \
https://github.com/nikkinikki-org/OpenWrt-nikki.git

# Momo
git clone -b main --depth 1 \
https://github.com/nikkinikki-org/OpenWrt-momo.git

# Daed
git clone -b master --depth 1 \
https://github.com/QiuSimons/luci-app-daed.git

# Aurora Theme
git clone -b master --depth 1 \
https://github.com/eamonxg/luci-theme-aurora.git

# VIKINGYFY Packages
git clone -b main --depth 1 \
https://github.com/VIKINGYFY/packages.git

# AdGuardHome
# git clone -b 2024.09.05 --depth 1 \
# https://github.com/XiaoBinin/luci-app-adguardhome.git

# SSRP
# git clone -b master --depth 1 \
# https://github.com/fw876/helloworld.git

# Modem
# git clone -b main --depth 1 \
# https://github.com/FUjr/modem_feeds.git

cd ../..

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 自动添加 LuCI 中文语言包
for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config | sed 's/^CONFIG_PACKAGE_//;s/=y//'); do
    trans="luci-i18n-${pkg#luci-app-}"

    if grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" .config 2>/dev/null; then
        continue
    fi

    if grep -rq "Package.*${trans}-zh-cn" feeds/luci feeds/*/* 2>/dev/null; then
        echo "自动添加中文语言包: ${trans}-zh-cn"
        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config
    fi
done

# 修正配置
make defconfig
