#!/bin/bash
#
# DIY1 - H68K + OpenWrt
# 第三方 Feed + conntrack
#

# 第三方 Feed
sed -i '1i src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' feeds.conf.default
sed -i '2i src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' feeds.conf.default
# sed -i '3i src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' feeds.conf.default
sed -i '4i src-git openclash https://github.com/vernesong/OpenClash.git;master' feeds.conf.default
sed -i '5i src-git homeproxy https://github.com/immortalwrt/homeproxy.git;master' feeds.conf.default
sed -i '6i src-git lucky https://github.com/gdy666/luci-app-lucky.git;main' feeds.conf.default
#sed -i '7i src-git timecontrol https://github.com/sirpdboy/luci-app-timecontrol.git;main' feeds.conf.default
sed -i '8i src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' feeds.conf.default
sed -i '9i src-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git;main' feeds.conf.default
sed -i '10i src-git daed https://github.com/QiuSimons/luci-app-daed.git;master' feeds.conf.default
#sed -i '11i src-git aurora https://github.com/eamonxg/luci-theme-aurora.git;master' feeds.conf.default
#sed -i '12i src-git helloworld https://github.com/fw876/helloworld.git;master' feeds.conf.default

# H68K / LinkEase / jjm2473
sed -i '13i src-git h68k_oled https://github.com/jjm2473/luci-app-oled.git;master' feeds.conf.default
sed -i '14i src-git lcdsimple https://github.com/jjm2473/lcdsimple.git;main' feeds.conf.default
sed -i '15i src-git third_party https://github.com/linkease/istore-packages.git;main' feeds.conf.default
sed -i '16i src-git diskman https://github.com/jjm2473/luci-app-diskman.git;dev' feeds.conf.default
sed -i '17i src-git oaf https://github.com/jjm2473/OpenAppFilter.git;dev7' feeds.conf.default
sed -i '18i src-git linkease_nas https://github.com/linkease/nas-packages.git;master' feeds.conf.default
sed -i '19i src-git linkease_nas_luci https://github.com/linkease/nas-packages-luci.git;main' feeds.conf.default
sed -i '20i src-git jjm2473_apps https://github.com/jjm2473/openwrt-apps.git;main' feeds.conf.default

# 其他 Feed
# sed -i '21i src-git vikingyfy https://github.com/VIKINGYFY/packages.git;main' feeds.conf.default
# sed -i '22i src-git modem https://github.com/FUjr/modem_feeds.git;main' feeds.conf.default

# Kenzok8
# sed -i '23i src-git kenzo https://github.com/kenzok8/openwrt-packages' feeds.conf.default
# sed -i '24i src-git small https://github.com/kenzok8/small' feeds.conf.default
# sed -i '25i src-git smpackage https://github.com/kenzok8/small-package' feeds.conf.default

# Kiddin9
# sed -i '26i src-git op https://github.com/kiddin9/op-packages' feeds.conf.default

# conntrack 最大连接数
sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' package/base-files/files/etc/sysctl.conf
echo 'net.netfilter.nf_conntrack_max=655550' >> package/base-files/files/etc/sysctl.conf

echo "DIY1 OK"
