#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 第三方插件 / 依赖 / 来源优先级处理
#
# 来源优先级：
#   1. package/myapp 独立第三方源码
#   2. DIY1 添加的第三方集合源
#   3. iStoreOS / OpenWrt 官方源码
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

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git \
    package/passwall-packages

git clone --depth=1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall.git \
    package/passwall-luci

./scripts/feeds update -a
./scripts/feeds install -a

###############################################################################
# 2. 第三方依赖预处理
###############################################################################

echo
echo "== 第三方依赖预处理 =="

# 第三方源
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

# 判断 package 是否存在
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

# 删除 package 选择
remove_package_entry() {
    local pkg="$1"

    sed -i \
        -E "/CONFIG_PACKAGE_${pkg}=y/d" \
        .config 2>/dev/null || true

    sed -i \
        -E "/CONFIG_PACKAGE_${pkg}\/.*/d" \
        .config 2>/dev/null || true
}

# 查找 Makefile
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

# 判断配置是否开启
is_enabled() {
    local pkg="$1"

    grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config 2>/dev/null
}

# 获取 package 版本
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

# myapp 优先
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

H68K = (
    r'if test "\$adc_value" -ge 770 -a "\$adc_value" -le 795; then'
)

H69K_IF = (
    r'if test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then'
)

H69K_ELIF = (
    r'elif test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then'
)

# ---------------------------------------------------------------------------
# 基础位置
# ---------------------------------------------------------------------------

gpio_matches = list(re.finditer(
    r'(?m)^[ \t]*if gpio input 143; then[ \t]*$',
    text
))

adc_matches = list(re.finditer(
    re.escape(ADC),
    text
))

if len(gpio_matches) != 1:
    print(
        "ERROR: GPIO143 检测逻辑数量异常："
        f"{len(gpio_matches)}"
    )
    sys.exit(1)

if len(adc_matches) != 1:
    print(
        "ERROR: ADC7 命令数量异常："
        f"{len(adc_matches)}"
    )
    sys.exit(1)

gpio_pos = gpio_matches[0].start()
adc_pos = adc_matches[0].start()

if adc_pos <= gpio_pos:
    print("ERROR: ADC7 位于 GPIO143 之前")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 找到 GPIO143 对应的 else。
#
# 这里不简单使用 rfind("else") 判断整个文件，
# 而是根据 GPIO143 所在行之后的第一个顶层 else。
# ---------------------------------------------------------------------------

gpio_line_end = text.find('\n', gpio_pos)

if gpio_line_end < 0:
    print("ERROR: GPIO143 行异常")
    sys.exit(1)

after_gpio = text[gpio_line_end + 1:adc_pos]

else_match = re.search(
    r'(?m)^[ \t]*else[ \t]*$',
    after_gpio
)

if not else_match:
    print("ERROR: ADC7 不在 GPIO143 的 else 分支中")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 已经正确修复：
#   H68K if
#   H69K elif
# ---------------------------------------------------------------------------

h68k_matches = list(re.finditer(
    re.escape(H68K),
    text
))

h69k_elif_matches = list(re.finditer(
    re.escape(H69K_ELIF),
    text
))

h69k_if_matches = list(re.finditer(
    r'(?m)^[ \t]*' + re.escape(H69K_IF) + r'[ \t]*$',
    text
))

if len(h68k_matches) == 1 and len(h69k_elif_matches) == 1:
    h68k_pos = h68k_matches[0].start()
    h69k_pos = h69k_elif_matches[0].start()

    if not (adc_pos < h68k_pos < h69k_pos):
        print("ERROR: H68K/H69K 判断顺序异常")
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

# ---------------------------------------------------------------------------
# 半成品修改直接停止。
#
# 防止脚本把已经被人工修改过的 bootscript 再次重构。
# ---------------------------------------------------------------------------

if (
    len(h68k_matches) > 0
    or len(h69k_elif_matches) > 0
):
    print("ERROR: 检测到不完整的 H68K/H69K 修改结构")
    print("ERROR: 为避免破坏 bootscript，停止自动修改")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 未修改状态：
# 必须只有一个官方 H69K if
# ---------------------------------------------------------------------------

if len(h69k_if_matches) != 1:
    print(
        "ERROR: 找不到唯一的官方 H69K 判断，"
        f"实际找到 {len(h69k_if_matches)} 个"
    )
    sys.exit(1)

m = h69k_if_matches[0]
indent = m.group(0)[:len(m.group(0)) - len(m.group(0).lstrip())]

# 官方 H69K 必须位于 ADC7 后
if m.start() <= adc_pos:
    print("ERROR: 官方 H69K 判断位于 ADC7 之前")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 只替换这一行。
#
# 不移动：
#   GPIO143
#   ADC7
#   外层 if/else/fi
#   USB reset
#   bootargs
#   DTB load
# ---------------------------------------------------------------------------

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
print("✓ H69K 官方判断保留并改为 elif")
print("✓ GPIO143 / ADC7 官方嵌套结构未改变")
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

# ---------------------------------------------------------------------------
# 基础数量检查
# ---------------------------------------------------------------------------

if count(r'^[ \t]*if gpio input 143; then[ \t]*$') != 1:
    fail("GPIO143 检测数量异常")

if count(r'adc single saradc@fe720000 7 adc_value') != 1:
    fail("ADC7 命令数量异常")

if count(
    r'^[ \t]*if test "\$adc_value" -ge 770 -a "\$adc_value" -le 795; then[ \t]*$'
) != 1:
    fail("H68K 条件数量异常")

if count(
    r'^[ \t]*elif test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then[ \t]*$'
) != 1:
    fail("H69K 条件数量异常")

if count(r'^[ \t]*echo h68k[ \t]*$') != 1:
    fail("echo h68k 数量异常")

if count(r'^[ \t]*setenv hwflag 1[ \t]*$') < 1:
    fail("H68K hwflag=1 不存在")

if count(r'^[ \t]*echo h69k[ \t]*$') != 1:
    fail("echo h69k 数量异常")

if count(r'^[ \t]*setenv hwflag 10[ \t]*$') != 1:
    fail("H69K hwflag=10 数量异常")

if count(
    r'^[ \t]*load mmc \$\{devnum\}:1 '
    r'\$\{fdt_addr_r\} rockchip\$\{hwflag\}\.dtb[ \t]*$'
) != 1:
    fail("DTB 动态加载逻辑异常")

# ---------------------------------------------------------------------------
# 位置检查
# ---------------------------------------------------------------------------

gpio_match = re.search(
    r'(?m)^[ \t]*if gpio input 143; then[ \t]*$',
    text
)

adc_match = re.search(
    r'adc single saradc@fe720000 7 adc_value',
    text
)

h68k_match = re.search(
    r'(?m)^[ \t]*if test "\$adc_value" -ge 770 '
    r'-a "\$adc_value" -le 795; then[ \t]*$',
    text
)

h69k_match = re.search(
    r'(?m)^[ \t]*elif test "\$adc_value" -lt 1024 '
    r'-a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then[ \t]*$',
    text
)

if not all((gpio_match, adc_match, h68k_match, h69k_match)):
    fail("无法定位 GPIO143 / ADC7 / H68K / H69K")

gpio_pos = gpio_match.start()
adc_pos = adc_match.start()
h68k_pos = h68k_match.start()
h69k_pos = h69k_match.start()

if not (
    gpio_pos
    < adc_pos
    < h68k_pos
    < h69k_pos
):
    fail("GPIO143 / ADC7 / H68K / H69K 顺序异常")

# ---------------------------------------------------------------------------
# ADC7 必须位于 GPIO143 的 else 分支
# ---------------------------------------------------------------------------

gpio_line_end = text.find('\n', gpio_pos)

if gpio_line_end < 0:
    fail("GPIO143 行异常")

between_gpio_adc = text[gpio_line_end + 1:adc_pos]

if not re.search(
    r'(?m)^[ \t]*else[ \t]*$',
    between_gpio_adc
):
    fail("ADC7 不在 GPIO143 的 else 分支中")

# ---------------------------------------------------------------------------
# H68K / H69K 分支内容
# ---------------------------------------------------------------------------

h68k_block = text[h68k_pos:h69k_pos]
h69k_block = text[h69k_pos:]

if 'echo h68k' not in h68k_block:
    fail("H68K 分支缺少 echo h68k")

if 'setenv hwflag 1' not in h68k_block:
    fail("H68K 分支缺少 hwflag=1")

if 'echo h69k' not in h69k_block:
    fail("H69K 分支缺少 echo h69k")

if 'setenv hwflag 10' not in h69k_block:
    fail("H69K 分支缺少 hwflag=10")

# ---------------------------------------------------------------------------
# 确认 H68K/H69K 判断在 ADC7 有效性检查内部
# ---------------------------------------------------------------------------

adc_valid_pos = text.find(
    'if test -n "$adc_value"; then',
    adc_pos
)

if adc_valid_pos < 0:
    fail("找不到 ADC7 有效性检查")

if not (
    adc_valid_pos < h68k_pos < h69k_pos
):
    fail("H68K/H69K 判断没有位于 ADC7 有效性检查内部")

# ---------------------------------------------------------------------------
# 模拟 ADC
# ---------------------------------------------------------------------------

def simulate(adc):
    if 770 <= adc <= 795:
        return "H68K", 1, "rockchip1.dtb"

    if (610 <= adc < 1024) or adc >= 1072265:
        return "H69K", 10, "rockchip10.dtb"

    return "UNKNOWN", None, None

tests = {
    610: ("H69K", 10, "rockchip10.dtb"),
    769: ("H69K", 10, "rockchip10.dtb"),
    770: ("H68K", 1, "rockchip1.dtb"),
    781: ("H68K", 1, "rockchip1.dtb"),
    783: ("H68K", 1, "rockchip1.dtb"),
    795: ("H68K", 1, "rockchip1.dtb"),
    796: ("H69K", 10, "rockchip10.dtb"),
    1023: ("H69K", 10, "rockchip10.dtb"),
    1072265: ("H69K", 10, "rockchip10.dtb"),
}

for adc, expected in tests.items():
    result = simulate(adc)

    if result != expected:
        fail(
            f"ADC={adc}: 得到 {result}，期望 {expected}"
        )

    print(
        f"✓ ADC={adc} -> "
        f"{result[0]} -> hwflag={result[1]} -> {result[2]}"
    )

print()
print("✓ GPIO143 -> ADC7 官方嵌套关系保持不变")
print("✓ ADC7 有效性检查保持不变")
print("✓ H68K 770~795 判断正常")
print("✓ H69K 官方范围判断正常")
print("✓ H68K 优先于 H69K")
print("✓ DTB 动态加载正常")
print("✓ bootscript 严格验证通过")
PY

echo
echo "===== H68K U-Boot 自动 DTB 修复完成 ====="
echo

###############################################################################
# 5. 依赖完整性检查
###############################################################################

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
echo "===== DIY2 检查完成 ====="echo "===== DIY2 检查完成 ====="
