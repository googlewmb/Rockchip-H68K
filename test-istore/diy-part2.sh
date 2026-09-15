#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#

echo "应用 H68K DTS"

mkdir -p target/linux/rockchip/dts/rk3568
mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

DTS_SRC="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

cp -f "$DTS_SRC" target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts
cp -f "$DTS_SRC" target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts 2>/dev/null || true
cp -f "$DTS_SRC" target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts 2>/dev/null || true

echo "删除重复插件"

# SmartDNS
rm -rf feeds/packages/net/smartdns
rm -rf package/feeds/packages/smartdns
rm -rf feeds/luci/applications/luci-app-smartdns
rm -rf package/feeds/luci/luci-app-smartdns

# MosDNS
rm -rf feeds/packages/net/mosdns
rm -rf package/feeds/packages/mosdns
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf package/feeds/luci/luci-app-mosdns

# V2Ray GeoData
rm -rf feeds/packages/net/v2ray-geodata
rm -rf package/feeds/packages/v2ray-geodata

# OpenClash
rm -rf feeds/luci/applications/luci-app-openclash
rm -rf package/feeds/luci/luci-app-openclash

# HomeProxy
rm -rf feeds/luci/applications/luci-app-homeproxy
rm -rf package/feeds/luci/luci-app-homeproxy

# OLED
rm -rf feeds/luci/applications/luci-app-oled
rm -rf package/feeds/luci/luci-app-oled

# LCD Simple
rm -rf feeds/luci/applications/lcdsimple
rm -rf package/feeds/luci/lcdsimple

# Diskman
rm -rf feeds/luci/applications/luci-app-diskman
rm -rf package/feeds/luci/luci-app-diskman

# OpenAppFilter
rm -rf feeds/luci/applications/OpenAppFilter
rm -rf package/feeds/luci/OpenAppFilter

# PassWall
#rm -rf feeds/packages/net/{sing-box,xray-core,v2ray-geodata}
#rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-passwall2}
#rm -rf package/feeds/packages/{sing-box,xray-core,v2ray-geodata}
#rm -rf package/feeds/luci/{luci-app-passwall,luci-app-passwall2}

# Lucky
#rm -rf feeds/packages/net/lucky
#rm -rf package/feeds/packages/lucky
#rm -rf feeds/luci/applications/luci-app-lucky
#rm -rf package/feeds/luci/luci-app-lucky

# TimeControl / Nikki / Momo / Daed
#rm -rf feeds/luci/applications/{luci-app-timecontrol,luci-app-nikki,luci-app-momo,luci-app-daed}
#rm -rf package/feeds/luci/{luci-app-timecontrol,luci-app-nikki,luci-app-momo,luci-app-daed}

echo "重复插件删除完成"

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

./scripts/feeds install -p packages golang || true

echo "修复 SmartDNS Rust Makefile"

if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then
    sed -i \
    's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
    package/myapp/smartdns/package/openwrt/Makefile
fi

echo "自动添加 LuCI 中文语言包"

for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config | sed 's/^CONFIG_PACKAGE_//;s/=y//'); do
    trans="luci-i18n-${pkg#luci-app-}"

    grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" .config 2>/dev/null && continue

    if grep -rq "Package.*${trans}-zh-cn" feeds/luci feeds/*/* package 2>/dev/null; then
        echo "添加中文语言包: ${trans}-zh-cn"
        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config
    fi
done

echo "设置 conntrack"

sed -i '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
>> package/base-files/files/etc/sysctl.conf

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
