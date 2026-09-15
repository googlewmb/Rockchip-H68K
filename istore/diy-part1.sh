#!/bin/bash
#
# DIY1
# H68K + OpenWrt 24.10
#

# 设置 conntrack 最大连接数为 655550
sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' package/base-files/files/etc/sysctl.conf
echo 'net.netfilter.nf_conntrack_max=655550' >> package/base-files/files/etc/sysctl.conf

# 添加软件源
sed -i '1i src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
sed -i '2i src-git small https://github.com/kenzok8/small' feeds.conf.default
# sed -i '3i src-git smpackage https://github.com/kenzok8/small-package' feeds.conf.default
# sed -i '4i src-git op https://github.com/kiddin9/op-packages' feeds.conf.default

# 删除 feeds 中的官方冲突包
# rm -rf ./feeds/packages/net/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata,lucky}
# rm -rf ./feeds/packages/net/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
# rm -rf ./feeds/packages/net/{sing-box,v2ray-geodata,v2ray-plugin,xray-core}
# rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-passwall2,luci-app-openclash,luci-app-homeproxy}
# rm -rf ./feeds/luci/applications/{luci-app-lucky,luci-app-timecontrol,luci-app-mosdns}
# rm -rf ./feeds/luci/applications/{luci-app-nikki,luci-app-momo,luci-app-daed}

# =========================================================
# SmartDNS —— 全部注释
# =========================================================

# rm -rf package/custom/smartdns
# rm -rf package/custom/luci-app-smartdns

# mkdir -p package/custom

# SmartDNS 主程序
# git clone --filter=blob:none --depth 1 --single-branch \
# https://github.com/pymumu/openwrt-smartdns \
# -b master \
# package/custom/smartdns

# SmartDNS LuCI
# git clone --filter=blob:none --depth 1 --single-branch \
# https://github.com/pymumu/luci-app-smartdns \
# -b master \
# package/custom/luci-app-smartdns

# 获取最新 SmartDNS Commit
# SMARTDNS_JSON=$(curl -sL https://api.github.com/repos/pymumu/smartdns/commits)
# SMARTDNS_VER=$(echo "${SMARTDNS_JSON}" | jq -r '.[0].commit.committer.date' | awk -F "T" '{print $1}')
# SMARTDNS_SHA=$(echo "${SMARTDNS_JSON}" | jq -r '.[0].sha')

# 下载 SmartDNS 源码并计算 SHA256
# curl -sL \
# -o "/tmp/smartdns-${SMARTDNS_SHA}.tar.gz" \
# "https://codeload.github.com/pymumu/smartdns/tar.gz/${SMARTDNS_SHA}"

# SMARTDNS_PKG_SHA=$(sha256sum "/tmp/smartdns-${SMARTDNS_SHA}.tar.gz" | awk '{print $1}')

# rm -f "/tmp/smartdns-${SMARTDNS_SHA}.tar.gz"

# 修改 SmartDNS 主程序 Makefile
# sed -i \
# 's/PKG_VERSION:=.*/PKG_VERSION:='"${SMARTDNS_SHA}"'/g' \
# package/custom/smartdns/Makefile

# sed -i \
# 's/PKG_SOURCE_PROTO:=git/PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz/g' \
# package/custom/smartdns/Makefile

# sed -i \
# 's#PKG_SOURCE_URL:=.*#PKG_SOURCE_URL:=https:\/\/codeload.github.com\/pymumu\/smartdns\/tar.gz\/$(PKG_VERSION)?#g' \
# package/custom/smartdns/Makefile

# sed -i \
# '/PKG_SOURCE_VERSION:=.*/d' \
# package/custom/smartdns/Makefile

# sed -i \
# 's/PKG_MIRROR_HASH:=.*/PKG_HASH:='"${SMARTDNS_PKG_SHA}"'/g' \
# package/custom/smartdns/Makefile

# SmartDNS 使用 feeds/packages/lang 下的依赖
# sed -i \
# 's#../../lang#$(TOPDIR)/feeds/packages/lang#g' \
# package/custom/smartdns/Makefile

# 修改 LuCI SmartDNS 版本
# sed -i \
# 's/PKG_VERSION:=.*/PKG_VERSION:='"${SMARTDNS_VER}"'/g' \
# package/custom/luci-app-smartdns/Makefile

# 使用官方 LuCI 构建框架
# sed -i \
# 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' \
# package/custom/luci-app-smartdns/Makefile


# =========================================================
# 第三方插件 —— 全部注释
# =========================================================

# mkdir -p package/small
# cd package/small

# MosDNS
# git clone -b v5 --depth 1 \
# https://github.com/sbwml/luci-app-mosdns.git

# OpenClash
# git clone -b master --depth 1 \
# https://github.com/vernesong/OpenClash.git

# HomeProxy
# git clone -b master --depth 1 \
# https://github.com/immortalwrt/homeproxy.git

# Lucky
# git clone -b main --depth 1 \
# https://github.com/gdy666/luci-app-lucky.git

# TimeControl
# git clone -b main --depth 1 \
# https://github.com/sirpdboy/luci-app-timecontrol.git

# NetSpeedTest
# git clone --depth 1 \
# https://github.com/sirpdboy/NetSpeedTest.git \
# luci-app-netspeedtest

# Nikki
# git clone -b main --depth 1 \
# https://github.com/nikkinikki-org/OpenWrt-nikki.git

# Momo
# git clone -b main --depth 1 \
# https://github.com/nikkinikki-org/OpenWrt-momo.git

# Daed
# git clone -b master --depth 1 \
# https://github.com/QiuSimons/luci-app-daed.git

# Aurora Theme
# git clone -b master --depth 1 \
# https://github.com/eamonxg/luci-theme-aurora.git

# VIKINGYFY Packages
# git clone -b main --depth 1 \
# https://github.com/VIKINGYFY/packages.git

# AdGuardHome
# git clone -b 2024.09.05 --depth 1 \
# https://github.com/XiaoBinin/luci-app-adguardhome.git \
# luci-app-adguardhome

# SSRP
# git clone -b master --depth 1 \
# https://github.com/fw876/helloworld.git

# Modem
# git clone -b main --depth 1 \
# https://github.com/FUjr/modem_feeds.git

# cd ../..


# =========================================================
# PassWall 软件源 —— 注释
# =========================================================

# sed -i '1i src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' feeds.conf.default
# sed -i '2i src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' feeds.conf.default


echo "DIY1 OK"
