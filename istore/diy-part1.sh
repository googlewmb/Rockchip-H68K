#!/bin/bash
#
# DIY1
# H68K + ImmortalWrt/OpenWrt
#

# 设置 conntrack 最大连接数为 655550
sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' package/base-files/files/etc/sysctl.conf
echo 'net.netfilter.nf_conntrack_max=655550' >> package/base-files/files/etc/sysctl.conf








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
