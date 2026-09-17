#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
# 第三方插件 / 依赖 / 来源优先级
#
# 优先级：
# 1. package/myapp
# 2. DIY1 第三方集合源
# 3. iStoreOS / OpenWrt 官方 feeds
#

set -e

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先"

# --- 0. 基础目录 ---

[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"
echo "TOPDIR: $TOPDIR"

# --- 1. 核心依赖与 PassWall ---

echo
echo "== 拉取/更新核心依赖与 PassWall =="

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/passwall-packages package/passwall-luci

git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

echo "更新并安装依赖索引..."
./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a

# --- 2. 第三方依赖预处理 ---

echo
echo "== 第三方依赖预处理 =="

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
    grep -Eq "^CONFIG_PACKAGE_${pkg}=(y|m)$" .config
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    [ -n "$pkg" ] || continue
    echo "明确要求：移除官方依赖入口 -> $pkg"

    for official_feed in $OFFICIAL_FEEDS; do
        remove_package_entry "$official_feed" "$pkg"
    done
done

# --- 3. 获取包版本 ---

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

# --- 4.5 H68K U-Boot 自动 DTB 识别 ---

echo
echo "== H68K U-Boot 自动 DTB 识别修复 =="

# GPIO143 -> GMAC1
# ADC7 -> H68K / H69K
# H68K ADC7 实测 781~783
# 770~795 -> H68K -> hwflag=1 -> rockchip1.dtb
# 其他值继续官方逻辑

BOOT_SCRIPT=""

for f in \
    target/linux/rockchip/image/legacy/rk3568-hinlink.bootscript \
    target/linux/rockchip/image/rk3568-hinlink.bootscript
do
    if [ -f "$f" ]; then
        BOOT_SCRIPT="$f"
        break
    fi
done

if [ -z "$BOOT_SCRIPT" ]; then
    echo "ERROR: 找不到 rk3568-hinlink.bootscript"

    find target/linux/rockchip \
        -type f \
        \( -iname '*hinlink*' -o -iname '*rk3568*' \) \
        2>/dev/null |
    sort |
    head -100

    echo "为了避免误修改其他文件，停止 DIY2。"
    exit 1
fi

echo "找到 boot script: $BOOT_SCRIPT"

# 已存在补丁：验证后继续执行后续 DIY2
if grep -q 'H68K 当前实机实测 ADC7' "$BOOT_SCRIPT"; then

    echo "检测到 H68K 自动识别补丁，跳过重复修改。"

    if grep -q \
        'test "$adc_value" -ge 770 -a "$adc_value" -le 795' \
        "$BOOT_SCRIPT" &&
       grep -q 'setenv hwflag 1' "$BOOT_SCRIPT" &&
       grep -q 'setenv hwflag 10' "$BOOT_SCRIPT"; then

        echo "H68K/H69K 自动识别逻辑验证通过。"

    else
        echo "ERROR: 检测到补丁标记，但实际代码不完整。"
        echo "为了避免继续使用异常 bootscript，停止 DIY2。"
        exit 1
    fi

else

    echo "检查官方自动识别逻辑..."

    if ! grep -q 'gpio input 143' "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 GPIO143 检测逻辑。"
        exit 1
    fi

    if ! grep -q \
        'adc single saradc@fe720000 7 adc_value' \
        "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 ADC7 检测逻辑。"
        exit 1
    fi

    if ! grep -q 'h69k' "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 H69K 判断逻辑。"
        exit 1
    fi

    if ! grep -q \
        'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
        "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 hwflag -> DTB 加载逻辑。"
        exit 1
    fi

    echo "官方自动识别逻辑检查通过。"

    # 精确替换官方 ADC 判断
    python3 - "$BOOT_SCRIPT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

old = """    if test -n "$adc_value"; then
        # h68k 511-524
        # h69k 691-695
        if test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then
            echo h69k
            setenv hwflag 10
        fi
    fi
"""

new = """    if test -n "$adc_value"; then
        # H68K 当前实机实测 ADC7 = 781~783
        # 使用 770~795 作为容差范围
        # 优先识别当前 H68K，避免被原 H69K 区间误判
        if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then
            echo h68k
            setenv hwflag 1

        # 保留官方原有 H69K 判断逻辑
        elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then
            echo h69k
            setenv hwflag 10
        fi
    fi
"""

if old not in text:
    print("ERROR: 没有找到预期的官方 ADC 判断代码。")
    print("为了避免误修改错误版本，DIY2 已停止。")
    sys.exit(1)

text = text.replace(old, new, 1)
path.write_text(text)

print("H68K 自动识别补丁应用成功。")
PY

fi

# --- 4.5 验证 H68K 自动识别 ---

echo
echo "== 验证 H68K 自动识别逻辑 =="

if ! grep -q 'H68K 当前实机实测 ADC7' "$BOOT_SCRIPT"; then
    echo "ERROR: H68K 补丁标记不存在。"
    exit 1
fi

if ! grep -q \
    'test "$adc_value" -ge 770 -a "$adc_value" -le 795' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H68K ADC 770~795 判断不存在。"
    exit 1
fi

if ! grep -q 'echo h68k' "$BOOT_SCRIPT"; then
    echo "ERROR: H68K 识别逻辑不存在。"
    exit 1
fi

if ! grep -q 'setenv hwflag 1' "$BOOT_SCRIPT"; then
    echo "ERROR: H68K hwflag=1 不存在。"
    exit 1
fi

if ! grep -q 'echo h69k' "$BOOT_SCRIPT"; then
    echo "ERROR: H69K 识别逻辑不存在。"
    exit 1
fi

if ! grep -q 'setenv hwflag 10' "$BOOT_SCRIPT"; then
    echo "ERROR: H69K hwflag=10 不存在。"
    exit 1
fi

if ! grep -q 'gpio input 143' "$BOOT_SCRIPT"; then
    echo "ERROR: GPIO143 逻辑被破坏。"
    exit 1
fi

if ! grep -q \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: ADC7 逻辑被破坏。"
    exit 1
fi

if ! grep -q \
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: hwflag -> DTB 加载逻辑不存在。"
    exit 1
fi

grep -n -A22 -B6 \
    'H68K 当前实机实测 ADC7' \
    "$BOOT_SCRIPT" || true

echo
echo "✓ H68K: ADC7 770~795 -> hwflag=1 -> rockchip1.dtb"
echo "✓ H69K: 原有判断 -> hwflag=10 -> rockchip10.dtb"
echo "✓ GPIO143: 原有逻辑保持不变"
echo "✓ ADC7: 原有读取逻辑保持不变"
echo "✓ hwflag -> DTB: 原有加载逻辑保持不变"

echo
echo "boot script:"
ls -lh "$BOOT_SCRIPT"

echo
echo "SHA256:"
sha256sum "$BOOT_SCRIPT"

# --- 5. 扫描 package/myapp ---

echo
echo "== 扫描 DIY1 独立第三方插件 =="

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue

        case "$pkg" in
            '$('*|*'$)'|*/*)
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
            -print0 2>/dev/null |
        xargs -0 -r sed -nE \
            's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u || true
    )

else
    echo "WARNING: package/myapp 不存在"
fi

# --- 6. 读取 .config ---

echo
echo "== 读取当前 .config =="

CONFIG_PACKAGES=""

if [ -f .config ]; then
    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"
fi

echo "当前启用 Package 数量：$(printf '%s\n' "$CONFIG_PACKAGES" | sed '/^$/d' | wc -l)"

# --- 7. 独立第三方插件优先 ---

echo
echo "== 独立第三方插件优先 =="

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
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

            echo "重复来源: $feed/$pkg"
            echo "版本: $VERSION"
            echo "选择: package/myapp"

            remove_package_entry "$feed" "$pkg"

        fi

    done

done

# --- 8. 第三方集合源优先 ---

echo
echo "== 第三方集合源优先 =="

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
    echo "第三方包: $pkg"
    echo "来源: ${THIRD_SOURCE}/${pkg}"
    echo "版本: $THIRD_VERSION"

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

# --- 9. SmartDNS Rust Makefile ---

echo
echo "== 修复 SmartDNS Rust Makefile =="

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

# --- 10. LuCI 中文语言包 ---

echo
echo "== 添加 LuCI 中文语言包 =="

if [ -f .config ]; then

    for pkg in $(
        grep '^CONFIG_PACKAGE_luci-app-.*=y' .config |
        sed 's/^CONFIG_PACKAGE_//;s/=y//' |
        sort -u
    ); do

        trans="luci-i18n-${pkg#luci-app-}"

        grep -q \
            "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
            .config 2>/dev/null && continue

        if grep -rnq \
            "Package.*${trans}-zh-cn" \
            package feeds 2>/dev/null; then

            echo "添加中文语言包: ${trans}-zh-cn"
            echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

        fi

    done

fi

# --- 11. conntrack ---

echo
echo "== 设置 conntrack =="

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
    >> package/base-files/files/etc/sysctl.conf

echo "nf_conntrack_max = 655550"

# --- 12. Wi-Fi 首次启动自动开启 ---

echo
echo "== 设置 Wi-Fi 首次启动自动开启 =="

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

# --- 12.5 插件依赖完整性 ---

echo
echo "== 检查 .config 插件依赖 =="

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
                -print0 \
                2>/dev/null || true
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
                's/\+@?[A-Za-z0-9_:-]+//g; s/\+/\ /g; s/@[A-Za-z0-9_:-]+//g' |
            tr ' ' '\n' |
            sed \
                -e 's/^[[:space:]]*//' \
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
                    echo "❌ [警告] $pkg 依赖 $dep，但源码树缺失！"
                    MISSING_DEPS_FOUND=1
                else
                    echo "⚠️ [提示] $pkg 依赖 $dep，但未在 .config 中启用。"
                fi

            fi

        done

    done

    if [ "$MISSING_DEPS_FOUND" -eq 0 ]; then
        echo "✓ 插件依赖完整性检查通过！"
    else
        echo "⚠️ 发现缺失的第三方依赖，请检查 package/feed。"
    fi

fi

# --- 13. 最终来源检查 ---

echo
echo "== 最终第三方插件来源检查 =="

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "[$pkg]"

    if [ -d package/myapp ]; then

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
            echo "  package/myapp"
            echo "  version: $(get_package_version "$FOUND_MYAPP")"
        fi

    fi

done

# --- 14. 完成 ---

echo
echo "== DIY2 OK =="

echo "H68K U-Boot 自动 DTB 修复状态:"

if [ -n "$BOOT_SCRIPT" ] && \
   grep -q 'H68K 当前实机实测 ADC7' "$BOOT_SCRIPT" 2>/dev/null; then

    echo "  ✓ 已应用"
    echo "  ✓ ADC7 770~795 -> hwflag=1 -> rockchip1.dtb"
    echo "  ✓ 原 H69K 判断保留"
    echo "  ✓ GPIO143 判断保留"

else

    echo "  ⚠ 未检测到 H68K 自动识别补丁"

fi

echo
echo "== DIY2 OK =="
