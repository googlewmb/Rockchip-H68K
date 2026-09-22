#!/bin/bash
set -e
set -o pipefail
#=================================================
# File name: preset-clash-core.sh
# Usage: <preset-clash-core.sh $platform> | example: <preset-clash-core.sh armv8>
# System Required: Linux
# Version: 1.0
# Lisence: MIT
# Author: SuLingGG
# Blog: https://mlapp.cn
# 参考网址：https://github.com/zzcabc/OpenWrt_Action/blob/11208c3d5160128d22d14318772ec48f1918deb9/script/immortalwrt/diy2.sh
# 插件网址：https://github.com/vernesong/OpenClash
# 内核网址：https://github.com/MetaCubeX/mihomo
# 规则网址：https://github.com/MetaCubeX/meta-rules-dat
#=================================================


# 预置openclash内核
mkdir -p files/etc/openclash/core


# openclash 的 Meta内核版本
# CLASH_META_URL="https://github.com/vernesong/OpenClash/raw/core/master/meta/clash-linux-amd64.tar.gz"

# Meta内核版本
CLASH_META_URL=$(curl -fsSL --retry 3 https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha | python3 -c 'import json,sys; assets=json.load(sys.stdin)["assets"]; print(next(a["browser_download_url"] for a in assets if a["name"].startswith("mihomo-linux-arm64-alpha-") and a["name"].endswith(".gz")))')

# 给内核解压
test -n "$CLASH_META_URL"
wget -qO- "$CLASH_META_URL" | gunzip -c > files/etc/openclash/core/clash_meta

# 给内核权限
chmod +x files/etc/openclash/core/clash*


# 下载mihomo core需要的文件？
# GeoIP.dat
GEOIP_URL=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat
# GeoSite.dat
GEOSITE_URL=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
# Country.mmdb
COUNTRY_FULL_URL=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb

wget -qO- $GEOIP_URL > files/etc/openclash/GeoIP.dat
wget -qO- $GEOSITE_URL > files/etc/openclash/GeoSite.dat
wget -qO- $COUNTRY_FULL_URL > files/etc/openclash/Country.mmdb

echo "preset-clash-core-L executed successfully!"
