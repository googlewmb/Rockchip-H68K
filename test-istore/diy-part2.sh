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

# 保留官方检测结构：
#
# GPIO143
#   └─ hasgmac1
#       └─ ADC7
#           ├─ H68K 770~795 -> hwflag 1
#           └─ H69K 官方范围 -> hwflag 10
#
# 这里只修改 ADC7 的 H69K 判断，
# 不移动 GPIO143，不移动 ADC7，不重建外层结构。

if ! grep -Fq 'gpio input 143' "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 GPIO143 检测逻辑。"
    exit 1
fi

if ! grep -Fq 'adc single saradc@fe720000 7 adc_value' "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 ADC7 检测逻辑。"
    exit 1
fi

if ! grep -Fq 'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 hwflag -> DTB 加载逻辑。"
    exit 1
fi

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

official = 'if test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then'
h68k = 'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then'

# 已经是正确补丁：直接保持不变。
if h68k in text and official in text:
    h68k_pos = text.find(h68k)
    h69k_pos = text.find(official)

    if h68k_pos < h69k_pos:
        # 检查 H68K 分支附近确实设置 hwflag=1。
        block = text[h68k_pos:h69k_pos]

        if 'echo h68k' in block and 'setenv hwflag 1' in block:
            print("H68K/H69K 补丁已经存在，跳过修改。")
            sys.exit(0)

# 如果存在 H68K 条件但结构不正确，停止，而不是盲目重写。
if h68k in text:
    print("ERROR: 检测到 H68K 判断，但结构不是预期状态。")
    print("为了避免破坏 bootscript，停止修改。")
    sys.exit(1)

matches = list(re.finditer(
    r'(?m)^([ \t]*)if test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 -o "\$adc_value" -ge 1072265; then[ \t]*$',
    text
))

if len(matches) != 1:
    print(f"ERROR: 官方 H69K ADC 判断应恰好存在 1 次，实际发现 {len(matches)} 次。")
    sys.exit(1)

m = matches[0]
indent = m.group(1)

replacement = (
    f'{indent}if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then\n'
    f'{indent}\techo h68k\n'
    f'{indent}\tsetenv hwflag 1\n'
    f'{indent}elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then'
)

text = text[:m.start()] + replacement + text[m.end():]

path.write_text(text)

print("H68K/H69K ADC 判断补丁应用成功。")
PY

# --- 严格验证最终 bootscript ---

echo
echo "== 严格验证 H68K/H69K 自动识别 =="

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

gpio = 'gpio input 143'
adc = 'adc single saradc@fe720000 7 adc_value'
dtb = 'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb'

h68k = 'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then'
h69k = 'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then'

errors = []

if text.count(gpio) != 1:
    errors.append(f"GPIO143 检测次数异常: {text.count(gpio)}")

if text.count(adc) != 1:
    errors.append(f"ADC7 检测次数异常: {text.count(adc)}")

if text.count(h68k) != 1:
    errors.append(f"H68K 判断次数异常: {text.count(h68k)}")

if text.count(h69k) != 1:
    errors.append(f"H69K 判断次数异常: {text.count(h69k)}")

if text.count('echo h68k') != 1:
    errors.append(f"echo h68k 次数异常: {text.count('echo h68k')}")

if text.count('echo h69k') != 1:
    errors.append(f"echo h69k 次数异常: {text.count('echo h69k')}")

if text.count('setenv hwflag 1') < 1:
    errors.append("缺少 H68K hwflag=1")

if text.count('setenv hwflag 10') != 1:
    errors.append(f"H69K hwflag=10 次数异常: {text.count('setenv hwflag 10')}")

if text.count(dtb) != 1:
    errors.append(f"DTB 加载次数异常: {text.count(dtb)}")

h68k_pos = text.find(h68k)
h69k_pos = text.find(h69k)

if h68k_pos < 0 or h69k_pos < 0 or h68k_pos >= h69k_pos:
    errors.append("H68K 判断没有位于 H69K 判断之前")

# 最重要的结构检查：
# ADC7 必须位于 GPIO143 的 else 分支内部。
gpio_pos = text.find(gpio)

if gpio_pos >= 0:
    else_pos = text.find('else', gpio_pos)
    adc_pos = text.find(adc, gpio_pos)

    if else_pos < 0 or adc_pos < 0 or adc_pos < else_pos:
        errors.append("ADC7 不在 GPIO143 的 else 分支之后")

    # ADC7 必须在 GPIO 外层 fi 之前。
    if adc_pos >= 0:
        before_adc = text[:adc_pos]

        depth = 0
        for line in before_adc.splitlines():
            s = line.strip()

            if re.match(r'^if\b', s):
                depth += 1
            elif s == 'fi':
                depth -= 1

        if depth < 1:
            errors.append("ADC7 可能已经移出 GPIO143 外层 if")

if errors:
    print("ERROR: bootscript 验证失败")
    for e in errors:
        print(" - " + e)
    sys.exit(1)

print("✓ GPIO143 检测保留")
print("✓ ADC7 仍位于 GPIO143 -> hasgmac1 分支")
print("✓ H68K 770~795 判断存在")
print("✓ H68K 判断位于 H69K 判断之前")
print("✓ H68K -> hwflag=1")
print("✓ H69K 官方判断保留")
print("✓ H69K -> hwflag=10")
print("✓ DTB 加载逻辑保留")
print("✓ bootscript 结构验证通过")
PY

echo
echo "===== 最终 HINLINK bootscript 检查 ====="

grep -n -A18 -B6 \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT" || true

echo
echo "===== ADC 自动识别模拟 ====="

for adc_value in 781 783 700 1072265; do
    echo
    echo "ADC7 = $adc_value"

    if [ "$adc_value" -ge 770 ] && [ "$adc_value" -le 795 ]; then
        echo "  H68K"
        echo "  hwflag=1"
        echo "  DTB=rockchip1.dtb"
    elif { [ "$adc_value" -lt 1024 ] && [ "$adc_value" -ge 610 ]; } || [ "$adc_value" -ge 1072265 ]; then
        echo "  H69K"
        echo "  hwflag=10"
        echo "  DTB=rockchip10.dtb"
    else
        echo "  无匹配 -> 保持官方默认 hwflag=1"
        echo "  DTB=rockchip1.dtb"
    fi
done

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

# --- 12.8 替换 Golang 为 27.x ---

if [ -d feeds/packages/lang/golang ]; then
    echo "删除旧 Golang"
    rm -rf feeds/packages/lang/golang
fi

git clone \
    -b 27.x \
    --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang

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

if [ -n "$BOOT_SCRIPT" ] &&
   grep -Fq \
   'test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
   "$BOOT_SCRIPT" 2>/dev/null &&
   grep -Fq \
   'setenv hwflag 1' \
   "$BOOT_SCRIPT" 2>/dev/null &&
   grep -Fq \
   'test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
   "$BOOT_SCRIPT" 2>/dev/null &&
   grep -Fq \
   'setenv hwflag 10' \
   "$BOOT_SCRIPT" 2>/dev/null &&
   grep -Fq \
   'adc single saradc@fe720000 7 adc_value' \
   "$BOOT_SCRIPT" 2>/dev/null &&
   grep -Fq \
   'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
   "$BOOT_SCRIPT" 2>/dev/null; then

    echo "  ✓ 已应用"
    echo "  ✓ GPIO143 检测保留"
    echo "  ✓ ADC7 保持在 GPIO143 -> hasgmac1 分支"
    echo "  ✓ 不重构官方 GPIO143 检测结构"
    echo "  ✓ 默认 hwflag=1"
    echo "  ✓ ADC7 770~795 -> H68K"
    echo "  ✓ H68K -> hwflag=1"
    echo "  ✓ H68K -> rockchip1.dtb"
    echo "  ✓ H69K ADC 判断保留"
    echo "  ✓ H69K -> hwflag=10"
    echo "  ✓ H69K -> rockchip10.dtb"
    echo "  ✓ DTB 加载逻辑保留"

else

    echo "  ⚠ 未检测到完整 H68K/H69K 自动识别补丁"

fi

echo
echo "== DIY2 OK =="
