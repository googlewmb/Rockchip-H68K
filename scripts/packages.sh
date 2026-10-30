#!/bin/bash
set -e
set -o pipefail

# 删除feeds中的插件
rm -rf ./feeds/packages/net/{geoview,chinadns-ng,hysteria,mosdns,v2ray-geodata,lucky}
rm -rf ./feeds/packages/net/{shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev}
rm -rf ./feeds/packages/net/{sing-box,v2ray-geodata,v2ray-plugin,xray-core,smartdns}

rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-passwall2,luci-app-openclash,luci-app-homeproxy}
rm -rf ./feeds/luci/applications/{luci-app-lucky,luci-app-smartdns,luci-app-timecontrol,luci-app-mosdns}
rm -rf ./feeds/luci/applications/{luci-app-nikki,luci-app-momo,luci-app-daed}

# 克隆依赖插件
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pwpage
# git clone --depth 1 https://github.com/sbwml/packages_lang_golang -b 27.x feeds/packages/lang/golang


# 克隆的源码放在small文件夹
mkdir package/small
pushd package/small

# luci-theme-aurora
git clone -b master --depth 1 https://github.com/eamonxg/luci-theme-aurora.git

# luci-app-nft-timecontrol
git clone -b main --depth 1 https://github.com/sirpdboy/luci-app-timecontrol.git

# adguardhome
# git clone -b 2024.09.05 --depth 1 https://github.com/XiaoBinin/luci-app-adguardhome.git

# homeproxy
git clone -b master --depth 1 https://github.com/immortalwrt/homeproxy.git

# lucky
git clone -b main --depth 1 https://github.com/gdy666/luci-app-lucky.git

# smartdns
git clone -b master --depth 1 https://github.com/pymumu/luci-app-smartdns.git
git clone -b master --depth 1 https://github.com/pymumu/smartdns.git
sed -i 's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' smartdns/package/openwrt/Makefile
sed -n '33p' smartdns/package/openwrt/Makefile

# ssrp
# git clone -b master --depth 1 https://github.com/fw876/helloworld.git

# VIKINGYFY/packages
#git clone -b main --depth 1 https://github.com/VIKINGYFY/packages.git

# passwall
git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall.git

# passwall2
git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git

# mosdns
git clone -b v5 --depth 1 https://github.com/sbwml/luci-app-mosdns.git

# luci-app-netspeedtest
# This optional repository currently returns HTTP 451. The LEDE profile does
# not select it; do not make an unused download a prerequisite for the build.
if grep -Eq '^CONFIG_PACKAGE_(luci-app-netspeedtest|luci-i18n-netspeedtest-[^=]+)=[ym]$|^CONFIG_ALL=y$' ../../.config; then
    git clone -b master --depth 1 https://github.com/sirpdboy/luci-app-netspeedtest.git
else
    echo 'netspeedtest is not selected; skip its optional source download'
fi

# openclash
git clone -b master --depth 1 https://github.com/vernesong/OpenClash.git

# OpenWrt-nikki
#git clone -b main --depth 1 https://github.com/nikkinikki-org/OpenWrt-nikki.git

# OpenWrt-momo
#git clone -b main --depth 1 https://github.com/nikkinikki-org/OpenWrt-momo.git

# daed
#git clone -b master --depth 1 https://github.com/QiuSimons/luci-app-daed.git



###############################################################################
# dae / daed / luci-app-daede
# 来源：https://github.com/kenzok8/openwrt-daede
###############################################################################

echo "下载 kenzok8/openwrt-daede"

DAEDE_TMP=".openwrt-daede-src"

git clone -b main --depth 1 \
https://github.com/kenzok8/openwrt-daede.git \
"$DAEDE_TMP"

# 检查所需软件包目录
for pkg in dae daed luci-app-daede; do
    if [ ! -d "$DAEDE_TMP/$pkg" ]; then
        echo "ERROR: openwrt-daede 缺少软件包目录: $pkg"
        exit 1
    fi

    if [ -e "$pkg" ] || [ -L "$pkg" ]; then
        echo "ERROR: 目标目录已存在，拒绝覆盖: package/myapp/$pkg"
        exit 1
    fi
done

# 将三个软件包放到 package/myapp 一级目录
mv "$DAEDE_TMP/dae" ./dae
mv "$DAEDE_TMP/daed" ./daed
mv "$DAEDE_TMP/luci-app-daede" ./luci-app-daede

# 删除临时仓库
rm -rf "$DAEDE_TMP"

echo "已添加 dae、daed、luci-app-daede"



#modem
# git clone -b main --depth 1 https://github.com/FUjr/modem_feeds.git

# ... 原有代码保持不变 ...

popd

# ========== 自适应修复开始 ==========
fix_outdated_singbox_patches() {
    local pkg_dirs=(
        "package/small/packages/sing-box"
        "package/small/sing-box"
        "feeds/packages/net/sing-box"
    )

    for dir in "${pkg_dirs[@]}"; do
        [ -d "$dir/patches" ] || continue
        echo "Checking sing-box patches in $dir/patches ..."

        for bad in "100-fix-dns-tcp-close.patch" "fix-dns-tcp-close.patch"; do
            if [ -f "$dir/patches/$bad" ]; then
                echo "→ Removing outdated patch: $dir/patches/$bad"
                rm -f "$dir/patches/$bad"
            fi
        done
    done
}

fix_outdated_singbox_patches
# ========== 自适应修复结束 ==========

echo "packages executed successfully!"
