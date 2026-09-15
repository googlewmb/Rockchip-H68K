#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#


# H68K 官方 DTS 修复少 1G 网口

echo "Applying official H68K DTS fix from test-istore/diy..."

mkdir -p target/linux/rockchip/dts/rk3568/
mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/

DTS_SRC="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

cp -f "$DTS_SRC" \
target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts

cp -f "$DTS_SRC" \
target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts \
2>/dev/null || true

cp -f "$DTS_SRC" \
target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts \
2>/dev/null || true

echo "H68K DTS applied successfully!"


# 默认 IP

#sed -i 's/192.168.1.1/192.168.50.5/g' \
#package/base-files/files/bin/config_generate


# 删除与 package/myapp 重复的官方网络组件

echo "删除与第三方插件重复的官方网络组件"

# SmartDNS
rm -rf ./feeds/packages/net/smartdns
rm -rf ./package/feeds/packages/smartdns
rm -rf ./feeds/luci/applications/luci-app-smartdns
rm -rf ./package/feeds/luci/luci-app-smartdns

# MosDNS
rm -rf ./feeds/packages/net/mosdns
rm -rf ./package/feeds/packages/mosdns
rm -rf ./feeds/luci/applications/luci-app-mosdns
rm -rf ./package/feeds/luci/luci-app-mosdns

# V2Ray GeoData
rm -rf ./feeds/packages/net/v2ray-geodata
rm -rf ./package/feeds/packages/v2ray-geodata

# OpenClash
rm -rf ./feeds/luci/applications/luci-app-openclash
rm -rf ./package/feeds/luci/luci-app-openclash

# HomeProxy
rm -rf ./feeds/luci/applications/luci-app-homeproxy
rm -rf ./package/feeds/luci/luci-app-homeproxy


# 以下为以后可能启用的第三方插件冲突删除

# PassWall
#rm -rf ./feeds/packages/net/{sing-box,xray-core,v2ray-geodata}
#rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-passwall2}
#rm -rf ./package/feeds/packages/{sing-box,xray-core,v2ray-geodata}
#rm -rf ./package/feeds/luci/{luci-app-passwall,luci-app-passwall2}

# Lucky
#rm -rf ./feeds/packages/net/lucky
#rm -rf ./feeds/luci/applications/luci-app-lucky
#rm -rf ./package/feeds/packages/lucky
#rm -rf ./package/feeds/luci/luci-app-lucky

# TimeControl
#rm -rf ./feeds/luci/applications/luci-app-timecontrol
#rm -rf ./package/feeds/luci/luci-app-timecontrol

# Nikki
#rm -rf ./feeds/luci/applications/luci-app-nikki
#rm -rf ./package/feeds/luci/luci-app-nikki

# Momo
#rm -rf ./feeds/luci/applications/luci-app-momo
#rm -rf ./package/feeds/luci/luci-app-momo

# Daed
#rm -rf ./feeds/luci/applications/luci-app-daed
#rm -rf ./package/feeds/luci/luci-app-daed


echo "官方重复插件删除完成"


# Golang 27.x

echo "安装 Golang 27.x"

rm -rf feeds/packages/lang/golang
rm -rf package/feeds/packages/golang

git clone \
--filter=blob:none \
--depth 1 \
--single-branch \
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
readlink -f package/feeds/packages/golang \
2>/dev/null || true

if [ -d package/feeds/packages/golang ]; then
    echo "Golang feed link OK"
else
    echo "WARNING: package/feeds/packages/golang 不存在"
fi


# 修复 SmartDNS Rust Makefile

echo "修复 SmartDNS Rust Makefile"

if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

    sed -i \
    's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
    package/myapp/smartdns/package/openwrt/Makefile

    echo "SmartDNS Makefile 修复完成"

else

    echo "WARNING: SmartDNS Makefile 不存在"

fi


# 自动添加 LuCI 中文语言包

echo "自动添加 LuCI 中文语言包"

for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config \
    | sed 's/^CONFIG_PACKAGE_//;s/=y//'); do

    trans="luci-i18n-${pkg#luci-app-}"

    grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
    .config 2>/dev/null && continue

    if grep -rq "Package.*${trans}-zh-cn" \
        feeds/luci feeds/*/* package 2>/dev/null; then

        echo "添加中文语言包: ${trans}-zh-cn"

        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

    fi

done


# conntrack 最大连接数

echo "设置 conntrack 最大连接数"

sed -i \
'/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
>> package/base-files/files/etc/sysctl.conf


# Wi-Fi 首次启动自动开启

echo "配置 Wi-Fi 首次启动自动开启"

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
