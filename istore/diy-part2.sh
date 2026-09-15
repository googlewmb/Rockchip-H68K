#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
#
# 来源优先级：
#   1. package/myapp 独立第三方源码
#   2. DIY1 添加的第三方集合源
#   3. iStoreOS / OpenWrt 官方 feeds
#
# 规则：
#   - 同名包多个来源：第三方优先
#   - 版本相同：按来源优先级保留
#   - 版本不同：仍按来源优先级，不自动按版本号选择
#   - 普通依赖不会因为插件去重而删除
#   - 明确要求替换官方依赖的，使用 REMOVE_OFFICIAL_DEPS
#   - 只删除 package/feeds/<feed>/<pkg> 安装入口
#   - 不删除 feeds/<feed> 源码
#

set -e

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先"


###############################################################################
# 0. 基础目录
###############################################################################

[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"


###############################################################################
# 1. 第三方依赖预处理
#
# 只有明确确认：
#
#   第三方插件必须使用自己的依赖版本
#   官方对应依赖不能使用
#
# 才把官方依赖填写到这里。
#
# 例如：
#
# REMOVE_OFFICIAL_DEPS="
# libxxx
# libyyy
# "
#
# 注意：
#   这里处理的是“明确要求替换官方依赖”的特殊情况。
#
# 普通依赖不要填写。
# HomeProxy 的 sing-box / sing-box-tiny 也不要填写。
#
###############################################################################

echo
echo "========================================"
echo "第三方依赖预处理"
echo "========================================"

# 第三方插件明确要求替换官方依赖时，在这里填写。
#
# 例如：
#
# 某第三方插件自带 libxxx，并明确要求不要使用官方 feeds 中的 libxxx：
#
# REMOVE_OFFICIAL_DEPS="
# libxxx
# "
#
# 多个依赖：
#
# REMOVE_OFFICIAL_DEPS="
# libxxx
# libyyy
# "
#
# 注意：
# 1. 这里只删除 package/feeds/<feed>/<pkg> 安装入口
# 2. 不删除 feeds/<feed> 源码
# 3. 普通插件依赖不要填写
# 4. 只有明确确认第三方版本必须替换官方版本的依赖才填写

REMOVE_OFFICIAL_DEPS=""


###############################################################################
# 2. feed 定义
###############################################################################

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


###############################################################################
# 3. 基础函数
###############################################################################

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


package_makefile()
{
    local feed="$1"
    local pkg="$2"
    local makefile="package/feeds/${feed}/${pkg}/Makefile"

    if [ -f "$makefile" ]; then
        readlink -f "$makefile" 2>/dev/null || true
    fi
}


is_enabled()
{
    local pkg="$1"

    grep -Eq \
        "^CONFIG_PACKAGE_${pkg}=(y|m)$" \
        .config 2>/dev/null
}


###############################################################################
# 4. 获取包版本
#
# 尽量从 Makefile 中读取：
#
#   PKG_VERSION
#
# 或：
#
#   PKG_VERSION:=...
#
# 如果无法读取，则显示 unknown。
#
###############################################################################

get_package_version()
{
    local makefile="$1"
    local version=""

    [ -f "$makefile" ] || {
        echo "unknown"
        return
    }

    version="$(
        sed -nE \
            's/^[[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*(.*)$/\1/p' \
            "$makefile" |
        head -n 1
    )"

    if [ -z "$version" ]; then
        version="$(
            sed -nE \
                's/^[[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*(.*)$/release-\1/p' \
                "$makefile" |
            head -n 1
        )"
    fi

    [ -n "$version" ] || version="unknown"

    echo "$version"
}


###############################################################################
# 5. H68K DTS
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

    echo "WARNING: 未找到 H68K DTS:"
    echo "$DTS_SOURCE"

fi


###############################################################################
# 6. 扫描 package/myapp 真正的 Package
#
# 只匹配：
#
#   define Package/xxx
#
# 不匹配：
#
#   define Package/$(PKG_NAME)
#   define Package/foo/description
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

    echo "WARNING: package/myapp 不存在"

fi


###############################################################################
# 7. 收集当前 .config 中实际启用的 Package
###############################################################################

echo
echo "========================================"
echo "读取当前 .config"
echo "========================================"

CONFIG_PACKAGES=""

if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

fi

echo "当前启用的第三方/官方 Package 数量：$(printf '%s\n' "$CONFIG_PACKAGES" | sed '/^$/d' | wc -l)"


###############################################################################
# 8. 独立第三方插件优先
#
# package/myapp > 其他所有来源
#
# 只删除：
#
#   package/feeds/<feed>/<pkg>
#
# 不碰：
#
#   feeds/<feed>
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

    MYAPP_MAKEFILE=""

    while IFS= read -r mf; do

        [ -f "$mf" ] || continue

        if grep -q \
            "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*$" \
            "$mf" 2>/dev/null; then

            MYAPP_MAKEFILE="$mf"
            break

        fi

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print
    )

    if [ -n "$MYAPP_MAKEFILE" ]; then
        MYAPP_VERSION="$(get_package_version "$MYAPP_MAKEFILE")"
        echo "package/myapp 版本: $MYAPP_VERSION"
    else
        MYAPP_VERSION="unknown"
    fi

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

        if package_entry_exists "$feed" "$pkg"; then

            MAKEFILE="$(package_makefile "$feed" "$pkg")"
            VERSION="$(get_package_version "$MAKEFILE")"

            echo "发现重复来源:"
            echo "  $feed/$pkg"
            echo "  版本: $VERSION"
            echo "选择: package/myapp"
            echo "原因: 独立第三方源码优先"

            remove_package_entry "$feed" "$pkg"

        fi

    done

done


###############################################################################
# 9. 第三方集合源 > 官方
#
# 只检查当前 .config 已启用的包。
#
# 这样不会因为 small / kenzo 等集合源中存在大量无关包，
# 就把这些包全部拿来参与 Kconfig。
#
###############################################################################

echo
echo "========================================"
echo "第三方集合源优先"
echo "========================================"

for pkg in $CONFIG_PACKAGES; do

    [ -n "$pkg" ] || continue

    # package/myapp 已经处理
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

    [ -n "$THIRD_SOURCE" ] || continue

    THIRD_MAKEFILE="$(package_makefile "$THIRD_SOURCE" "$pkg")"
    THIRD_VERSION="$(get_package_version "$THIRD_MAKEFILE")"

    echo
    echo "发现第三方重复包: $pkg"
    echo "第三方来源: ${THIRD_SOURCE}/${pkg}"
    echo "第三方版本: $THIRD_VERSION"

    for official_feed in $OFFICIAL_FEEDS; do

        if package_entry_exists "$official_feed" "$pkg"; then

            OFFICIAL_MAKEFILE="$(package_makefile "$official_feed" "$pkg")"
            OFFICIAL_VERSION="$(get_package_version "$OFFICIAL_MAKEFILE")"

            echo "官方来源: ${official_feed}/${pkg}"
            echo "官方版本: $OFFICIAL_VERSION"

            if [ "$THIRD_VERSION" = "$OFFICIAL_VERSION" ]; then

                echo "版本相同"
                echo "选择: 第三方 ${THIRD_SOURCE}/${pkg}"

            else

                echo "版本不同"
                echo "选择: 第三方 ${THIRD_SOURCE}/${pkg}"
                echo "原因: 第三方来源优先，不按版本号自动选择"

            fi

            remove_package_entry "$official_feed" "$pkg"

        fi

    done

done


###############################################################################
# 10. HomeProxy 依赖保护
#
# HomeProxy 是 package/myapp 中独立 clone 的插件。
#
# 正常依赖：
#
#   luci-app-homeproxy
#       ├── sing-box
#       └── sing-box-tiny
#
# 这里绝不因为插件去重删除：
#
#   sing-box
#   sing-box-tiny
#
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

            THIRD_MAKEFILE="$(package_makefile "$THIRD_SOURCE" "$dep")"
            THIRD_VERSION="$(get_package_version "$THIRD_MAKEFILE")"

            echo "第三方依赖:"
            echo "  ${THIRD_SOURCE}/${dep}"
            echo "  版本: $THIRD_VERSION"

            for official_feed in $OFFICIAL_FEEDS; do

                if package_entry_exists "$official_feed" "$dep"; then

                    OFFICIAL_MAKEFILE="$(package_makefile "$official_feed" "$dep")"
                    OFFICIAL_VERSION="$(get_package_version "$OFFICIAL_MAKEFILE")"

                    echo "官方依赖:"
                    echo "  ${official_feed}/${dep}"
                    echo "  版本: $OFFICIAL_VERSION"

                    if [ "$THIRD_VERSION" = "$OFFICIAL_VERSION" ]; then
                        echo "版本相同 → 使用第三方"
                    else
                        echo "版本不同 → 使用第三方"
                        echo "原因: 第三方依赖优先"
                    fi

                    remove_package_entry "$official_feed" "$dep"

                fi

            done

        else

            echo "未发现第三方替代版本"
            echo "保留现有官方依赖: $dep"

        fi

    done

else

    echo "HomeProxy 当前未在 .config 中启用"

fi


###############################################################################
# 11. 修复 sing-box -> HomeProxy 错误反向依赖
#
# 正确：
#
#   HomeProxy
#       ↓
#   sing-box-tiny
#       ↓
#   sing-box
#
# 错误：
#
#   sing-box
#       ↓
#   HomeProxy
#
###############################################################################

echo
echo "========================================"
echo "修复 sing-box → HomeProxy 反向依赖"
echo "========================================"

for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

    MAKEFILE="$(package_makefile "$feed" "sing-box")"

    [ -n "$MAKEFILE" ] || continue
    [ -f "$MAKEFILE" ] || continue

    echo "检查: $MAKEFILE"

    # 删除 DEPENDS 中错误的：
    #
    #   +luci-app-homeproxy
    #
    sed -i -E \
        's/[[:space:]]+\+luci-app-homeproxy([[:space:]]|$)/ /g' \
        "$MAKEFILE"

    # 删除直接写入的错误 Kconfig 关系。
    sed -i -E \
        '/^[[:space:]]*(select|depends on)[[:space:]]+PACKAGE_luci-app-homeproxy[[:space:]]*$/d' \
        "$MAKEFILE"

done


###############################################################################
# 12. sing-box-tiny 正常依赖保护
###############################################################################

echo
echo "========================================"
echo "保护 sing-box-tiny → sing-box"
echo "========================================"

for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

    MAKEFILE="$(package_makefile "$feed" "sing-box-tiny")"

    [ -n "$MAKEFILE" ] || continue
    [ -f "$MAKEFILE" ] || continue

    echo "保留 sing-box-tiny 正常依赖: $MAKEFILE"

done


###############################################################################
# 13. 修复当前已发现的自递归 Kconfig
#
#   luci-app-fchomo -> luci-app-fchomo
#   momo            -> momo
#   luci-app-momo   -> luci-app-momo
#
# 未启用：
#   删除 package/feeds/<feed>/<pkg> 入口
#
# 已启用：
#   尝试删除 Makefile 中自身依赖
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

        MAKEFILE="$(package_makefile "$feed" "$pkg")"

        [ -n "$MAKEFILE" ] || continue
        [ -f "$MAKEFILE" ] || continue

        echo "检查自依赖: ${feed}/${pkg}"

        sed -i -E \
            "s/[[:space:]]+\+${dep}([[:space:]]|$)/ /g" \
            "$MAKEFILE"

        sed -i -E \
            "/^[[:space:]]*(select|depends on)[[:space:]]+PACKAGE_${dep}[[:space:]]*$/d" \
            "$MAKEFILE"

    done
}


if is_enabled "luci-app-fchomo"; then

    echo "luci-app-fchomo 已启用"
    fix_self_dependency "luci-app-fchomo" "luci-app-fchomo"

else

    echo "luci-app-fchomo 未启用，删除安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "luci-app-fchomo"
    done

fi


if is_enabled "momo"; then

    echo "momo 已启用"
    fix_self_dependency "momo" "momo"

else

    echo "momo 未启用，删除安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "momo"
    done

fi


if is_enabled "luci-app-momo"; then

    echo "luci-app-momo 已启用"
    fix_self_dependency "luci-app-momo" "luci-app-momo"

else

    echo "luci-app-momo 未启用，删除安装入口"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        remove_package_entry "$feed" "luci-app-momo"
    done

fi


###############################################################################
# 14. 清理当前已知的无效依赖包
#
# 这些包之前出现：
#
#   dae       -> vmlinux-btf
#   daed      -> vmlinux-btf
#   honk      -> vmlinux-btf
#   luci-app-baidupcs-web -> baidupcs-web
#   luci-app-radicale3 -> rpcd-mod-rad3-enc
#
# 未启用才删除。
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
        echo "WARNING: $pkg 可能仍存在依赖警告"

    else

        echo "未启用，删除入口: $pkg"

        for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
            remove_package_entry "$feed" "$pkg"
        done

    fi

done


###############################################################################
# 15. Golang 27.x
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
# 16. SmartDNS Rust Makefile 修复
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
# 17. 自动添加 LuCI 中文语言包
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

            echo \
                "CONFIG_PACKAGE_${trans}-zh-cn=y" \
                >> .config

        fi

    done

fi


###############################################################################
# 18. conntrack
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
# 19. Wi-Fi 首次启动自动开启
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
# 20. 最终来源检查
#
# 输出：
#
#   包名
#   来源
#   版本
#
# 方便确认最终到底使用哪个版本。
###############################################################################

echo
echo "========================================"
echo "最终第三方插件来源检查"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "[$pkg]"

    if [ -d "package/myapp" ]; then

        FOUND_MYAPP=""

        while IFS= read -r mf; do

            [ -f "$mf" ] || continue

            if grep -q \
                "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*$" \
                "$mf" 2>/dev/null; then

                FOUND_MYAPP="$mf"
                break

            fi

        done < <(
            find package/myapp \
                -type f \
                -name Makefile \
                -print
        )

        if [ -n "$FOUND_MYAPP" ]; then

            echo "  package/myapp"
            echo "  version: $(get_package_version "$FOUND_MYAPP")"

        fi

    fi

done


###############################################################################
# 21. HomeProxy 最终依赖检查
###############################################################################

echo
echo "========================================"
echo "HomeProxy 最终依赖检查"
echo "========================================"

for dep in sing-box sing-box-tiny; do

    FOUND=""

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do

        if package_entry_exists "$feed" "$dep"; then
            FOUND="${FOUND}
${feed}/${dep}"
        fi

    done

    if [ -n "$FOUND" ]; then

        echo
        echo "$dep:"

        printf '%s\n' "$FOUND" |
            sed '/^[[:space:]]*$/d' |
        while IFS= read -r item; do

            feed="${item%%/*}"
            pkg="${item#*/}"

            MAKEFILE="$(package_makefile "$feed" "$pkg")"
            VERSION="$(get_package_version "$MAKEFILE")"

            echo "  $item"
            echo "  version: $VERSION"

        done

    else

        echo "WARNING: 未找到 HomeProxy 依赖: $dep"

    fi

done


###############################################################################
# 22. 检查是否还存在已知递归包
###############################################################################

echo
echo "========================================"
echo "递归依赖最终检查"
echo "========================================"

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

        echo "$pkg 仍存在："

        printf '%s\n' "$FOUND" |
            sed '/^[[:space:]]*$/d'

    else

        echo "✓ $pkg 未留下安装入口"

    fi

done


###############################################################################
# 23. DIY2 完成
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
echo "第三方优先级："
echo "  package/myapp > 第三方集合源 > 官方 feeds"
echo
echo "依赖规则："
echo "  普通依赖不删除"
echo "  依赖多来源时第三方优先"
echo "  明确要求替换官方依赖的使用 REMOVE_OFFICIAL_DEPS"
echo
echo "版本规则："
echo "  版本相同 → 按来源优先级"
echo "  版本不同 → 仍按来源优先级"
echo "  不自动因为版本号更高而选择官方"
echo
echo "========================================"
