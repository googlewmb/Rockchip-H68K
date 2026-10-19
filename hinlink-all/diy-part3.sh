
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

set -e

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先"

###############################################################################
# 0. 基础目录
###############################################################################

TOPDIR="${TOPDIR:-$(pwd)}"

[ -d "$TOPDIR" ] || {
    echo "ERROR: TOPDIR 不存在: $TOPDIR"
    exit 1
}

cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"

###############################################################################
# 1. 核心依赖与第三方源码拉取 (优先于扫描逻辑)
###############################################################################

echo
echo "========================================"
echo "拉取/更新 核心依赖与 PassWall 组件"
echo "========================================"

# 1.1 替换 Golang 为 27.x
# if [ -d feeds/packages/lang/golang ]; then
#     echo "删除旧 Golang"
#     rm -rf feeds/packages/lang/golang
# fi
#
# git clone \
#     -b 27.x \
#     --depth 1 \
#     https://github.com/sbwml/packages_lang_golang \
#     feeds/packages/lang/golang

# 1.2 移除官方旧库
# PassWall 已由 DIY1 拉取到 package/myapp，这里不重复拉取
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall

# DIY1 已下载：
# package/myapp/passwall-packages
# package/myapp/passwall
#
# DIY2 不重复 Clone，以下仅保留原逻辑为注释
# rm -rf package/passwall-packages package/passwall-luci
# git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
# git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

# 1.3 关键：刷新并注册新拉取的包索引到编译环境
echo "更新并安装新依赖索引..."
./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a

###############################################################################
# 1.5 移植 VIKINGYFY miniupnpd 2.3.11 完整修复
###############################################################################

echo
echo "========================================"
echo "移植 VIKINGYFY miniupnpd 2.3.11 修复"
echo "========================================"

MINIUPNPD_COMMIT="99c39ee7476d1872b080ed486533e8520f3fdad3"
MINIUPNPD_URL="https://codeload.github.com/VIKINGYFY/immortalwrt/tar.gz/${MINIUPNPD_COMMIT}"
MINIUPNPD_TARGET="package/network/services/miniupnpd"
MINIUPNPD_FEED="feeds/packages/net/miniupnpd"
MINIUPNPD_ENTRY="package/feeds/packages/miniupnpd"

MINIUPNPD_TMP="$(mktemp -d)"
MINIUPNPD_ARCHIVE="${MINIUPNPD_TMP}/source.tar.gz"
MINIUPNPD_EXTRACT="${MINIUPNPD_TMP}/extract"

miniupnpd_cleanup()
{
    rm -rf "$MINIUPNPD_TMP"
}

# 下载指定提交
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 \
        "$MINIUPNPD_URL" \
        -o "$MINIUPNPD_ARCHIVE"
elif command -v wget >/dev/null 2>&1; then
    wget \
        --tries=3 \
        -O "$MINIUPNPD_ARCHIVE" \
        "$MINIUPNPD_URL"
else
    echo "ERROR: 找不到 curl 或 wget"
    miniupnpd_cleanup
    exit 1
fi

# 解压指定提交
mkdir -p "$MINIUPNPD_EXTRACT"
tar -xzf "$MINIUPNPD_ARCHIVE" -C "$MINIUPNPD_EXTRACT"

# 定位提交中的完整 miniupnpd 包目录
MINIUPNPD_SOURCE_MAKEFILE="$(
    find "$MINIUPNPD_EXTRACT" \
        -type f \
        -path '*/package/network/services/miniupnpd/Makefile' \
        -print -quit
)"

if [ -z "$MINIUPNPD_SOURCE_MAKEFILE" ]; then
    echo "ERROR: 提交中未找到 package/network/services/miniupnpd/Makefile"
    miniupnpd_cleanup
    exit 1
fi

MINIUPNPD_SOURCE="${MINIUPNPD_SOURCE_MAKEFILE%/Makefile}"

# 校验指定版本，防止下载错误或目录定位错误
if ! grep -Eq '^[[:space:]]*PKG_VERSION:=2\.3\.11[[:space:]]*$' \
    "$MINIUPNPD_SOURCE_MAKEFILE"; then
    echo "ERROR: 提交中的 miniupnpd 版本不是 2.3.11"
    miniupnpd_cleanup
    exit 1
fi

if ! grep -Eq '^[[:space:]]*PKG_RELEASE:=2[[:space:]]*$' \
    "$MINIUPNPD_SOURCE_MAKEFILE"; then
    echo "ERROR: 提交中的 PKG_RELEASE 不是 2"
    miniupnpd_cleanup
    exit 1
fi

# 检查完整包的关键文件
for required_file in \
    Makefile \
    files/miniupnpd.init \
    files/upnpd.config \
    patches
do
    if [ ! -e "$MINIUPNPD_SOURCE/$required_file" ]; then
        echo "ERROR: 修复包缺少必要文件: $required_file"
        miniupnpd_cleanup
        exit 1
    fi
done

# 输出提交中实际包含的补丁，避免硬编码猜测补丁名称
echo "指定提交中的 miniupnpd 补丁："

if [ -d "$MINIUPNPD_SOURCE/patches" ]; then
    find "$MINIUPNPD_SOURCE/patches" \
        -maxdepth 1 \
        -type f \
        -name '*.patch' \
        -printf '%f\n' |
        sort
else
    echo "ERROR: 修复包没有 patches 目录"
    miniupnpd_cleanup
    exit 1
fi

# 先完整复制到临时目录，确认源目录有效后再覆盖
MINIUPNPD_STAGED="${MINIUPNPD_TMP}/miniupnpd"
cp -a "$MINIUPNPD_SOURCE" "$MINIUPNPD_STAGED"

if [ ! -f "$MINIUPNPD_STAGED/Makefile" ]; then
    echo "ERROR: miniupnpd 临时目录校验失败"
    miniupnpd_cleanup
    exit 1
fi

# 用提交中的完整包覆盖主源码包
mkdir -p "$(dirname "$MINIUPNPD_TARGET")"
rm -rf "$MINIUPNPD_TARGET"
cp -a "$MINIUPNPD_STAGED" "$MINIUPNPD_TARGET"

# 删除旧 feed 包，防止 feeds install 再注册冲突版本
rm -rf "$MINIUPNPD_FEED"

# 删除可能残留的 feeds 安装入口
if [ -e "$MINIUPNPD_ENTRY" ] || [ -L "$MINIUPNPD_ENTRY" ]; then
    rm -f "$MINIUPNPD_ENTRY"
fi

# 检查移植结果
if [ ! -f "$MINIUPNPD_TARGET/Makefile" ]; then
    echo "ERROR: miniupnpd 主源码覆盖失败"
    miniupnpd_cleanup
    exit 1
fi

if ! grep -Eq '^[[:space:]]*PKG_VERSION:=2\.3\.11[[:space:]]*$' \
    "$MINIUPNPD_TARGET/Makefile"; then
    echo "ERROR: 覆盖后的 miniupnpd 版本检查失败"
    miniupnpd_cleanup
    exit 1
fi

if ! grep -Eq '^[[:space:]]*PKG_RELEASE:=2[[:space:]]*$' \
    "$MINIUPNPD_TARGET/Makefile"; then
    echo "ERROR: 覆盖后的 miniupnpd release 检查失败"
    miniupnpd_cleanup
    exit 1
fi

echo "miniupnpd 修复移植完成"
echo "提交: $MINIUPNPD_COMMIT"
echo "版本: 2.3.11"
echo "PKG_RELEASE: 2"
echo "主源码: $MINIUPNPD_TARGET"
echo "feed 旧版本: 已清理"
echo "feed 安装入口: 已清理"

miniupnpd_cleanup

###############################################################################
# 2. 第三方依赖预处理 (明确要求的移除项)
###############################################################################

echo
echo "========================================"
echo "第三方依赖预处理"
echo "========================================"

REMOVE_OFFICIAL_DEPS=""

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
        "^CONFIG_PACKAGE_${pkg}=(y|m)" \
        .config 2>/dev/null
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    [ -n "$pkg" ] || continue
    echo "明确要求：移除官方依赖入口 -> $pkg"

    for official_feed in $OFFICIAL_FEEDS; do
        remove_package_entry "$official_feed" "$pkg"
    done
done

###############################################################################
# 3. 获取包版本函数定义
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
# 5. 扫描 package/myapp 真正的 Package
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
            *'('*|*')'*|*'/'*)
                continue
                ;;
        esac

        MYAPP_PACKAGES="${MYAPP_PACKAGES}
$pkg"

        echo "✓ $pkg"

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null |
        xargs -0 -r sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u || true
    )

else

    echo "WARNING: package/myapp 不存在"

fi

###############################################################################
# 6. 收集当前 .config 中实际启用的 Package
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
# 7. 独立第三方插件优先
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

    while IFS= read -r -d '' mf; do

        [ -f "$mf" ] || continue

        if grep -Eq \
            "^[[:space:]]*define[[:space:]]+Package/${pkg}([[:space:]]|\\))" \
            "$mf" 2>/dev/null; then

            MYAPP_MAKEFILE="$mf"
            break

        fi

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null || true
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
# 8. 第三方集合源优先 (THIRD_PARTY_FEEDS > OFFICIAL_FEEDS)
###############################################################################

echo
echo "========================================"
echo "第三方集合源优先"
echo "========================================"

for pkg in $CONFIG_PACKAGES; do

    [ -n "$pkg" ] || continue

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
                echo "版本相同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"
            else
                echo "版本不同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"
                echo "原因: 第三方来源优先，不按版本号自动选择"
            fi

            remove_package_entry "$official_feed" "$pkg"

        fi

    done

done

###############################################################################
# 9. SmartDNS Rust Makefile 修复
###############################################################################

echo
echo "========================================"
echo "修复 SmartDNS Rust Makefile"
echo "========================================"

if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/package/openwrt/Makefile

    echo "已修复: package/myapp/smartdns/package/openwrt/Makefile"

fi

if [ -f package/myapp/smartdns/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/Makefile

    echo "已修复: package/myapp/smartdns/Makefile"

fi

###############################################################################
# 10. 自动添加 LuCI 中文语言包 (移除了内部 make defconfig)
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

        if grep -rnq \
            "Package.*${trans}-zh-cn" \
            package feeds 2>/dev/null; then

            echo "添加中文语言包: ${trans}-zh-cn"

            echo \
                "CONFIG_PACKAGE_${trans}-zh-cn=y" \
                >> .config

        fi

    done

fi

###############################################################################
# 11. conntrack 调优
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
# 12. Wi-Fi 首次启动自动开启
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
# 13. 最终来源检查
###############################################################################

echo
echo "========================================"
echo "最终第三方插件来源检查"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "[$pkg]"

    if [ -d package/myapp ]; then

        FOUND_MYAPP=""

        while IFS= read -r -d '' mf; do

            [ -f "$mf" ] || continue

            if grep -Eq \
                "^[[:space:]]*define[[:space:]]+Package/${pkg}([[:space:]]|\\))" \
                "$mf" 2>/dev/null; then

                FOUND_MYAPP="$mf"
                break

            fi

        done < <(
            find package/myapp \
                -type f \
                -name Makefile \
                -print0 2>/dev/null || true
        )

        if [ -n "$FOUND_MYAPP" ]; then

            echo "  package/myapp"
            echo "  version: $(get_package_version "$FOUND_MYAPP")"

        fi

    fi

done

###############################################################################
# 16. DIY2 完成
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
