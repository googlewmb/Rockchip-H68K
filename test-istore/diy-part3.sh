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

TOPDIR="${TOPDIR:-$(pwd)}"
cd "$TOPDIR"

echo "== DIY2 开始 =="

###############################################################################
# 0. 基础检查
###############################################################################

echo "== 检查 OpenWrt 源码目录 =="

[ -d feeds ] || {
    echo "ERROR: 找不到 feeds 目录"
    exit 1
}

[ -d package ] || {
    echo "ERROR: 找不到 package 目录"
    exit 1
}

###############################################################################
# 1. feeds
###############################################################################

echo "== 更新 feeds =="

./scripts/feeds update -a
./scripts/feeds install -a

###############################################################################
# 1.1 PassWall
###############################################################################

echo "== 安装 PassWall =="

rm -rf \
    feeds/packages/net/xray-core \
    feeds/packages/net/v2ray-geodata \
    feeds/packages/net/sing-box \
    feeds/packages/net/chinadns-ng \
    feeds/packages/net/dns2socks \
    feeds/packages/net/hysteria \
    feeds/packages/net/ipt2socks \
    feeds/packages/net/microsocks \
    feeds/packages/net/naiveproxy \
    feeds/packages/net/shadowsocks-rust \
    feeds/packages/net/shadowsocksr-libev \
    feeds/packages/net/simple-obfs \
    feeds/packages/net/tcping \
    feeds/packages/net/v2ray-plugin \
    feeds/packages/net/xray-plugin \
    feeds/packages/net/geoview \
    feeds/packages/net/shadow-tls

rm -rf feeds/luci/applications/luci-app-passwall

rm -rf package/passwall-packages
rm -rf package/passwall-luci

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git \
    package/passwall-packages

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall.git \
    package/passwall-luci

###############################################################################
# 2. package/myapp 第三方软件包检查
###############################################################################

echo "== 检查 package/myapp =="

package_entry_exists() {
    local pkg="$1"

    find package/myapp \
        -type f \
        -name Makefile \
        -exec grep -qE "^define Package/${pkg}([[:space:]]|$)" {} \; \
        -print -quit 2>/dev/null |
        grep -q .
}

remove_package_entry() {
    local pkg="$1"
    local file

    file="$(
        find package/myapp \
            -type f \
            -name Makefile \
            -exec grep -lE "^define Package/${pkg}([[:space:]]|$)" {} \; \
            2>/dev/null |
            head -n1
    )"

    if [ -n "$file" ]; then
        echo "package/myapp: $pkg -> $file"
    fi
}

package_makefile() {
    local pkg="$1"

    find package/myapp \
        -type f \
        -name Makefile \
        -exec grep -lE "^define Package/${pkg}([[:space:]]|$)" {} \; \
        2>/dev/null |
        head -n1
}

is_enabled() {
    local pkg="$1"

    grep -qE "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null
}

get_package_version() {
    local pkg="$1"
    local file

    file="$(package_makefile "$pkg")"

    [ -n "$file" ] || return 0

    sed -nE \
        's/^PKG_VERSION[:?]?=([0-9A-Za-z._+-]+).*/\1/p' \
        "$file" |
        head -n1
}

if [ -d package/myapp ]; then
    while IFS= read -r file; do
        [ -n "$file" ] || continue

        pkg="$(
            sed -nE \
                's/^define Package\/([^[:space:]]+).*/\1/p' \
                "$file" |
                head -n1
        )"

        [ -n "$pkg" ] || continue

        echo "发现 package/myapp: $pkg"

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print 2>/dev/null
    )
fi

###############################################################################
# 3. SmartDNS Rust 依赖修复
###############################################################################

echo "== SmartDNS Rust 依赖检查 =="

find package \
    -type f \
    -path '*/smartdns*/Makefile' \
    -print 2>/dev/null |
while read -r file; do
    if grep -q 'rustc' "$file" 2>/dev/null; then
        echo "检查: $file"

        sed -i \
            's/PKG_BUILD_DEPENDS:=.*rust.*/PKG_BUILD_DEPENDS:=rust\/host/' \
            "$file" 2>/dev/null || true
    fi
done

###############################################################################
# 3.1 LuCI 中文包检查
###############################################################################

echo "== LuCI 中文包检查 =="

find package feeds \
    -type f \
    \( -name 'Makefile' -o -name '*.mk' \) \
    -print 2>/dev/null |
while read -r file; do
    grep -q 'luci-i18n-' "$file" 2>/dev/null &&
        echo "检查 LuCI: $file" || true
done

###############################################################################
# 3.2 Conntrack
###############################################################################

echo "== Conntrack 检查 =="

if grep -q '^CONFIG_PACKAGE_conntrack=y$' .config 2>/dev/null; then
    echo "✓ conntrack 已启用"
else
    echo "INFO: conntrack 未直接启用"
fi

###############################################################################
# 3.3 Wi-Fi 自动启用
###############################################################################

echo "== Wi-Fi 自动启用 =="

mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-wifi-enable <<'EOF'
#!/bin/sh

[ -d /sys/class/ieee80211 ] || exit 0

uci -q set wireless.radio0.disabled='0'
uci -q set wireless.radio1.disabled='0'
uci commit wireless
exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-wifi-enable

###############################################################################
# 4. H68K U-Boot 自动 DTB 识别
###############################################################################

echo "== H68K U-Boot 自动 DTB 识别修复 =="

BOOT_SCRIPT="target/linux/rockchip/image/legacy/rk3568-hinlink.bootscript"

[ -f "$BOOT_SCRIPT" ] || {
    echo "ERROR: 找不到 $BOOT_SCRIPT"
    exit 1
}

grep -Fq 'gpio input 143' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 GPIO143 检测逻辑"
    exit 1
}

grep -Fq 'adc single saradc@fe720000 7 adc_value' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 ADC7 命令"
    exit 1
}

grep -Fq 'rockchip${hwflag}.dtb' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 hwflag -> DTB 加载逻辑"
    exit 1
}

echo "✓ GPIO143 检测逻辑存在"
echo "✓ ADC7 检测逻辑存在"
echo "✓ hwflag -> DTB 加载逻辑存在"

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

GPIO_PATTERN = (
    r'^[ \t]*if[ \t]+gpio[ \t]+input[ \t]+143'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

H68K_PATTERN = (
    r'^[ \t]*if[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-ge[ \t]+770[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-le[ \t]+795'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

H69K_IF_PATTERN = (
    r'^[ \t]*if[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-lt[ \t]+1024[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-ge[ \t]+610[ \t]+'
    r'-o[ \t]+"\$adc_value"[ \t]+-ge[ \t]+1072265'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

H69K_ELIF_PATTERN = (
    r'^[ \t]*elif[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-lt[ \t]+1024[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-ge[ \t]+610[ \t]+'
    r'-o[ \t]+"\$adc_value"[ \t]+-ge[ \t]+1072265'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

lines = text.splitlines()

gpio = [i for i, x in enumerate(lines)
        if re.match(GPIO_PATTERN, x)]

adc = [i for i, x in enumerate(lines)
       if 'adc single saradc@fe720000 7 adc_value' in x]

if len(gpio) != 1:
    print(f"ERROR: GPIO143 检测数量异常: {len(gpio)}")
    sys.exit(1)

if len(adc) != 1:
    print(f"ERROR: ADC7 检测数量异常: {len(adc)}")
    sys.exit(1)

gpio_pos = gpio[0]
adc_pos = adc[0]

if adc_pos <= gpio_pos:
    print("ERROR: ADC7 不在 GPIO143 检测之后")
    sys.exit(1)

# 已经正确修改过
h68k = [i for i, x in enumerate(lines)
        if re.match(H68K_PATTERN, x)]

h69k_if = [i for i, x in enumerate(lines)
           if re.match(H69K_IF_PATTERN, x)]

h69k_elif = [i for i, x in enumerate(lines)
             if re.match(H69K_ELIF_PATTERN, x)]

if len(h68k) == 1 and len(h69k_elif) == 1 and len(h69k_if) == 0:
    h68k_pos = h68k[0]
    h69k_pos = h69k_elif[0]

    if not (gpio_pos < adc_pos < h68k_pos < h69k_pos):
        print("ERROR: H68K/H69K 判断顺序异常")
        sys.exit(1)

    region = lines[gpio_pos:h69k_pos + 8]
    region_text = "\n".join(region)

    if 'else' not in region_text:
        print("ERROR: ADC7 不在 GPIO143 else 分支中")
        sys.exit(1)

    if 'echo h68k' not in "\n".join(lines[h68k_pos:h69k_pos]):
        print("ERROR: H68K 分支缺少 echo h68k")
        sys.exit(1)

    if 'setenv hwflag 1' not in "\n".join(lines[h68k_pos:h69k_pos]):
        print("ERROR: H68K 分支缺少 hwflag=1")
        sys.exit(1)

    if 'echo h69k' not in "\n".join(lines[h69k_pos:]):
        print("ERROR: H69K 分支缺少 echo h69k")
        sys.exit(1)

    if 'setenv hwflag 10' not in "\n".join(lines[h69k_pos:]):
        print("ERROR: H69K 分支缺少 hwflag=10")
        sys.exit(1)

    print("✓ H68K/H69K 自动识别逻辑已经正确存在")
    sys.exit(0)

# 部分修改状态直接拒绝，避免重复插入
if h68k or h69k_elif:
    print("ERROR: bootscript 处于部分修改状态，拒绝自动重建")
    sys.exit(1)

if len(h69k_if) != 1:
    print(f"ERROR: 官方 H69K 判断数量异常: {len(h69k_if)}")
    sys.exit(1)

h69k_pos = h69k_if[0]

if h69k_pos <= adc_pos:
    print("ERROR: 官方 H69K 判断不在 ADC7 之后")
    sys.exit(1)

old = lines[h69k_pos]

indent = re.match(r'^([ \t]*)', old).group(1)

new = [
    indent + 'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then',
    indent + '\techo h68k',
    indent + '\tsetenv hwflag 1',
    indent + 'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then',
]

lines[h69k_pos:h69k_pos + 1] = new

path.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""))

print("✓ 已插入 H68K 770-795 判断")
print("✓ 已将原 H69K if 转换为 elif")
PY

###############################################################################
# 4.1 H68K bootscript 最终严格检查
###############################################################################

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()

def count(pattern):
    return len(re.findall(pattern, text, re.M))

gpio_pattern = (
    r'^[ \t]*if[ \t]+gpio[ \t]+input[ \t]+143'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

h68k_pattern = (
    r'^[ \t]*if[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-ge[ \t]+770[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-le[ \t]+795'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

h69k_elif_pattern = (
    r'^[ \t]*elif[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-lt[ \t]+1024[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-ge[ \t]+610[ \t]+'
    r'-o[ \t]+"\$adc_value"[ \t]+-ge[ \t]+1072265'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

if count(gpio_pattern) != 1:
    raise SystemExit("ERROR: GPIO143 数量不是 1")

if text.count('adc single saradc@fe720000 7 adc_value') != 1:
    raise SystemExit("ERROR: ADC7 数量不是 1")

if count(h68k_pattern) != 1:
    raise SystemExit("ERROR: H68K 判断数量不是 1")

if count(h69k_elif_pattern) != 1:
    raise SystemExit("ERROR: H69K elif 数量不是 1")

if 'echo h68k' not in text:
    raise SystemExit("ERROR: 缺少 echo h68k")

if 'setenv hwflag 1' not in text:
    raise SystemExit("ERROR: 缺少 hwflag=1")

if 'echo h69k' not in text:
    raise SystemExit("ERROR: 缺少 echo h69k")

if 'setenv hwflag 10' not in text:
    raise SystemExit("ERROR: 缺少 hwflag=10")

if text.count('load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb') != 1:
    raise SystemExit("ERROR: 动态 DTB 加载数量异常")

gpio_pos = next(
    i for i, x in enumerate(lines)
    if re.match(gpio_pattern, x)
)

adc_pos = next(
    i for i, x in enumerate(lines)
    if 'adc single saradc@fe720000 7 adc_value' in x
)

h68k_pos = next(
    i for i, x in enumerate(lines)
    if re.match(h68k_pattern, x)
)

h69k_pos = next(
    i for i, x in enumerate(lines)
    if re.match(h69k_elif_pattern, x)
)

if not (gpio_pos < adc_pos < h68k_pos < h69k_pos):
    raise SystemExit("ERROR: GPIO143/ADC7/H68K/H69K 顺序异常")

# ADC7 必须位于 GPIO143 的 else 分支
else_pos = None
depth = 0

for i in range(gpio_pos + 1, len(lines)):
    s = lines[i].strip()

    if re.match(r'^if\b', s):
        depth += 1
    elif s == 'fi':
        if depth == 0:
            break
        depth -= 1
    elif s == 'else' and depth == 0:
        else_pos = i
        break

if else_pos is None or not (else_pos < adc_pos):
    raise SystemExit("ERROR: ADC7 不在 GPIO143 else 分支")

print("✓ GPIO143 = 1")
print("✓ ADC7 = 1")
print("✓ H68K = 1")
print("✓ H69K elif = 1")
print("✓ hwflag 1/10 均存在")
print("✓ 动态 DTB 加载正确")
print("✓ GPIO143 -> ADC7 -> H68K -> H69K 顺序正确")
PY

###############################################################################
# 5. 生成最终配置
###############################################################################

echo "== 生成最终配置 =="

make defconfig >/dev/null

echo "✓ make defconfig 完成"

###############################################################################
# 6. Go 1.27
###############################################################################

echo "== Go 1.27 =="

if [ -d feeds/packages/lang/golang ]; then
    echo "删除旧 Golang"
    rm -rf feeds/packages/lang/golang
fi

git clone \
    -b 27.x \
    --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang

GO_VERSION="$(get_package_version golang)"

echo "Go 版本: ${GO_VERSION:-未知}"

###############################################################################
# 7. 最终源码检查
###############################################################################

echo "== 最终源码检查 =="

[ -d package/passwall-packages ] || {
    echo "ERROR: PassWall packages 不存在"
    exit 1
}

[ -d package/passwall-luci ] || {
    echo "ERROR: PassWall LuCI 不存在"
    exit 1
}

[ -d feeds/packages/lang/golang ] || {
    echo "ERROR: Golang feed 不存在"
    exit 1
}

[ -f "$BOOT_SCRIPT" ] || {
    echo "ERROR: H68K bootscript 不存在"
    exit 1
}

grep -Fq 'adc single saradc@fe720000 7 adc_value' "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 ADC7"
    exit 1
}

grep -Fq 'rockchip${hwflag}.dtb' "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少动态 DTB"
    exit 1
}

grep -Fq '770 -a "$adc_value" -le 795' "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H68K ADC 范围"
    exit 1
}

grep -Fq 'setenv hwflag 1' "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H68K hwflag=1"
    exit 1
}

grep -Fq 'setenv hwflag 10' "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H69K hwflag=10"
    exit 1
}

echo "✓ PassWall packages"
echo "✓ PassWall LuCI"
echo "✓ Golang 27.x"
echo "✓ H68K ADC7 自动识别"
echo "✓ H69K ADC 自动识别"
echo "✓ 动态 DTB 加载"

echo "== DIY2 OK =="
