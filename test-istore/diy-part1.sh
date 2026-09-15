#!/bin/bash
#
# DIY1 - H68K + iStoreOS 24.10
# 第三方插件源码
#

echo "DIY1 - 下载第三方插件"

mkdir -p package/myapp
cd package/myapp

# PassWall
#git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git passwall-packages
#git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall.git passwall
#git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git passwall2

# OpenClash
git clone -b master --depth 1 https://github.com/vernesong/OpenClash.git openclash

# HomeProxy
git clone -b master --depth 1 https://github.com/immortalwrt/homeproxy.git homeproxy

# Lucky
#git clone -b main --depth 1 https://github.com/gdy666/luci-app-lucky.git lucky

# TimeControl
#git clone -b main --depth 1 https://github.com/sirpdboy/luci-app-timecontrol.git timecontrol

# Nikki / Momo / Daed
#git clone -b main --depth 1 https://github.com/nikkinikki-org/OpenWrt-nikki.git nikki
#git clone -b main --depth 1 https://github.com/nikkinikki-org/OpenWrt-momo.git momo
#git clone -b master --depth 1 https://github.com/QiuSimons/luci-app-daed.git daed

# Aurora / HelloWorld
#git clone -b master --depth 1 https://github.com/eamonxg/luci-theme-aurora.git aurora
#git clone -b master --depth 1 https://github.com/fw876/helloworld.git helloworld

# SmartDNS
git clone -b master --depth 1 https://github.com/pymumu/luci-app-smartdns.git luci-app-smartdns
git clone -b master --depth 1 https://github.com/pymumu/smartdns.git smartdns

# MosDNS / V2Ray GeoData
git clone -b v5 --depth 1 https://github.com/sbwml/luci-app-mosdns.git mosdns
git clone --depth 1 https://github.com/sbwml/v2ray-geodata.git v2ray-geodata

# H68K / jjm2473
#git clone -b master --depth 1 https://github.com/jjm2473/luci-app-oled.git luci-app-oled
#git clone -b main --depth 1 https://github.com/jjm2473/lcdsimple.git lcdsimple
#git clone -b dev --depth 1 https://github.com/jjm2473/luci-app-diskman.git luci-app-diskman
#git clone -b dev7 --depth 1 https://github.com/jjm2473/OpenAppFilter.git OpenAppFilter

# LinkEase
#git clone -b main --depth 1 https://github.com/linkease/istore-packages.git istore-packages
#git clone -b master --depth 1 https://github.com/linkease/nas-packages.git nas-packages
#git clone -b main --depth 1 https://github.com/linkease/nas-packages-luci.git nas-packages-luci
#git clone -b main --depth 1 https://github.com/jjm2473/openwrt-apps.git openwrt-apps

# 其他
#git clone -b main --depth 1 https://github.com/VIKINGYFY/packages.git vikingyfy-packages
#git clone -b main --depth 1 https://github.com/FUjr/modem_feeds.git modem-feeds
#git clone --depth 1 https://github.com/kenzok8/openwrt-packages.git kenzok8-packages
#git clone --depth 1 https://github.com/kenzok8/small.git kenzok8-small
#git clone --depth 1 https://github.com/kenzok8/small-package.git kenzok8-small-package
#git clone --depth 1 https://github.com/kiddin9/op-packages.git kiddin9

cd ../..

echo "已下载插件:"
find package/myapp -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort

echo "DIY1 OK"
