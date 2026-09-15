#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件优先策略：
#
# 1. package/myapp 中的第三方插件作为主插件，永远保留
# 2. DIY1 添加的第三方插件集合源永远保留：
#      nas
#      nas_luci
#      jjm2473_apps
# 3. 只有官方 / iStoreOS 自带 feeds 中存在同名 Package 时，
#    才删除官方重复版本
# 4. 第三方独有插件不删除
# 5. 官方独有插件不删除
# 6. 不删除任何第三方 feed
#

echo "========================================"
echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件优先"
echo "========================================"


echo "应用 H68K DTS"

mkdir -p target/linux/rockchip/dts/rk3568
mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

DTS_SRC="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

cp -f "$DTS_SRC" \
target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts

cp -f "$DTS_SRC" \
target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts \
2>/dev/null || true

cp -f "$DTS_SRC" \
target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts \
2>/dev/null || true


echo ""
echo "检查第三方插件与官方插件重复情况"


# =========================================================
# 官方 / iStoreOS 自带 feeds
#
# 这里只允许处理这些官方 / 系统自带源。
#
# DIY1 添加的第三方 feeds：
#
#   nas
#   nas_luci
#   jjm2473_apps
#
# 不在这里，因此永远不会被本段清理。
# =========================================================

OFFICIAL_FEEDS="
packages
luci
routing
telephony
store
third
"


# =========================================================
# 自动获取 package/myapp 中的 Package 名称
#
# 例如：
#
# package/myapp/openclash/
# package/myapp/homeproxy/
# package/myapp/smartdns/
#
# 自动读取其中的：
#
# define Package/xxx
#
# =========================================================

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r makefile; do

        while IFS= read -r pkg; do

            [ -z "$pkg" ] && continue

            case " $MYAPP_PACKAGES " in

                *" $pkg "*)
                    ;;

                *)
                    MYAPP_PACKAGES="$MYAPP_PACKAGES $pkg"
                    ;;

            esac

        done < <(
            sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([^/[:space:]]+).*$/\1/p' \
            "$makefile"
        )

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            2>/dev/null
    )

fi


echo ""
echo "DIY1 第三方主插件："

if [ -n "$MYAPP_PACKAGES" ]; then

    for pkg in $MYAPP_PACKAGES; do
        echo "  保留第三方插件: $pkg"
    done

else

    echo "  未检测到 package/myapp 插件"

fi


# =========================================================
# 只清理官方 feeds 中真正存在的重复插件
#
# 逻辑：
#
# package/myapp 有 xxx
#        ↓
# 检查官方 feeds
#        ↓
# 官方有 xxx
#        ↓
# 删除官方 xxx
#
# 官方没有 xxx
#        ↓
# 什么都不做
#
# 第三方 feed 有 xxx
#        ↓
# 不处理
#
# =========================================================

echo ""
echo "开始检查官方 feeds"


for feed in $OFFICIAL_FEEDS; do

    FEED_DIR="feeds/$feed"

    if [ ! -d "$FEED_DIR" ]; then
        continue
    fi

    echo ""
    echo "检查官方 feed: $feed"


    for pkg in $MYAPP_PACKAGES; do

        # -------------------------------------------------
        # 检查官方 feed 是否存在同名 package
        # -------------------------------------------------

        FOUND=""

        while IFS= read -r dir; do

            [ -z "$dir" ] && continue

            FOUND="$dir"
            break

        done < <(
            find "$FEED_DIR" \
                -type d \
                -name "$pkg" \
                2>/dev/null
        )


        # -------------------------------------------------
        # 官方不存在
        #
        # 第三方插件独有：
        # 不做任何处理
        # -------------------------------------------------

        if [ -z "$FOUND" ]; then
            continue
        fi


        # -------------------------------------------------
        # 官方存在同名插件
        #
        # 第三方版本优先
        # 删除官方源码版本
        # -------------------------------------------------

        echo "  发现官方重复插件: $feed/$pkg"
        echo "  第三方版本优先，删除官方版本"


        find "$FEED_DIR" \
            -type d \
            -name "$pkg" \
            -print \
            -exec rm -rf {} + \
            2>/dev/null || true


        # -------------------------------------------------
        # 同时删除 package/feeds 中官方 feed 的入口
        # -------------------------------------------------

        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            echo "  删除官方安装入口:"
            echo "    package/feeds/$feed/$pkg"

            rm -rf \
                "package/feeds/$feed/$pkg"

        fi

    done

done


echo ""
echo "官方重复插件清理完成"


# =========================================================
# 检查第三方 feeds
#
# 只显示，不删除。
# =========================================================

echo ""
echo "检查第三方插件源"


for feed in nas nas_luci jjm2473_apps; do

    if [ -d "feeds/$feed" ]; then

        echo "  保留第三方 feed: feeds/$feed"

    fi

done


echo ""
echo "第三方插件优先处理完成"


# =========================================================
# 安装 Golang 27.x
# =========================================================

echo ""
echo "安装 Golang 27.x"

rm -rf feeds/packages/lang/golang
rm -rf package/feeds/packages/golang

git clone \
--filter=blob:none \
--depth 1 \
--single-branch \
-b 27.x \
https://github.com/sbwml/packages_lang_golang \
feeds/packages/lang/golang

./scripts/feeds install -p packages golang || true


# =========================================================
# 修复 SmartDNS Rust Makefile
# =========================================================

echo ""
echo "修复 SmartDNS Rust Makefile"


if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

    sed -i \
    's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
    package/myapp/smartdns/package/openwrt/Makefile

fi


if [ -f package/myapp/smartdns/Makefile ]; then

    sed -i \
    's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
    package/myapp/smartdns/Makefile

fi


# =========================================================
# 自动添加 LuCI 中文语言包
# =========================================================

echo ""
echo "自动添加 LuCI 中文语言包"


for pkg in $(grep '^CONFIG_PACKAGE_luci-app-.*=y' .config | sed 's/^CONFIG_PACKAGE_//;s/=y//'); do

    trans="luci-i18n-${pkg#luci-app-}"


    grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
    .config 2>/dev/null && continue


    if grep -rq \
        "Package.*${trans}-zh-cn" \
        feeds/luci \
        feeds/*/* \
        package \
        2>/dev/null; then

        echo "添加中文语言包: ${trans}-zh-cn"

        echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

    fi

done


# =========================================================
# 设置 conntrack
# =========================================================

echo ""
echo "设置 conntrack 最大连接数"

sed -i \
'/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
>> package/base-files/files/etc/sysctl.conf


# =========================================================
# 配置 Wi-Fi 首次启动自动开启
# =========================================================

echo ""
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


# =========================================================
# 完成
# =========================================================

echo ""
echo "========================================"
echo "DIY2 OK"
echo "第三方插件优先策略已完成"
echo "========================================"
