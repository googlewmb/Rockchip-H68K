#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 插件优先级：
#
# 1. package/myapp
#    独立第三方插件源码
#
# 2. 第三方插件集合源
#    nas
#    nas_luci
#    jjm2473_apps
#    kenzo
#    small
#
# 3. 官方 / iStoreOS 自带 feeds
#    packages
#    luci
#    routing
#    telephony
#    store
#    third
#
# 规则：
#
# package/myapp
#     > 第三方插件集合源
#     > 官方 feeds
#
# 重复时保留优先级高的来源。
#


echo "========================================"
echo "DIY2 - H68K + iStoreOS 24.10"
echo "插件优先级清理"
echo "========================================"


# =========================================================
# H68K DTS
# =========================================================


# =========================================================
# Feed 分类
# =========================================================

# 官方 / iStoreOS 自带 feeds
OFFICIAL_FEEDS="
packages
luci
routing
telephony
store
third
"

# DIY1 添加的第三方插件集合源
THIRD_PARTY_FEEDS="
nas
nas_luci
jjm2473_apps
kenzo
small
"


# =========================================================
# 获取 package/myapp 中的 Package 名称
#
# package/myapp 是最高优先级。
# =========================================================

echo ""
echo "扫描 package/myapp 第三方插件"

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
echo "最高优先级：package/myapp"

if [ -n "$MYAPP_PACKAGES" ]; then

    for pkg in $MYAPP_PACKAGES; do
        echo "  ✓ $pkg"
    done

else

    echo "  未检测到第三方 Package"

fi


# =========================================================
# 第一阶段
#
# package/myapp
#       ↓
# 覆盖第三方插件集合源
#
# 如果 package/myapp 和：
#
# nas
# nas_luci
# jjm2473_apps
# kenzo
# small
#
# 存在同名 Package：
#
# 保留 package/myapp
# 删除集合源中的重复 Package
# =========================================================

echo ""
echo "========================================"
echo "第一阶段：清理第三方集合源重复插件"
echo "========================================"


for feed in $THIRD_PARTY_FEEDS; do

    FEED_DIR="feeds/$feed"

    [ -d "$FEED_DIR" ] || continue

    echo ""
    echo "检查第三方集合源: $feed"


    for pkg in $MYAPP_PACKAGES; do

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


        if [ -z "$FOUND" ]; then
            continue
        fi


        echo "  发现重复插件: $feed/$pkg"
        echo "  保留 package/myapp/$pkg"
        echo "  删除第三方集合源重复版本"


        find "$FEED_DIR" \
            -type d \
            -name "$pkg" \
            -print \
            -exec rm -rf {} + \
            2>/dev/null || true


        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            echo "  删除安装入口:"
            echo "    package/feeds/$feed/$pkg"

            rm -rf \
                "package/feeds/$feed/$pkg"

        fi

    done

done


echo ""
echo "第三方集合源重复插件清理完成"


# =========================================================
# 第二阶段
#
# 第三方插件来源优先于官方 feeds。
#
# 这里建立：
#
# THIRD_PARTY_PACKAGES
#
# 包含：
#
# package/myapp
# +
# 第三方插件集合源
#
# 然后：
#
# 官方 feeds 中只要出现同名 Package，
# 就删除官方版本。
# =========================================================

echo ""
echo "========================================"
echo "第二阶段：清理官方重复插件"
echo "========================================"


THIRD_PARTY_PACKAGES="$MYAPP_PACKAGES"


# ---------------------------------------------------------
# 从第三方集合源中获取 Package 名称
#
# 注意：
# 此时 package/myapp 已经拥有最高优先级，
# 所以刚才重复的集合源包已经被删除。
# ---------------------------------------------------------

for feed in $THIRD_PARTY_FEEDS; do

    FEED_DIR="feeds/$feed"

    [ -d "$FEED_DIR" ] || continue

    while IFS= read -r makefile; do

        while IFS= read -r pkg; do

            [ -z "$pkg" ] && continue

            case " $THIRD_PARTY_PACKAGES " in

                *" $pkg "*)
                    ;;

                *)
                    THIRD_PARTY_PACKAGES="$THIRD_PARTY_PACKAGES $pkg"
                    ;;

            esac

        done < <(
            sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([^/[:space:]]+).*$/\1/p' \
            "$makefile"
        )

    done < <(
        find "$FEED_DIR" \
            -type f \
            -name Makefile \
            2>/dev/null
    )

done


echo ""
echo "第三方有效 Package："

if [ -n "$THIRD_PARTY_PACKAGES" ]; then

    for pkg in $THIRD_PARTY_PACKAGES; do
        echo "  ✓ $pkg"
    done

else

    echo "  未检测到"

fi


# =========================================================
# 删除官方 feeds 中与第三方重复的 Package
#
# 注意：
#
# 只处理：
#
# packages
# luci
# routing
# telephony
# store
# third
#
# 不处理：
#
# nas
# nas_luci
# jjm2473_apps
# kenzo
# small
# =========================================================

for feed in $OFFICIAL_FEEDS; do

    FEED_DIR="feeds/$feed"

    [ -d "$FEED_DIR" ] || continue

    echo ""
    echo "检查官方 feed: $feed"


    for pkg in $THIRD_PARTY_PACKAGES; do

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


        # 官方没有
        #
        # 第三方独有插件，什么都不做。
        if [ -z "$FOUND" ]; then
            continue
        fi


        # -------------------------------------------------
        # 官方存在同名插件
        #
        # 第三方优先。
        # 删除官方版本。
        # -------------------------------------------------

        echo "  发现官方重复插件: $feed/$pkg"
        echo "  第三方版本优先，删除官方版本"


        find "$FEED_DIR" \
            -type d \
            -name "$pkg" \
            -print \
            -exec rm -rf {} + \
            2>/dev/null || true


        # 删除官方 feed 的安装入口

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
# 显示第三方集合源
#
# 只显示，不删除 feed 本身。
# =========================================================

echo ""
echo "========================================"
echo "第三方插件集合源"
echo "========================================"

for feed in $THIRD_PARTY_FEEDS; do

    if [ -d "feeds/$feed" ]; then

        echo "  ✓ 保留: feeds/$feed"

    else

        echo "  - 不存在: feeds/$feed"

    fi

done


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
echo ""
echo "插件优先级："
echo "  1. package/myapp"
echo "  2. nas"
echo "  3. nas_luci"
echo "  4. jjm2473_apps"
echo "  5. kenzo"
echo "  6. small"
echo "  7. 官方 / iStoreOS feeds"
echo ""
echo "第三方重复插件已按优先级处理"
echo "官方重复插件已清理"
echo "========================================"
