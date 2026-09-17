#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
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
#
# 官方默认逻辑：
# GPIO143 检测到 GMAC1 后
#     setenv hwflag 1
#
# H68K：
# ADC7 770~795
#     保持默认 hwflag=1
#     -> rockchip1.dtb
#
# 注意：
# 不在 H68K 分支再次 setenv hwflag 1
# 这样可以保留不同批次板子的原有默认值逻辑。
#
# H69K：
# 保留官方判断
#     setenv hwflag 10
#     -> rockchip10.dtb

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

# --- 已存在补丁：验证后继续 ---

if grep -q 'H68K 当前实机 ADC7' "$BOOT_SCRIPT"; then

    echo "检测到 H68K 自动识别补丁，跳过重复修改。"

    if grep -Fq \
        'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
        "$BOOT_SCRIPT" &&
       grep -Fq \
        'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
        "$BOOT_SCRIPT" &&
       grep -q 'echo h68k' "$BOOT_SCRIPT" &&
       grep -q 'echo h69k' "$BOOT_SCRIPT" &&
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

    # GPIO143
    if ! grep -q 'gpio input 143' "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 GPIO143 检测逻辑。"
        exit 1
    fi

    # ADC7
    if ! grep -Fq \
        'adc single saradc@fe720000 7 adc_value' \
        "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 ADC7 检测逻辑。"
        exit 1
    fi

    # 官方 H69K
    if ! grep -q 'echo h69k' "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 H69K 判断逻辑。"
        exit 1
    fi

    # 官方 H69K ADC 条件
    if ! grep -Fq \
        'if test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
        "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到官方 H69K ADC 判断条件。"
        exit 1
    fi

    # 官方 hwflag -> DTB
    if ! grep -Fq \
        'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
        "$BOOT_SCRIPT"; then
        echo "ERROR: 未找到 hwflag -> DTB 加载逻辑。"
        exit 1
    fi

    echo "官方自动识别逻辑检查通过。"

    # -------------------------------------------------------------------------
    # 精确替换官方 H69K 判断条件
    #
    # 只替换这一行。
    #
    # 原：
    # if test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then
    #
    # 新：
    # if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then
    #     echo h68k
    #
    # elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then
    #
    # 重点：
    # H68K 不再次 setenv hwflag 1。
    #
    # 因为进入 ADC 判断之前，官方代码已经：
    #
    # setenv hwflag 1
    #
    # 因此 ADC 不命中新 H68K 范围时，仍然保留原来的默认值。
    # -------------------------------------------------------------------------

    echo
    echo "== 应用 H68K ADC7 自动识别补丁 =="

    python3 - "$BOOT_SCRIPT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

official = 'if test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then'

replacement = '''if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then
\t\t\techo h68k

\t\t# 保留官方 H69K 判断
\t\telif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then'''

count = text.count(official)

if count != 1:
    print(
        f"ERROR: 官方 H69K ADC 判断条件出现 {count} 次，"
        "预期必须恰好 1 次。"
    )
    print("为了避免误修改错误版本，DIY2 已停止。")
    sys.exit(1)

text = text.replace(official, replacement, 1)

path.write_text(text)

print("H68K 自动识别补丁应用成功。")
PY

fi

# --- 4.5 验证 H68K 自动识别 ---

echo
echo "== 验证 H68K 自动识别逻辑 =="

# 补丁标记
if ! grep -q 'H68K 当前实机 ADC7' "$BOOT_SCRIPT"; then
    echo "ERROR: H68K 补丁标记不存在。"
    exit 1
fi

# H68K ADC 范围
if ! grep -Fq \
    'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H68K ADC 770~795 判断不存在。"
    exit 1
fi

# H68K 输出
if ! grep -q 'echo h68k' "$BOOT_SCRIPT"; then
    echo "ERROR: H68K 识别逻辑不存在。"
    exit 1
fi

# H69K 输出
if ! grep -q 'echo h69k' "$BOOT_SCRIPT"; then
    echo "ERROR: H69K 识别逻辑不存在。"
    exit 1
fi

# H69K hwflag
if ! grep -q 'setenv hwflag 10' "$BOOT_SCRIPT"; then
    echo "ERROR: H69K hwflag=10 不存在。"
    exit 1
fi

# GPIO143
if ! grep -q 'gpio input 143' "$BOOT_SCRIPT"; then
    echo "ERROR: GPIO143 逻辑被破坏。"
    exit 1
fi

# ADC7
if ! grep -Fq \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: ADC7 逻辑被破坏。"
    exit 1
fi

# 默认 hwflag=1
#
# 注意这里不是要求 H68K 分支里面重新设置 hwflag=1，
# 而是确认 GPIO143 -> setenv hwflag 1 这一原始逻辑仍然存在。
if ! grep -q 'setenv hwflag 1' "$BOOT_SCRIPT"; then
    echo "ERROR: 原始默认 hwflag=1 逻辑不存在。"
    exit 1
fi

# hwflag -> DTB
if ! grep -Fq \
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: hwflag -> DTB 加载逻辑不存在。"
    exit 1
fi

# --- H68K / H69K 顺序检查 ---

H68K_LINE="$(
    grep -n -F \
        'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
        "$BOOT_SCRIPT" |
    head -n 1 |
    cut -d: -f1
)"

H69K_LINE="$(
    grep -n -F \
        'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
        "$BOOT_SCRIPT" |
    head -n 1 |
    cut -d: -f1
)"

if [ -z "$H68K_LINE" ] || [ -z "$H69K_LINE" ]; then
    echo "ERROR: 无法确定 H68K/H69K 判断顺序。"
    exit 1
fi

if [ "$H68K_LINE" -ge "$H69K_LINE" ]; then
    echo "ERROR: H68K 判断没有位于 H69K 判断之前。"
    exit 1
fi

# --- 检查 H68K 分支没有重新覆盖默认值 ---

H68K_BLOCK="$(
    sed -n \
        "${H68K_LINE},${H69K_LINE}p" \
        "$BOOT_SCRIPT"
)"

if printf '%s\n' "$H68K_BLOCK" | grep -q 'setenv hwflag 1'; then
    echo "ERROR: H68K 新增分支内部重新设置了 hwflag=1。"
    echo "为了保留原有默认值逻辑，停止 DIY2。"
    exit 1
fi

echo
echo "===== H68K/H69K 自动识别代码 ====="

grep -n -A28 -B8 \
    'H68K 当前实机 ADC7' \
    "$BOOT_SCRIPT" || true

echo
echo "✓ GPIO143 检测逻辑保留"
echo "✓ GPIO143 -> hwflag=1 默认值保留"
echo "✓ H68K ADC7 770~795 -> 保持默认 hwflag=1"
echo "✓ H68K 分支不会重新覆盖 hwflag"
echo "✓ ADC 不命中 H68K 范围时保留原默认值"
echo "✓ H69K 官方判断保留"
echo "✓ H69K -> hwflag=10"
echo "✓ hwflag -> rockchip${hwflag}.dtb 保留"

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
   grep -q 'H68K 当前实机 ADC7' "$BOOT_SCRIPT" 2>/dev/null; then

    echo "  ✓ 已应用"
    echo "  ✓ GPIO143 -> 默认 hwflag=1"
    echo "  ✓ ADC7 770~795 -> H68K，保持 hwflag=1"
    echo "  ✓ ADC 未命中 H68K 范围 -> 保留原默认值"
    echo "  ✓ 原 H69K 判断 -> hwflag=10"
    echo "  ✓ GPIO143 判断保留"

else

    echo "  ⚠ 未检测到 H68K 自动识别补丁"

fi

echo
echo "== DIY2 OK =="
