#!/bin/bash
#
# DIY1
# H68K + OpenWrt
# 添加第三方 Feed + 系统参数
#
# 执行顺序：
# DIY1
# ↓
# ./scripts/feeds update -a
# ↓
# ./scripts/feeds install -a
# ↓
# 加载 .config
# ↓
# DIY2
# ↓
# make defconfig
#

# PassWall
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >> feeds.conf.default
echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' >> feeds.conf.default

# PassWall2
# echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' >> feeds.conf.default

# OpenClash
echo 'src-git openclash https://github.com/vernesong/OpenClash.git;master' >> feeds.conf.default

# HomeProxy
echo 'src-git homeproxy https://github.com/immortalwrt/homeproxy.git;master' >> feeds.conf.default

# Lucky
echo 'src-git lucky https://github.com/gdy666/luci-app-lucky.git;main' >> feeds.conf.default

# TimeControl
echo 'src-git timecontrol https://github.com/sirpdboy/luci-app-timecontrol.git;main' >> feeds.conf.default

# NetSpeedTest
echo 'src-git netspeedtest https://github.com/sirpdboy/luci-app-netspeedtest.git;master' >> feeds.conf.default

# Nikki
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# Momo
echo 'src-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git;main' >> feeds.conf.default

# Daed
echo 'src-git daed https://github.com/QiuSimons/luci-app-daed.git;master' >> feeds.conf.default

# Aurora
echo 'src-git aurora https://github.com/eamonxg/luci-theme-aurora.git;master' >> feeds.conf.default

# VIKINGYFY
# echo 'src-git vikingyfy https://github.com/VIKINGYFY/packages.git;main' >> feeds.conf.default

# SSRP / HelloWorld
echo 'src-git helloworld https://github.com/fw876/helloworld.git;master' >> feeds.conf.default

# Modem
echo 'src-git modem https://github.com/FUjr/modem_feeds.git;main' >> feeds.conf.default

# Kenzok8
# echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default
# echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default
# echo 'src-git smpackage https://github.com/kenzok8/small-package' >> feeds.conf.default

# Kiddin9
# echo 'src-git op https://github.com/kiddin9/op-packages' >> feeds.conf.default

# 设置 conntrack 最大连接数为 655550
sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' >> \
package/base-files/files/etc/sysctl.conf

echo "DIY1: third-party feeds and system settings added successfully!"
