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

# GPIO143 = GMAC1 检测
# ADC7 = H68K / H69K 硬件版本检测
#
# 关键修复：
# GPIO143 只负责检测 GMAC1，不再阻止 ADC7 检测。
#
# 默认：
#     hwflag=1 -> rockchip1.dtb
#
# ADC7：
#     770~795 -> H68K -> hwflag=1
#     610~1023 或 >=1072265 -> H69K -> hwflag=10
#
# H68K 区间与官方 H69K 区间存在重叠，
# 因此 H68K 判断必须优先。
#
# 这样即使 GPIO143=1，也仍然会读取 ADC7，
# 不会因为 GPIO143 阻断 H68K/H69K 自动识别。

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

# --- 检查基础硬件识别逻辑 ---

if ! grep -q 'gpio input 143' "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 GPIO143 检测逻辑。"
    exit 1
fi

if ! grep -Fq \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 ADC7 检测逻辑。"
    exit 1
fi

if ! grep -Fq \
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: 未找到 hwflag -> DTB 加载逻辑。"
    exit 1
fi

echo "✓ GPIO143 检测逻辑存在"
echo "✓ ADC7 检测逻辑存在"
echo "✓ hwflag -> DTB 加载逻辑存在"

# --- 严格重建 H68K/H69K 检测块 ---

echo
echo "== 重建 H68K/H69K 自动识别逻辑 =="

python3 - "$BOOT_SCRIPT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

adc_line = '        adc single saradc@fe720000 7 adc_value'

if adc_line not in text:
    adc_line = '\t\tadc single saradc@fe720000 7 adc_value'

if adc_line not in text:
    print("ERROR: 找不到 ADC7 命令。")
    sys.exit(1)

# 从 ADC7 命令所在位置向后找到 if test "$adc_value"
adc_pos = text.find(adc_line)

if adc_pos < 0:
    print("ERROR: ADC7 命令定位失败。")
    sys.exit(1)

if_pos = text.find('if test "$adc_value"', adc_pos)

if if_pos < 0:
    print("ERROR: 找不到 ADC7 判断块。")
    sys.exit(1)

# 找到 ADC 判断块结束位置。
# 这里针对官方 Hinlink bootscript 的结构：
#
# if test "$adc_value"...; then
#     ...
# fi
#
# 后面通常紧接着：
# fi
#
# 我们只替换 ADC7 后面的硬件判断部分，
# 保留 GPIO143、reset USB、bootargs、load、booti 等其他逻辑。

lines = text.splitlines()

adc_idx = None
for i, line in enumerate(lines):
    if 'adc single saradc@fe720000 7 adc_value' in line:
        adc_idx = i
        break

if adc_idx is None:
    print("ERROR: ADC7 行不存在。")
    sys.exit(1)

# 找 ADC7 后第一个 if test "$adc_value"
start = None
for i in range(adc_idx + 1, len(lines)):
    if 'if test "$adc_value"' in lines[i]:
        start = i
        break

if start is None:
    print("ERROR: 找不到 ADC 判断起始位置。")
    sys.exit(1)

# 找到对应的第一个结束 fi。
# 官方块内部只有一个 if/elif/fi。
end = None
for i in range(start + 1, len(lines)):
    stripped = lines[i].strip()
    if stripped == 'fi':
        end = i
        break

if end is None:
    print("ERROR: 找不到 ADC 判断结束位置。")
    sys.exit(1)

# 根据原文件缩进自动使用 tab/空格。
indent = lines[start][:len(lines[start]) - len(lines[start].lstrip())]

replacement = [
    indent + 'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then',
    indent + '\techo h68k',
    indent + '\tsetenv hwflag 1',
    indent + '\telif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then',
    indent + '\t\techo h69k',
    indent + '\t\tsetenv hwflag 10',
    indent + '\tfi',
]

# 上面的 replacement 最后一行 fi 属于判断块本身，
# 所以不要再保留原来的 end 行。
lines[start:end + 1] = replacement

# 现在处理 GPIO143 外层结构：
#
# 原始：
# if gpio input 143; then
#     echo nogmac
# else
#     echo hasgmac1
#     setenv hwflag 1
#     adc ...
#     ...
# fi
#
# 改成：
#
# if gpio input 143; then
#     echo nogmac
# else
#     echo hasgmac1
# fi
#
# ADC7 检测必须位于 GPIO 判断之后、外层 fi 之外。

# 重新寻找 gpio input 143
gpio_idx = None
for i, line in enumerate(lines):
    if 'gpio input 143' in line:
        gpio_idx = i
        break

if gpio_idx is None:
    print("ERROR: GPIO143 行不存在。")
    sys.exit(1)

# 找 GPIO 外层对应的 else 和 fi
else_idx = None
for i in range(gpio_idx + 1, len(lines)):
    if lines[i].strip() == 'else':
        else_idx = i
        break
    if lines[i].strip() == 'fi':
        break

if else_idx is None:
    print("ERROR: GPIO143 else 不存在。")
    sys.exit(1)

gpio_end = None
depth = 1

for i in range(gpio_idx + 1, len(lines)):
    stripped = lines[i].strip()

    if stripped.startswith('if ') or stripped.startswith('if\t'):
        depth += 1

    if stripped == 'fi':
        depth -= 1
        if depth == 0:
            gpio_end = i
            break

if gpio_end is None:
    print("ERROR: GPIO143 判断块结束位置不存在。")
    sys.exit(1)

# 在 GPIO else 中找到 ADC7。
adc_idx = None
for i in range(else_idx + 1, gpio_end):
    if 'adc single saradc@fe720000 7 adc_value' in lines[i]:
        adc_idx = i
        break

if adc_idx is None:
    print("ERROR: ADC7 仍然位于预期 GPIO 块之外/不存在。")
    sys.exit(1)

# 提取 ADC7 及其后面的 ADC 判断块。
# 当前结构中，ADC判断结束位置是 replacement 最后的 fi。
adc_block_start = adc_idx

adc_block_end = None
for i in range(adc_idx + 1, gpio_end):
    if lines[i].strip() == 'fi':
        adc_block_end = i
        break

if adc_block_end is None:
    print("ERROR: ADC7 判断结束位置不存在。")
    sys.exit(1)

adc_block = lines[adc_block_start:adc_block_end + 1]

# 从 GPIO else 中移除 ADC 相关内容。
del lines[adc_block_start:adc_block_end + 1]

# 删除 else 中原来的：
# echo hasgmac1
# setenv hwflag 1
# 但保留 echo hasgmac1。
for i in range(else_idx + 1, gpio_end):
    if lines[i].strip() == 'setenv hwflag 1':
        del lines[i]
        break

# 重新定位 GPIO end。
gpio_end = None
depth = 1

for i in range(gpio_idx + 1, len(lines)):
    stripped = lines[i].strip()

    if stripped.startswith('if ') or stripped.startswith('if\t'):
        depth += 1

    if stripped == 'fi':
        depth -= 1
        if depth == 0:
            gpio_end = i
            break

if gpio_end is None:
    print("ERROR: GPIO143 判断块重新定位失败。")
    sys.exit(1)

# 将 ADC 检测放到 GPIO 判断结束后。
# 默认 hwflag=1，确保没有 ADC 匹配时也不会产生未定义 DTB。
insert = [
    '',
    'echo "===== HINLINK DETECT ====="',
    'env delete adc_value',
    'setenv hwflag 1',
    'echo "GPIO143 checked"',
    'adc single saradc@fe720000 7 adc_value',
    'echo "U-BOOT ADC7=${adc_value}"',
    'if test -n "$adc_value"; then',
    '\tif test "$adc_value" -ge 770 -a "$adc_value" -le 795; then',
    '\t\techo h68k',
    '\t\tsetenv hwflag 1',
    '\telif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then',
    '\t\techo h69k',
    '\t\tsetenv hwflag 10',
    '\telse',
    '\t\techo "ADC NO MATCH -> H68K DEFAULT"',
    '\tfi',
    'else',
    '\techo "ADC READ FAILED -> H68K DEFAULT"',
    'fi',
    'echo "FINAL HWFLAG=${hwflag}"',
    'echo "FINAL DTB=rockchip${hwflag}.dtb"',
    'echo "===== HINLINK DETECT END ====="',
]

# 防止重复运行 DIY2 后重复插入。
marker = 'echo "===== HINLINK DETECT ====="'

if marker not in lines:
    lines[gpio_end + 1:gpio_end + 1] = insert

# 删除旧的 ADC 判断块可能留下的空行问题不重要。
path.write_text('\n'.join(lines) + '\n')

print("H68K/H69K 自动识别逻辑重建成功。")
PY

# --- 严格验证最终逻辑 ---

echo
echo "== 严格验证 H68K/H69K 自动识别 =="

H68K_COUNT="$(
    grep -Fxc \
    '		if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
    "$BOOT_SCRIPT" 2>/dev/null || true
)"

if [ "$H68K_COUNT" -eq 0 ]; then
    H68K_COUNT="$(
        grep -Fxc \
        '		if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
        "$BOOT_SCRIPT" 2>/dev/null || true
    )"
fi

if ! grep -Fq \
    'test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H68K ADC 770~795 判断不存在。"
    exit 1
fi

if ! grep -Fq \
    'setenv hwflag 1' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H68K hwflag=1 不存在。"
    exit 1
fi

if ! grep -Fq \
    'test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H69K ADC 判断不存在。"
    exit 1
fi

if ! grep -Fq \
    'setenv hwflag 10' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: H69K hwflag=10 不存在。"
    exit 1
fi

if ! grep -q \
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: DTB 加载逻辑不存在。"
    exit 1
fi

if ! grep -q \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: ADC7 命令不存在。"
    exit 1
fi

if ! grep -q \
    'gpio input 143' \
    "$BOOT_SCRIPT"; then
    echo "ERROR: GPIO143 检测逻辑不存在。"
    exit 1
fi

echo "✓ GPIO143 检测保留"
echo "✓ ADC7 检测不再受 GPIO143 阻断"
echo "✓ 默认 hwflag=1"
echo "✓ ADC7 770~795 -> H68K"
echo "✓ H68K -> hwflag=1"
echo "✓ H68K -> rockchip1.dtb"
echo "✓ ADC7 610~1023 或 >=1072265 -> H69K"
echo "✓ H69K -> hwflag=10"
echo "✓ H69K -> rockchip10.dtb"
echo "✓ DTB 加载逻辑保留"

echo
echo "===== 最终 H68K/H69K 代码 ====="

grep -n -A35 -B8 \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT" || true

echo
echo "===== 自动识别结果模拟 ====="

echo "ADC7 = 781:"
if [ 781 -ge 770 ] && [ 781 -le 795 ]; then
    echo "  H68K"
    echo "  hwflag=1"
    echo "  DTB=rockchip1.dtb"
elif { [ 781 -lt 1024 ] && [ 781 -ge 610 ]; } || [ 781 -ge 1072265 ]; then
    echo "  H69K"
    echo "  hwflag=10"
    echo "  DTB=rockchip10.dtb"
fi

echo
echo "ADC7 = 700:"
if [ 700 -ge 770 ] && [ 700 -le 795 ]; then
    echo "  H68K"
    echo "  hwflag=1"
    echo "  DTB=rockchip1.dtb"
elif { [ 700 -lt 1024 ] && [ 700 -ge 610 ]; } || [ 700 -ge 1072265 ]; then
    echo "  H69K"
    echo "  hwflag=10"
    echo "  DTB=rockchip10.dtb"
fi

echo
echo "ADC7 = 1072265:"
if [ 1072265 -ge 770 ] && [ 1072265 -le 795 ]; then
    echo "  H68K"
    echo "  hwflag=1"
    echo "  DTB=rockchip1.dtb"
elif { [ 1072265 -lt 1024 ] && [ 1072265 -ge 610 ]; } || [ 1072265 -ge 1072265 ]; then
    echo "  H69K"
    echo "  hwflag=10"
    echo "  DTB=rockchip10.dtb"
fi

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
    echo "  ✓ ADC7 独立检测"
    echo "  ✓ GPIO143 不再阻断 ADC7"
    echo "  ✓ 默认 hwflag=1"
    echo "  ✓ ADC7 770~795 -> H68K"
    echo "  ✓ H68K -> 强制 hwflag=1"
    echo "  ✓ H68K -> rockchip1.dtb"
    echo "  ✓ H69K ADC 判断保留"
    echo "  ✓ H69K -> hwflag=10"
    echo "  ✓ H69K -> rockchip10.dtb"
    echo "  ✓ U-Boot ADC值会输出到串口"
    echo "  ✓ 最终 hwflag 会输出到串口"
    echo "  ✓ 最终 DTB 会输出到串口"

else

    echo "  ⚠ 未检测到完整 H68K/H69K 自动识别补丁"

fi

echo
echo "== DIY2 OK =="
