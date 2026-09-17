#!/bin/bash
# DIY2 - H68K + iStoreOS 24.10
# 第三方插件 / 依赖 / 来源优先级：
# 1. package/myapp
# 2. DIY1 第三方集合源
# 3. iStoreOS / OpenWrt 官方 feeds

set -e

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先"

# 基础目录
[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"
echo "TOPDIR: $TOPDIR"

# 核心依赖与 PassWall
echo "[1] 拉取/更新 Golang 与 PassWall"

if [ -d feeds/packages/lang/golang ]; then
    rm -rf feeds/packages/lang/golang
fi

git clone -b 27.x --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/passwall-packages package/passwall-luci

git clone --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
    package/passwall-packages

git clone --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall \
    package/passwall-luci

./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a

# 第三方来源处理
echo "[2] 处理第三方依赖来源"

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

package_entry_exists() {
    local feed="$1"
    local pkg="$2"
    local entry="package/feeds/${feed}/${pkg}"
    [ -e "$entry" ] || [ -L "$entry" ]
}

remove_package_entry() {
    local feed="$1"
    local pkg="$2"
    local entry="package/feeds/${feed}/${pkg}"

    if [ -e "$entry" ] || [ -L "$entry" ]; then
        echo "删除安装入口: ${feed}/${pkg}"
        rm -f "$entry"
    fi
}

package_makefile() {
    local feed="$1"
    local pkg="$2"
    local makefile="package/feeds/${feed}/${pkg}/Makefile"

    if [ -f "$makefile" ]; then
        readlink -f "$makefile" 2>/dev/null || true
    fi
}

is_enabled() {
    local pkg="$1"
    grep -Eq "^CONFIG_PACKAGE_${pkg}=(y|m)$" .config 2>/dev/null
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    [ -n "$pkg" ] || continue

    for official_feed in $OFFICIAL_FEEDS; do
        remove_package_entry "$official_feed" "$pkg"
    done
done

# 获取包版本
get_package_version() {
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

# SONiC Full Cone NAT
echo "[3] 应用 SONiC Full Cone NAT"

if curl -fsSL \
    https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh |
    bash; then
    echo "✓ SONiC Full Cone 补丁应用成功"
    SONIC_OK=1
else
    echo "✗ SONiC Full Cone 补丁应用失败"
    SONIC_OK=0
fi

rm -f package/network/utils/nftables/patches/100-nftables-add-fullcone-expression-support.patch
rm -f package/network/utils/nftables/patches/999-*fullcone*.patch 2>/dev/null || true
rm -f package/network/utils/nftables/patches/*fullcone*100*.patch 2>/dev/null || true

mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-enable-fullcone <<'EOF'
#!/bin/sh

sleep 3

uci -q set firewall.@defaults[0].fullcone='1'
uci -q set firewall.@zone[1].fullcone='1'

# uci -q add_list firewall.@zone[1].fullcone_proto='udp'

uci -q commit firewall

if [ -f /etc/config/turboacc ]; then
    uci -q set turboacc.config.fullcone_nat='1'
    uci -q set turboacc.config.fullcone_nat_mode='1'
    uci -q commit turboacc
fi

exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-enable-fullcone

[ "$SONIC_OK" = "0" ] &&
    echo "警告：SONiC Full Cone 补丁失败，请检查网络或源码版本！"

# 扫描 package/myapp
echo "[4] 扫描 package/myapp"

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue

        case "$pkg" in
            '('*|*')'|*'/'*) continue ;;
        esac

        MYAPP_PACKAGES="$MYAPP_PACKAGES
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

# 读取 .config
echo "[5] 读取当前 .config"

CONFIG_PACKAGES=""

if [ -f .config ]; then
    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"
fi

echo "当前启用 Package 数量：$(
    printf '%s\n' "$CONFIG_PACKAGES" |
    sed '/^$/d' |
    wc -l
)"

# package/myapp 优先
echo "[6] 独立第三方插件优先"

for pkg in $MYAPP_PACKAGES; do
    [ -n "$pkg" ] || continue

    echo "检查: $pkg"

    MYAPP_MAKEFILE=""

    while IFS= read -r -d '' mf; do
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

            echo "发现重复来源: $feed/$pkg"
            echo "版本: $VERSION"
            echo "选择: package/myapp"

            remove_package_entry "$feed" "$pkg"
        fi
    done
done

# 第三方集合源优先
echo "[7] 第三方集合源优先"

for pkg in $CONFIG_PACKAGES; do
    [ -n "$pkg" ] || continue

    case "
$MYAPP_PACKAGES
" in
        *"
$pkg
"*) continue ;;
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

    echo "发现第三方重复包: $pkg"
    echo "第三方来源: ${THIRD_SOURCE}/${pkg}"
    echo "第三方版本: $THIRD_VERSION"

    for official_feed in $OFFICIAL_FEEDS; do
        if package_entry_exists "$official_feed" "$pkg"; then
            OFFICIAL_MAKEFILE="$(package_makefile "$official_feed" "$pkg")"
            OFFICIAL_VERSION="$(get_package_version "$OFFICIAL_MAKEFILE")"

            echo "官方来源: ${official_feed}/${pkg}"
            echo "官方版本: $OFFICIAL_VERSION"
            echo "选择: 第三方 ${THIRD_SOURCE}/${pkg}"

            remove_package_entry "$official_feed" "$pkg"
        fi
    done
done

# SmartDNS Rust Makefile
echo "[8] 修复 SmartDNS Rust Makefile"

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

# 自动添加 LuCI 中文语言包
echo "[9] 添加 LuCI 中文语言包"

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
            echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config
        fi
    done
fi

# conntrack
echo "[10] 设置 conntrack"

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
    >> package/base-files/files/etc/sysctl.conf

# Wi-Fi 首次启动自动开启
echo "[11] 设置 Wi-Fi 首次启动自动开启"

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

# 检查插件依赖
echo "[12] 检查 .config 插件依赖"

if [ -f .config ]; then
    MISSING_DEPS_FOUND=0

    for pkg in $CONFIG_PACKAGES; do
        [ -n "$pkg" ] || continue

        pkg_makefile=""

        while IFS= read -r -d '' mf; do
            if grep -q \
                "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*$" \
                "$mf" 2>/dev/null; then

                pkg_makefile="$mf"
                break
            fi
        done < <(
            find package feeds \
                -maxdepth 5 \
                -type f \
                -name Makefile \
                -print0 2>/dev/null || true
        )

        [ -n "$pkg_makefile" ] || continue

        raw_depends="$(
            awk -v target="Package/$pkg" '
                $0 ~ "define " target { in_pkg=1; next }
                in_pkg && /^endef/ { in_pkg=0 }
                in_pkg && /^[[:space:]]*DEPENDS[[:space:]]*:?=/ {
                    sub(/^[[:space:]]*DEPENDS[[:space:]]*:?=[[:space:]]*/, "");
                    print $0
                }
            ' "$pkg_makefile" |
            tr '\n' ' '
        )"

        [ -n "$raw_depends" ] || continue

        parsed_deps="$(
            echo "$raw_depends" |
            sed -E \
                's/\+@?[A-Za-z0-9_:-]+//g;
                 s/\+/\ /g;
                 s/@[A-Za-z0-9_:-]+//g' |
            tr ' ' '\n' |
            sed -e 's/^[[:space:]]*//' \
                -e 's/[[:space:]]*$//' |
            grep -v -E '^$|^\+|^\%|^!' |
            sort -u || true
        )"

        for dep in $parsed_deps; do
            [ -n "$dep" ] || continue

            case "$dep" in
                libc|librt|libpthread|kernel|kmod-*|luci-base|luci-compat)
                    continue
                    ;;
            esac

            if ! grep -Eq \
                "^CONFIG_PACKAGE_${dep}=(y|m)$" \
                .config 2>/dev/null; then

                dep_exists=0

                if grep -rnq \
                    "^[[:space:]]*define[[:space:]]\+Package/${dep}[[:space:]]*$" \
                    package/ feeds/ 2>/dev/null; then
                    dep_exists=1
                fi

                if [ "$dep_exists" -eq 0 ]; then
                    echo "❌ 插件 [$pkg] 缺少依赖源码: [$dep]"
                    MISSING_DEPS_FOUND=1
                else
                    echo "⚠️ 插件 [$pkg] 依赖 [$dep] 未在 .config 启用"
                fi
            fi
        done
    done

    if [ "$MISSING_DEPS_FOUND" -eq 0 ]; then
        echo "✓ 插件依赖完整性检查通过"
    else
        echo "⚠️ 发现缺失依赖，请检查 package/feed"
    fi
fi

# 最终来源检查
echo "[13] 最终第三方插件来源检查"

for pkg in $MYAPP_PACKAGES; do
    [ -n "$pkg" ] || continue

    FOUND_MYAPP=""

    while IFS= read -r -d '' mf; do
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
            -print0 2>/dev/null || true
    )

    if [ -n "$FOUND_MYAPP" ]; then
        echo "$pkg -> package/myapp / $(get_package_version "$FOUND_MYAPP")"
    fi
done

echo
echo "DIY2 OK"
