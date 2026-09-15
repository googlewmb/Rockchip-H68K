#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
#
# 优先级：
#   1. package/myapp 独立第三方源码
#   2. DIY1 添加的第三方集合源
#   3. iStoreOS / OpenWrt 官方 feeds
#
# 重要：
#   - 插件和依赖分开处理
#   - 普通依赖不会因为插件去重而删除
#   - 同名依赖存在多个来源时，第三方优先
#   - 明确要求替换官方依赖的，使用 REMOVE_OFFICIAL_DEPS 白名单
#

set -e

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖优先"


###############################################################################
# 0. 基础检查
###############################################################################

[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"


###############################################################################
# 1. 第三方依赖预处理
#
# 只有明确知道某个第三方插件要求：
#
#   第三方版本 > 官方版本
#
# 才把官方依赖写进这里。
#
# 注意：
#   这里删除的是 package/feeds/<feed>/<pkg> 安装入口，
#   不删除 feeds/<feed> 源码。
#
# 例如以后确认：
#
#   某插件必须使用自己的 xxx
#
# 才写：
#
#   REMOVE_OFFICIAL_DEPS="
#   xxx
#   "
#
###############################################################################

echo
echo "========================================"
echo "第三方依赖预处理"
echo "========================================"

REMOVE_OFFICIAL_DEPS="
"

# 示例：
# REMOVE_OFFICIAL_DEPS="
# libxxx
# libyyy
# "

remove_feed_entry()
{
    local pkg="$1"
    local feed="$2"
    local entry="package/feeds/${feed}/${pkg}"

    if [ -e "$entry" ] || [ -L "$entry" ]; then
        echo "删除 ${feed} 官方/第三方安装入口: ${pkg}"
        rm -f "$entry"
    fi
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    [ -n "$pkg" ] || continue

    for feed in packages luci routing telephony store third; do
        remove_feed_entry "$pkg" "$feed"
    done
done


###############################################################################
# 2. H68K DTS
###############################################################################

echo
echo "========================================"
echo "H68K DTS"
echo "========================================"

DTS_SOURCE="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

if [ -f "$DTS_SOURCE" ]; then

    mkdir -p target/linux/rockchip/dts/rk3568
    mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

    cp -f "$DTS_SOURCE" \
        target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts

    cp -f "$DTS_SOURCE" \
        target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts

    cp -f "$DTS_SOURCE" \
        target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts

    echo "H68K DTS 已复制"

else
    echo "未找到 H68K DTS:"
    echo "$DTS_SOURCE"
fi


###############################################################################
# 3. 读取 package/myapp 中真正的 Package 名称
#
# 以前的问题：
#
#   ✓ $(PKG_NAME)
#
# 这种变量定义不能作为真实 Package 名。
#
# 这里只接受：
#
#   define Package/xxx
#
# 且 xxx 必须是真实的包名。
#
###############################################################################

echo
echo "========================================"
echo "扫描 DIY1 独立第三方插件"
echo "========================================"

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

        case "$pkg" in
            '$('*|*'$)'|*'/'*)
                continue
                ;;
        esac

        MYAPP_PACKAGES="$MYAPP_PACKAGES
$pkg"

        echo "✓ $pkg"

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 |
        xargs -0 -r sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u
    )

else
    echo "package/myapp 不存在"
fi


###############################################################################
# 4. 工具函数
###############################################################################

is_enabled()
{
    local pkg="$1"

    grep -Eq \
        "^CONFIG_PACKAGE_${pkg}=(y|m)$" \
        .config 2>/dev/null
}

package_entry_exists()
{
    local feed="$1"
    local pkg="$2"
    local entry="package/feeds/${feed}/${pkg}"

    [ -e "$entry" ] || [ -L "$entry" ]
}

remove_package_entry()
{
    local feed="$1"
    local pkg="$2"
    local entry="package/feeds/${feed}/${pkg}"

    if [ -e "$entry" ] || [ -L "$entry" ]; then
        echo "删除安装入口: ${feed}/${pkg}"
        rm -f "$entry"
    fi
}

package_source_makefile()
{
    local feed="$1"
    local pkg="$2"
    local entry="package/feeds/${feed}/${pkg}/Makefile"

    if [ -f "$entry" ]; then
        readlink -f "$entry" 2>/dev/null || true
    fi
}


###############################################################################
# 5. 独立第三方插件优先
#
# package/myapp > 所有其他来源
#
# 注意：
#   这里只删除 package/feeds/<feed>/<pkg>
#   不删除 feeds/<feed> 源码目录。
#
###############################################################################

echo
echo "========================================"
echo "独立第三方插件优先"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "检查独立第三方插件: $pkg"

    for feed in packages luci routing telephony store third; do

        if package_entry_exists "$feed" "$pkg"; then
            echo "发现重复来源: ${feed}/${pkg}"
            echo "package/myapp 版本优先"

            remove_package_entry "$feed" "$pkg"
        fi

    done

done


###############################################################################
# 6. 第三方集合源 > 官方 feeds
#
# DIY1 当前集合源：
#
#   nas
#   nas_luci
#   jjm2473_apps
#   kenzo
#   small
#
# 只处理“实际需要”的包：
#
#   - .config 中启用的包
#   - DIY1 独立插件
#
# 不扫描第三方 feed 全部包。
#
###############################################################################

echo
echo "========================================"
echo "第三方集合源优先"
echo "========================================"

THIRD_PARTY_FEEDS="
nas
nas_luci
jjm2473_apps
kenzo
small
"

OFFICIAL_FEEDS="
packages
luci
routing
telephony
store
third
"


###############################################################################
# 7. 收集当前 .config 中实际启用的 Package
###############################################################################

CONFIG_PACKAGES=""

if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

fi


###############################################################################
# 8. 第三方集合源覆盖官方同名包
#
# 只删除官方 package/feeds/<feed>/<pkg>。
#
# 不删除第三方源码。
# 不删除官方 feeds 源码。
###############################################################################

for pkg in $CONFIG_PACKAGES; do

    [ -n "$pkg" ] || continue

    # package/myapp 已经处理过
    case "
$MYAPP_PACKAGES
" in
        *"
$pkg
"*)
            continue
            ;;
    esac

    THIRD_SOURCE=""

    for third_feed in $THIRD_PARTY_FEEDS; do

        if package_entry_exists "$third_feed" "$pkg"; then
            THIRD_SOURCE="$third_feed"
            break
        fi

    done

    if [ -n "$THIRD_SOURCE" ]; then

        echo
        echo "第三方集合源优先: $pkg"
        echo "来源: $THIRD_SOURCE"

        for official_feed in $OFFICIAL_FEEDS; do

            if package_entry_exists "$official_feed" "$pkg"; then
                echo "删除官方重复入口: ${official_feed}/${pkg}"
                remove_package_entry "$official_feed" "$pkg"
            fi

        done

    fi

done


###############################################################################
# 9. HomeProxy 依赖保护
#
# HomeProxy 是 DIY1 单独 clone 的插件，不是集合源插件。
#
# 依赖：
#
#   luci-app-homeproxy
#       ├── sing-box
#       └── sing-box-tiny
#
# 这里绝对不删除：
#
#   sing-box
#   sing-box-tiny
#
# 如果依赖本身同时存在第三方和官方来源：
#
#   第三方 > 官方
#
# 但如果第三方没有，则保留官方。
###############################################################################

echo
echo "========================================"
echo "HomeProxy 依赖保护"
echo "========================================"

if is_enabled "luci-app-homeproxy"; then

    echo "检测到 HomeProxy 已启用"

    for dep in sing-box sing-box-tiny; do

        echo
        echo "检查 HomeProxy 依赖: $dep"

        THIRD_SOURCE=""

        for third_feed in $THIRD_PARTY_FEEDS; do

            if package_entry_exists "$third_feed" "$dep"; then
                THIRD_SOURCE="$third_feed"
                break
            fi

        done

        if [ -n "$THIRD_SOURCE" ]; then

            echo "第三方存在: ${THIRD_SOURCE}/${dep}"
            echo "第三方版本优先"

            for official_feed in $OFFICIAL_FEEDS; do

                if package_entry_exists "$official_feed" "$dep"; then
                    echo "删除官方重复入口: ${official_feed}/${dep}"
                    remove_package_entry "$official_feed" "$dep"
                fi

            done

        else

            echo "没有发现第三方替代版本"
            echo "保留官方依赖: $dep"

        fi

    done

else
    echo "HomeProxy 当前未在 .config 中启用"
fi


###############################################################################
# 10. HomeProxy / sing-box 错误反向依赖修复
#
# 正确关系：
#
#   HomeProxy
#       ↓
#   sing-box-tiny
#       ↓
#   sing-box
#
# 不允许：
#
#   sing-box
#       ↓
#   HomeProxy
#
# 否则会形成：
#
#   luci-app-homeproxy
#       ↓
#   sing-box-tiny
#       ↓
#   sing-box
#       ↓
#   luci-app-homeproxy
#
###############################################################################

echo
echo "========================================"
echo "修复 sing-box → HomeProxy 反向依赖"
echo "========================================"

for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

    MAKEFILE="$(package_source_makefile "$feed" "sing-box")"

    [ -n "$MAKEFILE" ] || continue
    [ -f "$MAKEFILE" ] || continue

    echo "检查: $MAKEFILE"

    # 删除 DEPENDS 中错误的：
    #
    #   +luci-app-homeproxy
    #
    # 但不动 sing-box 自己正常的其他依赖。

    sed -i -E \
        's/[[:space:]]+\+luci-app-homeproxy([[:space:]]|$)/ /g' \
        "$MAKEFILE"

    # 如果源码直接写了 Kconfig select / depends，
    # 只删除指向 HomeProxy 的反向关系。

    sed -i -E \
        '/^[[:space:]]*(select|depends on)[[:space:]]+PACKAGE_luci-app-homeproxy[[:space:]]*$/d' \
        "$MAKEFILE"

done


###############################################################################
# 11. sing-box-tiny 依赖保护
#
# sing-box-tiny -> sing-box 是正常依赖。
#
# 这里不删除：
#
#   +sing-box
#
###############################################################################

echo
echo "检查 sing-box-tiny 正常依赖"

for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

    MAKEFILE="$(package_source_makefile "$feed" "sing-box-tiny")"

    [ -n "$MAKEFILE" ] || continue
    [ -f "$MAKEFILE" ] || continue

    echo "保留 sing-box-tiny: $MAKEFILE"

done


###############################################################################
# 12. 修复明确发现的自递归 Kconfig 包
#
# 当前已发现：
#
#   luci-app-fchomo -> luci-app-fchomo
#   momo            -> momo
#   luci-app-momo   -> luci-app-momo
#
# 处理原则：
#
#   未启用：
#       删除 package/feeds/<feed>/<pkg> 安装入口
#
#   已启用：
#       尝试删除 Makefile 中指向自身的依赖
#
# 不删除真正需要的其他依赖。
###############################################################################

echo
echo "========================================"
echo "处理已知递归依赖"
echo "========================================"

fix_self_dependency()
{
    local pkg="$1"
    local dep="$2"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

        MAKEFILE="$(package_source_makefile "$feed" "$pkg")"

        [ -n "$MAKEFILE" ] || continue
        [ -f "$MAKEFILE" ] || continue

        echo "检查自依赖: ${feed}/${pkg}"

        # Makefile DEPENDS 中：
        #   +pkg
        #
        # 删除自身依赖。

        sed -i -E \
            "s/[[:space:]]+\+${dep}([[:space:]]|$)/ /g" \
            "$MAKEFILE"

        # 处理直接 Kconfig 写法。

        sed -i -E \
            "/^[[:space:]]*(select|depends on)[[:space:]]+PACKAGE_${dep}[[:space:]]*$/d" \
            "$MAKEFILE"

    done
}


if is_enabled "luci-app-fchomo"; then

    echo "luci-app-fchomo 已启用，尝试修复自依赖"
    fix_self_dependency "luci-app-fchomo" "luci-app-fchomo"

else

    echo "luci-app-fchomo 未启用，删除其 Kconfig 安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "luci-app-fchomo"
    done

fi


if is_enabled "momo"; then

    echo "momo 已启用，尝试修复自依赖"
    fix_self_dependency "momo" "momo"

else

    echo "momo 未启用，删除其 Kconfig 安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "momo"
    done

fi


if is_enabled "luci-app-momo"; then

    echo "luci-app-momo 已启用，尝试修复自依赖"
    fix_self_dependency "luci-app-momo" "luci-app-momo"

else

    echo "luci-app-momo 未启用，删除其 Kconfig 安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "luci-app-momo"
    done

fi


###############################################################################
# 13. 清理当前已知的无效依赖包
#
# 这些包之前出现：
#
#   dae       -> vmlinux-btf
#   daed      -> vmlinux-btf
#   honk      -> vmlinux-btf
#   luci-app-baidupcs-web -> baidupcs-web
#   luci-app-radicale3 -> rpcd-mod-rad3-enc
#
# 如果没有在 .config 中启用，则移除它们的安装入口。
#
# 如果用户主动启用，则保留，避免 DIY2 擅自删除用户选择的插件。
###############################################################################

echo
echo "========================================"
echo "清理未启用的已知无效包"
echo "========================================"

INVALID_PACKAGES="
dae
daed
honk
luci-app-baidupcs-web
luci-app-radicale3
"

for pkg in $INVALID_PACKAGES; do

    if is_enabled "$pkg"; then

        echo "已启用，保留: $pkg"
        echo "注意：$pkg 仍可能存在依赖警告"

    else

        echo "未启用，删除入口: $pkg"

        for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
            remove_package_entry "$feed" "$pkg"
        done

    fi

done


###############################################################################
# 14. Golang 27.x
###############################################################################

echo
echo "========================================"
echo "安装 Golang 27.x"
echo "========================================"

if [ -d feeds/packages/lang/golang ]; then
    echo "删除旧 Golang"
    rm -rf feeds/packages/lang/golang
fi

if [ -e package/feeds/packages/golang ] || \
   [ -L package/feeds/packages/golang ]; then
    rm -f package/feeds/packages/golang
fi

git clone \
    -b 27.x \
    --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang

./scripts/feeds install -p packages golang || true

echo "Golang 27.x 处理完成"


###############################################################################
# 15. SmartDNS Rust Makefile 修复
###############################################################################

echo
echo "========================================"
echo "修复 SmartDNS Rust Makefile"
echo "========================================"

if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/package/openwrt/Makefile

    echo "已修复:"
    echo "package/myapp/smartdns/package/openwrt/Makefile"

fi


if [ -f package/myapp/smartdns/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/Makefile

    echo "已修复:"
    echo "package/myapp/smartdns/Makefile"

fi


###############################################################################
# 16. 自动添加 LuCI 中文语言包
###############################################################################

echo
echo "========================================"
echo "添加 LuCI 中文语言包"
echo "========================================"

if [ -f .config ]; then

    for pkg in $(
        grep '^CONFIG_PACKAGE_luci-app-.*=y' .config |
        sed 's/^CONFIG_PACKAGE_//;s/=y//' |
        sort -u
    ); do

        trans="luci-i18n-${pkg#luci-app-}"

        if grep -q \
            "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
            .config 2>/dev/null; then
            continue
        fi

        if grep -rq \
            "Package.*${trans}-zh-cn" \
            feeds/luci \
            feeds/*/* \
            package 2>/dev/null; then

            echo "添加中文语言包: ${trans}-zh-cn"
            echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

        fi

    done

fi


###############################################################################
# 17. conntrack
###############################################################################

echo
echo "========================================"
echo "设置 conntrack"
echo "========================================"

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    package/base-files/files/etc/sysctl.conf

echo \
    'net.netfilter.nf_conntrack_max=655550' \
    >> package/base-files/files/etc/sysctl.conf

echo "nf_conntrack_max = 655550"


###############################################################################
# 18. Wi-Fi 首次启动自动开启
###############################################################################

echo
echo "========================================"
echo "设置 Wi-Fi 首次启动自动开启"
echo "========================================"

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/zz-enable-wifi <<'EOF'
#!/bin/sh

. /lib/functions.sh

[ -s /etc/config/wireless ] || wifi config

if [ -s /etc/config/wireless ]; then

    config_load wireless

    enable_wifi()
    {
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

echo "Wi-Fi 首次启动自动开启已设置"


###############################################################################
# 19. 最终检查
###############################################################################

echo
echo "========================================"
echo "DIY2 最终检查"
echo "========================================"

echo
echo "package/myapp 独立第三方插件："

if [ -n "$MYAPP_PACKAGES" ]; then
    printf '%s\n' "$MYAPP_PACKAGES" |
        sed '/^[[:space:]]*$/d' |
        sort -u
else
    echo "无"
fi


echo
echo "检查 HomeProxy："

if package_entry_exists "packages" "luci-app-homeproxy"; then
    echo "WARNING: 官方 packages 中仍存在 HomeProxy"
fi

if [ -e package/myapp/homeproxy ]; then
    echo "✓ package/myapp/homeproxy"
fi


echo
echo "检查 HomeProxy 依赖入口："

for dep in sing-box sing-box-tiny; do

    FOUND=""

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

        if package_entry_exists "$feed" "$dep"; then
            FOUND="${FOUND}
${feed}/${dep}"
        fi

    done

    if [ -n "$FOUND" ]; then
        echo "$dep:"
        printf '%s\n' "$FOUND" |
            sed '/^[[:space:]]*$/d'
    else
        echo "WARNING: 未找到 $dep"
    fi

done


echo
echo "检查递归依赖包入口："

for pkg in \
    luci-app-fchomo \
    momo \
    luci-app-momo; do

    FOUND=""

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then
            FOUND="${FOUND}
${feed}/${pkg}"
        fi

    done

    if [ -n "$FOUND" ]; then
        echo "$pkg:"
        printf '%s\n' "$FOUND" |
            sed '/^[[:space:]]*$/d'
    else
        echo "✓ $pkg 未留下安装入口"
    fi

done


echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
