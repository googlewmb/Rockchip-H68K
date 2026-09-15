#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 插件优先级：
#
# package/myapp
#       >
# 第三方插件集合源
#       >
# 官方 / iStoreOS feeds
#
# 只处理：
# 1. .config 中实际启用的插件
# 2. package/myapp 中实际存在的插件
#
# 不扫描整个第三方 feed 的全部 Package，
# 避免无关插件的依赖问题污染 defconfig。
#


echo ""
echo "========================================"
echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件优先"
echo "========================================"


# =========================================================
# Feed 分类
# =========================================================

OFFICIAL_FEEDS="
packages
luci
routing
telephony
store
third
"

THIRD_PARTY_FEEDS="
nas
nas_luci
jjm2473_apps
kenzo
small
"


# =========================================================
# H68K DTS
# =========================================================

echo ""
echo "应用 H68K DTS"

mkdir -p target/linux/rockchip/dts/rk3568
mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

DTS_SRC="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

if [ -f "$DTS_SRC" ]; then

    cp -f "$DTS_SRC" \
    target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts

    cp -f "$DTS_SRC" \
    target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts \
    2>/dev/null || true

    cp -f "$DTS_SRC" \
    target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts \
    2>/dev/null || true

else

    echo "WARNING: H68K DTS 文件不存在："
    echo "$DTS_SRC"

fi


# =========================================================
# 获取 package/myapp 中真实 Package 名称
#
# 忽略：
# $(PKG_NAME)
# ${PKG_NAME}
# 变量形式的 Package 名称
# =========================================================

echo ""
echo "扫描 package/myapp 第三方插件"

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r makefile; do

        while IFS= read -r pkg; do

            [ -z "$pkg" ] && continue

            # 忽略变量形式
            case "$pkg" in
                '$('*|'\${'*)
                    continue
                    ;;
            esac

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
        echo "  ✓ $pkg"
    done

else

    echo "  未检测到"

fi


# =========================================================
# 从 .config 获取实际启用的 PACKAGE
#
# 只关注：
#
# CONFIG_PACKAGE_xxx=y
#
# 不把整个 feed 中未启用的包纳入处理。
# =========================================================

CONFIG_PACKAGES=""

if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
        's/^CONFIG_PACKAGE_([^=]+)=y$/\1/p' \
        .config
    )"

fi


echo ""
echo "实际启用的插件："

if [ -n "$CONFIG_PACKAGES" ]; then

    for pkg in $CONFIG_PACKAGES; do
        echo "  ✓ $pkg"
    done

else

    echo "  未检测到 CONFIG_PACKAGE_*"
fi


# =========================================================
# 判断 Package 是否存在于指定 feed
# =========================================================

find_feed_package()
{
    local feed="$1"
    local pkg="$2"

    [ -d "feeds/$feed" ] || return 1

    find "feeds/$feed" \
        -type d \
        -name "$pkg" \
        -print -quit \
        2>/dev/null
}


# =========================================================
# 第一优先级
#
# package/myapp
#
# 如果 package/myapp 中存在某个 Package，
# 则：
#
# 1. 删除第三方 feed 中同名的 package/feeds 安装入口
# 2. 删除官方 feed 中同名的 package/feeds 安装入口
#
# 注意：
#
# 不删除 feeds/ 原始源码。
# =========================================================

echo ""
echo "========================================"
echo "第一阶段：package/myapp 最高优先级"
echo "========================================"


for pkg in $MYAPP_PACKAGES; do

    [ -z "$pkg" ] && continue


    # -----------------------------------------------------
    # 第三方 feeds
    # -----------------------------------------------------

    for feed in $THIRD_PARTY_FEEDS; do

        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            echo "第三方重复：$feed/$pkg"
            echo "  保留：package/myapp"
            echo "  删除：package/feeds/$feed/$pkg"

            rm -rf \
                "package/feeds/$feed/$pkg"

        fi

    done


    # -----------------------------------------------------
    # 官方 feeds
    # -----------------------------------------------------

    for feed in $OFFICIAL_FEEDS; do

        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            echo "官方重复：$feed/$pkg"
            echo "  保留：package/myapp"
            echo "  删除：package/feeds/$feed/$pkg"

            rm -rf \
                "package/feeds/$feed/$pkg"

        fi

    done

done


# =========================================================
# 第二优先级
#
# 实际启用的第三方插件
#       >
# 官方 feeds
#
# 注意：
#
# 这里只处理 .config 中实际启用的 Package。
#
# 不扫描整个 third-party feed。
# =========================================================

echo ""
echo "========================================"
echo "第二阶段：第三方插件优先于官方"
echo "========================================"


for pkg in $CONFIG_PACKAGES; do

    [ -z "$pkg" ] && continue


    # -----------------------------------------------------
    # 如果已经由 package/myapp 提供
    #
    # package/myapp 优先级最高。
    # -----------------------------------------------------

    case " $MYAPP_PACKAGES " in
        *" $pkg "*)

            echo "跳过：$pkg"
            echo "  来源：package/myapp"
            continue

            ;;
    esac


    # -----------------------------------------------------
    # 判断该 Package 是否来自第三方 feed
    # -----------------------------------------------------

    THIRD_PARTY_FOUND=""


    for feed in $THIRD_PARTY_FEEDS; do

        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            THIRD_PARTY_FOUND="$feed"
            break

        fi

    done


    # -----------------------------------------------------
    # 第三方没有
    #
    # 官方正常使用。
    # -----------------------------------------------------

    if [ -z "$THIRD_PARTY_FOUND" ]; then

        continue

    fi


    # -----------------------------------------------------
    # 第三方存在
    #
    # 删除官方同名 Package 的安装入口。
    # -----------------------------------------------------

    echo ""
    echo "第三方插件优先：$pkg"
    echo "  来源：$THIRD_PARTY_FOUND"


    for feed in $OFFICIAL_FEEDS; do

        if [ -e "package/feeds/$feed/$pkg" ] ||
           [ -L "package/feeds/$feed/$pkg" ]; then

            echo "  删除官方重复：package/feeds/$feed/$pkg"

            rm -rf \
                "package/feeds/$feed/$pkg"

        fi

    done

done


# =========================================================
# 特殊递归依赖处理
#
# 某些第三方 feed 中存在：
#
# luci-app-fchomo → luci-app-fchomo
# momo → momo
# luci-app-momo → luci-app-momo
#
# 如果用户没有选择这些包，
# 不让它们参与 Kconfig。
#
# 这里仅删除 package/feeds 安装入口，
# 不删除 feeds 源码。
# =========================================================

echo ""
echo "========================================"
echo "第三阶段：清理已知递归依赖包"
echo "========================================"


BROKEN_RECURSIVE_PACKAGES="
luci-app-fchomo
momo
luci-app-momo
"


for pkg in $BROKEN_RECURSIVE_PACKAGES; do

    if grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null; then

        echo "保留用户主动选择：$pkg"

    else

        for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

            if [ -e "package/feeds/$feed/$pkg" ] ||
               [ -L "package/feeds/$feed/$pkg" ]; then

                echo "删除未启用递归包：package/feeds/$feed/$pkg"

                rm -rf \
                    "package/feeds/$feed/$pkg"

            fi

        done

    fi

done


# =========================================================
# HomeProxy / sing-box
#
# HomeProxy 是 package/myapp 的主插件时，
# 保留 HomeProxy。
#
# 不直接删除 sing-box，
# 因为 HomeProxy 本身需要 sing-box。
#
# 后续由 make defconfig 根据实际依赖决定。
# =========================================================

if grep -q '^CONFIG_PACKAGE_luci-app-homeproxy=y$' .config 2>/dev/null; then

    echo ""
    echo "HomeProxy 已启用"
    echo "保留 luci-app-homeproxy"

fi


# =========================================================
# 清理未启用且存在明显缺失依赖的插件
#
# 这些插件本身不是 DIY1 主插件。
#
# 只删除 package/feeds 安装入口。
# =========================================================

echo ""
echo "========================================"
echo "第四阶段：清理未启用的已知问题包"
echo "========================================"


OPTIONAL_BROKEN_PACKAGES="
dae
daed
honk
luci-app-baidupcs-web
luci-app-radicale3
"


for pkg in $OPTIONAL_BROKEN_PACKAGES; do

    if grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null; then

        echo "用户已启用，保留：$pkg"

    else

        for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

            if [ -e "package/feeds/$feed/$pkg" ] ||
               [ -L "package/feeds/$feed/$pkg" ]; then

                echo "未启用，删除问题包入口：$feed/$pkg"

                rm -rf \
                    "package/feeds/$feed/$pkg"

            fi

        done

    fi

done


# =========================================================
# Golang 27.x
# =========================================================

echo ""
echo "========================================"
echo "安装 Golang 27.x"
echo "========================================"


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
# SmartDNS Rust Makefile
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
# conntrack
# =========================================================

echo ""
echo "设置 conntrack 最大连接数"


sed -i \
'/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
package/base-files/files/etc/sysctl.conf


echo 'net.netfilter.nf_conntrack_max=655550' \
>> package/base-files/files/etc/sysctl.conf


# =========================================================
# Wi-Fi 首次启动自动开启
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
# 最终检查
# =========================================================

echo ""
echo "========================================"
echo "DIY2 OK"
echo ""
echo "插件优先级："
echo ""
echo "  1. package/myapp"
echo "  2. nas"
echo "  3. nas_luci"
echo "  4. jjm2473_apps"
echo "  5. kenzo"
echo "  6. small"
echo "  7. 官方 / iStoreOS feeds"
echo ""
echo "只处理实际启用插件"
echo "未启用的问题插件不会参与 Kconfig"
echo "========================================"
