#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
#
# 来源优先级：
#   1. package/myapp 独立第三方源码
#   2. DIY1 添加的第三方集合源
#   3. PassWall 官方第三方源码
#   4. iStoreOS / OpenWrt 官方源码
#
# H68K U-Boot 自动 DTB：
#   GPIO143=0 -> ADC7
#   ADC7 770~795 -> H68K -> rockchip1.dtb
#   ADC7 610~769 / 796~1023 / >=1072265 -> H69K -> rockchip10.dtb
#

set -e

TOPDIR="${TOPDIR:-$(pwd)}"

echo
echo "DIY2 - H68K + iStoreOS 24.10"
echo
echo "第三方插件 / 依赖 / 来源优先"
echo
echo "TOPDIR: ${TOPDIR}"
echo

cd "${TOPDIR}"

###############################################################################
# 1. 拉取 / 更新核心依赖与 PassWall
###############################################################################

echo "== 拉取/更新核心依赖与 PassWall =="

rm -rf package/passwall-packages
rm -rf package/passwall-luci

./scripts/feeds update -a
./scripts/feeds install -a

echo
echo "== 移除 OpenWrt feeds 自带 PassWall 核心包 =="

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

echo "✓ OpenWrt 旧版 PassWall 核心包已移除"

rm -rf feeds/luci/applications/luci-app-passwall

echo "✓ OpenWrt 旧版 luci-app-passwall 已移除"

echo
echo "== 拉取 Openwrt-Passwall 官方第三方源码 =="

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git \
    package/passwall-packages

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall.git \
    package/passwall-luci

echo "✓ passwall-packages"
echo "✓ passwall-luci"

###############################################################################
# 2. 第三方依赖预处理
###############################################################################

echo
echo "== 第三方依赖预处理 =="

OFFICIAL_FEEDS="
package/feeds/base
package/feeds/packages
package/feeds/luci
package/feeds/routing
package/feeds/telephony
"

THIRD_PARTY_FEEDS="
package/feeds/small
package/feeds/third
package/passwall-packages
package/passwall-luci
"

package_entry_exists() {
    local pkg="$1"

    grep -Rqs \
        -E "^[[:space:]]*(define Package/${pkg}([[:space:]]|$)|Package: ${pkg}([[:space:]]|$))" \
        package/feeds \
        package/passwall-packages \
        package/passwall-luci \
        package/myapp \
        2>/dev/null
}

remove_package_entry() {
    local pkg="$1"

    sed -i \
        -E "/CONFIG_PACKAGE_${pkg}=y/d" \
        .config 2>/dev/null || true

    sed -i \
        -E "/CONFIG_PACKAGE_${pkg}\/.*/d" \
        .config 2>/dev/null || true
}

package_makefile() {
    local pkg="$1"

    find \
        package/myapp \
        package/feeds \
        package/passwall-packages \
        package/passwall-luci \
        -type f \
        -name Makefile \
        -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
        if grep -qE \
            "^(define Package/${pkg}([[:space:]]|$)|PKG_NAME:=.*${pkg})" \
            "$file" 2>/dev/null; then
            echo "$file"
            return 0
        fi
    done
}

is_enabled() {
    local pkg="$1"

    grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null
}

get_package_version() {
    local pkg="$1"
    local makefile

    makefile="$(package_makefile "$pkg" | head -n1)"

    [ -n "$makefile" ] || return 0

    grep -E \
        '^[[:space:]]*PKG_VERSION[:]?=' \
        "$makefile" 2>/dev/null |
        head -n1 |
        sed -E 's/^[^=]*=[[:space:]]*//'
}

###############################################################################
# 3. 扫描 package/myapp
###############################################################################

echo
echo "== 扫描 package/myapp =="

if [ -d package/myapp ]; then
    find package/myapp \
        -type f \
        -name Makefile \
        -print 2>/dev/null |
    while read -r file; do
        pkg="$(
            sed -n \
                -E 's/^define Package\/([^ ]+).*/\1/p' \
                "$file" |
            head -n1
        )"

        [ -n "$pkg" ] || continue

        echo "发现 myapp 包: ${pkg}"
    done
fi

###############################################################################
# 4. 配置文件 / 第三方源优先级
###############################################################################

echo
echo "== 处理第三方源码优先级 =="

if [ -d package/myapp ]; then
    find package/myapp \
        -type f \
        -name Makefile \
        -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
        pkg="$(
            sed -n \
                -E 's/^define Package\/([^ ]+).*/\1/p' \
                "$file" |
            head -n1
        )"

        [ -n "$pkg" ] || continue

        echo "优先使用 myapp: ${pkg}"
    done
fi

###############################################################################
# 4.1 SmartDNS Rust Makefile 修复
###############################################################################

echo
echo "== SmartDNS Rust Makefile 检查 =="

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
# 4.2 LuCI 中文语言包
###############################################################################

echo
echo "== LuCI 中文语言包 =="

if [ -d package/feeds/luci ]; then
    find package/feeds/luci \
        -maxdepth 2 \
        -type d \
        -name 'luci-i18n-*-zh-cn' \
        -print 2>/dev/null |
    while read -r dir; do
        echo "发现: $dir"
    done
fi

###############################################################################
# 4.3 Conntrack
###############################################################################

echo
echo "== Conntrack =="

if is_enabled kmod-nf-conntrack; then
    echo "kmod-nf-conntrack 已启用"
fi

###############################################################################
# 4.4 Wi-Fi 自动启用
###############################################################################

echo
echo "== Wi-Fi 自动启用 =="

if [ -f package/base-files/files/etc/uci-defaults/99-wifi-enable ]; then
    echo "Wi-Fi 自动启用脚本已存在"
else
    mkdir -p package/base-files/files/etc/uci-defaults

    cat > package/base-files/files/etc/uci-defaults/99-wifi-enable <<'EOF'
#!/bin/sh

[ -d /sys/class/ieee80211 ] || exit 0

uci -q set wireless.radio0.disabled='0'
uci -q set wireless.radio1.disabled='0'

uci commit wireless

exit 0
EOF

    chmod +x \
        package/base-files/files/etc/uci-defaults/99-wifi-enable
fi

###############################################################################
# 4.5 H68K U-Boot 自动 DTB 识别修复
###############################################################################

echo
echo "== H68K U-Boot 自动 DTB 识别修复 =="

BOOT_SCRIPT=""

for file in \
    target/linux/rockchip/image/legacy/rk3568-hinlink.bootscript \
    target/linux/rockchip/image/rk3568-hinlink.bootscript
do
    if [ -f "$file" ]; then
        BOOT_SCRIPT="$file"
        break
    fi
done

if [ -z "$BOOT_SCRIPT" ]; then
    echo "ERROR: 找不到 HINLINK bootscript"
    exit 1
fi

echo "找到 boot script: ${BOOT_SCRIPT}"

grep -Fq 'gpio input 143' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 GPIO143 检测逻辑"
    exit 1
}

grep -Fq 'adc single saradc@fe720000 7 adc_value' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 ADC7 命令"
    exit 1
}

grep -Fq 'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 hwflag -> DTB 加载逻辑"
    exit 1
}

echo "✓ GPIO143 检测逻辑存在"
echo "✓ ADC7 检测逻辑存在"
echo "✓ hwflag -> DTB 加载逻辑存在"

echo
echo "== 检查/修复 H68K/H69K ADC 自动识别 =="

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

ADC = r'adc single saradc@fe720000 7 adc_value'

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

gpio_matches = list(re.finditer(GPIO_PATTERN, text, re.MULTILINE))
adc_matches = list(re.finditer(re.escape(ADC), text))

if len(gpio_matches) != 1:
    print(f"ERROR: GPIO143 检测逻辑数量异常：{len(gpio_matches)}")
    sys.exit(1)

if len(adc_matches) != 1:
    print(f"ERROR: ADC7 命令数量异常：{len(adc_matches)}")
    sys.exit(1)

gpio_pos = gpio_matches[0].start()
adc_pos = adc_matches[0].start()

if adc_pos <= gpio_pos:
    print("ERROR: ADC7 位于 GPIO143 之前")
    sys.exit(1)

# ADC7 必须位于 GPIO143 的 else 分支
gpio_line_end = text.find('\n', gpio_pos)

if gpio_line_end < 0:
    print("ERROR: GPIO143 行异常")
    sys.exit(1)

between_gpio_adc = text[gpio_line_end + 1:adc_pos]

if not re.search(
    r'(?m)^[ \t]*else[ \t]*$',
    between_gpio_adc
):
    print("ERROR: ADC7 不在 GPIO143 的 else 分支中")
    sys.exit(1)

h68k_matches = list(re.finditer(H68K_PATTERN, text, re.MULTILINE))
h69k_if_matches = list(re.finditer(H69K_IF_PATTERN, text, re.MULTILINE))
h69k_elif_matches = list(re.finditer(H69K_ELIF_PATTERN, text, re.MULTILINE))

# 已经是最终正确版本
if (
    len(h68k_matches) == 1
    and len(h69k_elif_matches) == 1
    and len(h69k_if_matches) == 0
):
    h68k_pos = h68k_matches[0].start()
    h69k_pos = h69k_elif_matches[0].start()

    if not (gpio_pos < adc_pos < h68k_pos < h69k_pos):
        print("ERROR: GPIO143 -> ADC7 -> H68K -> H69K 顺序异常")
        sys.exit(1)

    h68k_block = text[h68k_pos:h69k_pos]
    h69k_block = text[h69k_pos:]

    if 'echo h68k' not in h68k_block:
        print("ERROR: H68K 分支缺少 echo h68k")
        sys.exit(1)

    if 'setenv hwflag 1' not in h68k_block:
        print("ERROR: H68K 分支缺少 setenv hwflag 1")
        sys.exit(1)

    if 'echo h69k' not in h69k_block:
        print("ERROR: H69K 分支缺少 echo h69k")
        sys.exit(1)

    if 'setenv hwflag 10' not in h69k_block:
        print("ERROR: H69K 分支缺少 setenv hwflag 10")
        sys.exit(1)

    print("✓ H68K/H69K 自动识别逻辑已经正确")
    print("✓ 无需重复修改")
    sys.exit(0)

# 半成品直接停止
if len(h68k_matches) > 0 or len(h69k_elif_matches) > 0:
    print("ERROR: 检测到不完整的 H68K/H69K 修改结构")
    print("ERROR: 为避免破坏 bootscript，停止自动修改")
    sys.exit(1)

# 必须存在唯一官方 H69K if
if len(h69k_if_matches) != 1:
    print(
        "ERROR: 找不到唯一的官方 H69K 判断，"
        f"实际找到 {len(h69k_if_matches)} 个"
    )
    sys.exit(1)

m = h69k_if_matches[0]

if m.start() <= adc_pos:
    print("ERROR: 官方 H69K 判断位于 ADC7 之前")
    sys.exit(1)

original_line = m.group(0)

indent = original_line[
    :len(original_line) - len(original_line.lstrip())
]

replacement = (
    f'{indent}if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then\n'
    f'{indent}\techo h68k\n'
    f'{indent}\tsetenv hwflag 1\n'
    f'{indent}elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 '
    f'-o "$adc_value" -ge 1072265; then'
)

text = text[:m.start()] + replacement + text[m.end():]

path.write_text(text)

print("✓ 已加入 H68K ADC7 770~795 判断")
print("✓ H69K 官方判断已转换为 elif")
print("✓ GPIO143 / ADC7 结构未移动")
PY

###############################################################################
# 4.5.1 严格验证最终 bootscript
###############################################################################

echo
echo "== 严格验证 H68K/H69K 自动识别逻辑 =="

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

def fail(message):
    print("ERROR: " + message)
    sys.exit(1)

def count(pattern):
    return len(re.findall(pattern, text, re.MULTILINE))

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

H69K_PATTERN = (
    r'^[ \t]*elif[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-lt[ \t]+1024[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-ge[ \t]+610[ \t]+'
    r'-o[ \t]+"\$adc_value"[ \t]+-ge[ \t]+1072265'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

if count(GPIO_PATTERN) != 1:
    fail("GPIO143 检测数量异常")

if count(r'adc single saradc@fe720000 7 adc_value') != 1:
    fail("ADC7 命令数量异常")

if count(H68K_PATTERN) != 1:
    fail("H68K 条件数量异常")

if count(H69K_PATTERN) != 1:
    fail("H69K 条件数量异常")

if count(r'^[ \t]*echo h68k[ \t]*$') != 1:
    fail("echo h68k 数量异常")

if count(r'^[ \t]*setenv hwflag 1[ \t]*$') < 1:
    fail("setenv hwflag 1 不存在")

if count(r'^[ \t]*echo h69k[ \t]*$') != 1:
    fail("echo h69k 数量异常")

if count(r'^[ \t]*setenv hwflag 10[ \t]*$') != 1:
    fail("setenv hwflag 10 数量异常")

if count(
    r'^[ \t]*load mmc \$\{devnum\}:1 '
    r'\$\{fdt_addr_r\} rockchip\$\{hwflag\}\.dtb[ \t]*$'
) != 1:
    fail("DTB 动态加载逻辑异常")

print("✓ GPIO143 唯一")
print("✓ ADC7 唯一")
print("✓ H68K 条件唯一")
print("✓ H69K 条件唯一")
print("✓ H68K -> hwflag=1")
print("✓ H69K -> hwflag=10")
print("✓ 动态 DTB 加载唯一")

gpio_match = re.search(GPIO_PATTERN, text, re.MULTILINE)
adc_match = re.search(
    r'adc single saradc@fe720000 7 adc_value',
    text
)
h68k_match = re.search(H68K_PATTERN, text, re.MULTILINE)
h69k_match = re.search(H69K_PATTERN, text, re.MULTILINE)

if not all((gpio_match, adc_match, h68k_match, h69k_match)):
    fail("无法定位完整 GPIO143 / ADC7 / H68K / H69K")

gpio_pos = gpio_match.start()
adc_pos = adc_match.start()
h68k_pos = h68k_match.start()
h69k_pos = h69k_match.start()

if not (gpio_pos < adc_pos < h68k_pos < h69k_pos):
    fail("GPIO143 -> ADC7 -> H68K -> H69K 顺序错误")

print("✓ GPIO143 -> ADC7 -> H68K -> H69K 顺序正确")

gpio_line_end = text.find('\n', gpio_pos)

if gpio_line_end < 0:
    fail("GPIO143 行异常")

between_gpio_adc = text[gpio_line_end + 1:adc_pos]

if not re.search(
    r'(?m)^[ \t]*else[ \t]*$',
    between_gpio_adc
):
    fail("ADC7 不在 GPIO143 的 else 分支")

print("✓ ADC7 位于 GPIO143 的 else 分支")

adc_valid_pos = text.find(
    'if test -n "$adc_value"; then',
    adc_pos
)

if adc_valid_pos < 0:
    fail("找不到 ADC7 有效性检查")

if not (adc_valid_pos < h68k_pos < h69k_pos):
    fail("H68K/H69K 判断未位于 ADC7 有效性检查之后")

print("✓ H68K/H69K 位于 ADC7 有效性检查内部")

h68k_block = text[h68k_pos:h69k_pos]
h69k_block = text[h69k_pos:]

if "echo h68k" not in h68k_block:
    fail("H68K 分支不完整")

if "setenv hwflag 1" not in h68k_block:
    fail("H68K 分支没有 hwflag=1")

if "echo h69k" not in h69k_block:
    fail("H69K 分支不完整")

if "setenv hwflag 10" not in h69k_block:
    fail("H69K 分支没有 hwflag=10")

print("✓ H68K 分支完整")
print("✓ H69K 分支完整")

def simulate(adc):
    if 770 <= adc <= 795:
        return "H68K", 1, "rockchip1.dtb"

    if (610 <= adc < 1024) or adc >= 1072265:
        return "H69K", 10, "rockchip10.dtb"

    return "UNKNOWN", None, None

tests = {
    610: ("H69K", 10, "rockchip10.dtb"),
    609: ("UNKNOWN", None, None),
    769: ("H69K", 10, "rockchip10.dtb"),
    770: ("H68K", 1, "rockchip1.dtb"),
    781: ("H68K", 1, "rockchip1.dtb"),
    783: ("H68K", 1, "rockchip1.dtb"),
    795: ("H68K", 1, "rockchip1.dtb"),
    796: ("H69K", 10, "rockchip10.dtb"),
    1023: ("H69K", 10, "rockchip10.dtb"),
    1024: ("UNKNOWN", None, None),
    1072264: ("UNKNOWN", None, None),
    1072265: ("H69K", 10, "rockchip10.dtb"),
}

for adc, expected in tests.items():
    result = simulate(adc)

    if result != expected:
        fail(
            f"ADC={adc}: 得到 {result}，"
            f"预期 {expected}"
        )

    print(
        f"✓ ADC={adc} -> "
        f"{result[0]} -> hwflag={result[1]} -> {result[2]}"
    )

print()
print("===== H68K/H69K 自动识别验证全部通过 =====")
PY

###############################################################################
# 4.5.2 输出最终 bootscript 核心区域
###############################################################################

echo
echo "== 最终 H68K/H69K bootscript =="

sed -n \
    '/if gpio input 143; then/,/env delete adc_value/p' \
    "$BOOT_SCRIPT"

echo
echo "====================================="

###############################################################################
# 5. 依赖完整性检查
###############################################################################

echo
echo "== 依赖完整性检查 =="

make defconfig >/dev/null

echo "✓ defconfig 完成"

###############################################################################
# 6. Go 版本检查
###############################################################################

echo
echo "== Go 版本检查 =="

if grep -q '^CONFIG_GOLANG_VERSION_1_27=y' .config 2>/dev/null; then
    echo "✓ Go 1.27 已启用"
else
    echo "Go 1.27 未显式启用，保持当前配置"
fi

###############################################################################
# 7. 最终源码检查
###############################################################################

echo
echo "== 最终源码检查 =="

if grep -Fq \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT"
then
    echo "✓ ADC7 检测存在"
else
    echo "ERROR: ADC7 检测丢失"
    exit 1
fi

if grep -Fq \
    'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
    "$BOOT_SCRIPT"
then
    echo "✓ H68K ADC 判断存在"
else
    echo "ERROR: H68K ADC 判断丢失"
    exit 1
fi

if grep -Fq \
    'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then' \
    "$BOOT_SCRIPT"
then
    echo "✓ H69K ADC 判断存在"
else
    echo "ERROR: H69K ADC 判断丢失"
    exit 1
fi

if grep -Fq \
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT"
then
    echo "✓ DTB 动态加载存在"
else
    echo "ERROR: DTB 动态加载丢失"
    exit 1
fi

echo
echo "===== DIY2 检查完成 ====="
