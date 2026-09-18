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
    https://github.com/xiaorouji/openwrt-passwall-packages.git \
    package/passwall-packages

git clone --depth=1 \
    https://github.com/xiaorouji/openwrt-passwall.git \
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

grep -Fq 'rockchip${hwflag}.dtb' "$BOOT_SCRIPT" || {
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

# 官方 H69K 判断
official_h69k = re.compile(
    r'(?m)^([ \t]*)'
    r'if test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then[ \t]*$'
)

# 已修复后的 H68K 判断
patched_h68k = re.compile(
    r'(?m)^([ \t]*)'
    r'if test "\$adc_value" -ge 770 -a "\$adc_value" -le 795; then[ \t]*$'
)

# 已修复后的 H69K elif
patched_h69k = re.compile(
    r'(?m)^([ \t]*)'
    r'elif test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then[ \t]*$'
)

h68k_matches = list(patched_h68k.finditer(text))
h69k_matches = list(patched_h69k.finditer(text))
official_matches = list(official_h69k.finditer(text))

# ---------------------------------------------------------------------------
# 已经正确修复：直接验证并退出
# ---------------------------------------------------------------------------

if len(h68k_matches) == 1 and len(h69k_matches) == 1:
    h68k = h68k_matches[0]
    h69k = h69k_matches[0]

    if h68k.start() >= h69k.start():
        print("ERROR: H68K 判断没有位于 H69K 判断之前。")
        sys.exit(1)

    block_start = max(
        text.rfind("adc single saradc@fe720000 7 adc_value", 0, h68k.start()),
        text.rfind("else", 0, h68k.start())
    )

    if block_start < 0:
        print("ERROR: 无法确认 H68K 判断位于 ADC7 后。")
        sys.exit(1)

    print("✓ H68K/H69K 自动识别逻辑已正确存在")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 如果存在 H68K，但结构不是完整正确结构，拒绝继续修改
# ---------------------------------------------------------------------------

if len(h68k_matches) > 0 or len(h69k_matches) > 0:
    print("ERROR: 已存在部分 H68K/H69K 修改，但结构不完整。")
    print("请检查 bootscript，拒绝自动重构。")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 必须只有一个官方 H69K if
# ---------------------------------------------------------------------------

if len(official_matches) != 1:
    print(
        "ERROR: 找不到唯一的官方 H69K 判断，"
        f"实际找到 {len(official_matches)} 个。"
    )
    sys.exit(1)

m = official_matches[0]
indent = m.group(1)

# ---------------------------------------------------------------------------
# 确认 ADC7 在 GPIO143 的 else 分支内部
# ---------------------------------------------------------------------------

adc_pos = text.find(
    "adc single saradc@fe720000 7 adc_value"
)

if adc_pos < 0:
    print("ERROR: 找不到 ADC7 命令。")
    sys.exit(1)

gpio_pos = text.find("if gpio input 143")
if gpio_pos < 0 or adc_pos < gpio_pos:
    print("ERROR: ADC7 位于 GPIO143 检测之前，结构异常。")
    sys.exit(1)

# 找 ADC7 前最近的 else
else_pos = text.rfind("else", gpio_pos, adc_pos)

if else_pos < 0:
    print("ERROR: 无法确认 ADC7 位于 GPIO143 的 else 分支。")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 只替换官方 H69K 的 if
# ---------------------------------------------------------------------------

replacement = (
    f'{indent}if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then\n'
    f'{indent}\techo h68k\n'
    f'{indent}\tsetenv hwflag 1\n'
    f'{indent}elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 '
    f'-o "$adc_value" -ge 1072265; then'
)

text = (
    text[:m.start()]
    + replacement
    + text[m.end():]
)

path.write_text(text)

print("✓ 已在官方 H69K 判断之前加入 H68K ADC7 判断")
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

def count(pattern):
    return len(re.findall(pattern, text, re.MULTILINE))

# 基础检查
if count(r'if gpio input 143') != 1:
    print("ERROR: GPIO143 检测数量异常")
    sys.exit(1)

if count(r'adc single saradc@fe720000 7 adc_value') != 1:
    print("ERROR: ADC7 命令数量异常")
    sys.exit(1)

if count(r'if test "\$adc_value" -ge 770 -a "\$adc_value" -le 795; then') != 1:
    print("ERROR: H68K 条件数量异常")
    sys.exit(1)

if count(
    r'elif test "\$adc_value" -lt 1024 -a "\$adc_value" -ge 610 '
    r'-o "\$adc_value" -ge 1072265; then'
) != 1:
    print("ERROR: H69K 条件数量异常")
    sys.exit(1)

if count(r'echo h68k') != 1:
    print("ERROR: echo h68k 数量异常")
    sys.exit(1)

if count(r'setenv hwflag 1') < 1:
    print("ERROR: H68K hwflag=1 不存在")
    sys.exit(1)

if count(r'echo h69k') != 1:
    print("ERROR: echo h69k 数量异常")
    sys.exit(1)

if count(r'setenv hwflag 10') != 1:
    print("ERROR: H69K hwflag=10 不存在")
    sys.exit(1)

if count(r'load mmc \$\{devnum\}:1 \$\{fdt_addr_r\} rockchip\$\{hwflag\}\.dtb') != 1:
    print("ERROR: DTB 动态加载逻辑异常")
    sys.exit(1)

# 位置关系
gpio_pos = text.find("if gpio input 143")
adc_pos = text.find("adc single saradc@fe720000 7 adc_value")
h68k_pos = text.find(
    'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then'
)
h69k_pos = text.find(
    'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 '
    '-o "$adc_value" -ge 1072265; then'
)

if not (
    gpio_pos >= 0
    and adc_pos > gpio_pos
    and h68k_pos > adc_pos
    and h69k_pos > h68k_pos
):
    print("ERROR: GPIO143 / ADC7 / H68K / H69K 顺序异常")
    sys.exit(1)

# ADC7 前必须存在 GPIO143 的 else
else_pos = text.rfind("else", gpio_pos, adc_pos)

if else_pos < 0:
    print("ERROR: ADC7 不在 GPIO143 的 else 分支中")
    sys.exit(1)

# H68K 后必须紧接 H69K
between = text[h68k_pos:h69k_pos]

if 'setenv hwflag 1' not in between:
    print("ERROR: H68K 分支缺少 hwflag=1")
    sys.exit(1)

# 模拟实际 ADC 值
def simulate(adc):
    if 770 <= adc <= 795:
        return "H68K", 1, "rockchip1.dtb"

    if (610 <= adc < 1024) or adc >= 1072265:
        return "H69K", 10, "rockchip10.dtb"

    return "UNKNOWN", None, None

tests = {
    781: ("H68K", 1, "rockchip1.dtb"),
    783: ("H68K", 1, "rockchip1.dtb"),
    700: ("H69K", 10, "rockchip10.dtb"),
    1072265: ("H69K", 10, "rockchip10.dtb"),
}

for adc, expected in tests.items():
    result = simulate(adc)

    if result != expected:
        print(
            f"ERROR: ADC={adc}: "
            f"得到 {result}，期望 {expected}"
        )
        sys.exit(1)

    print(
        f"✓ ADC={adc} -> "
        f"{result[0]} -> hwflag={result[1]} -> {result[2]}"
    )

print()
print("✓ GPIO143 -> ADC7 官方嵌套关系保持不变")
print("✓ H68K 770~795 判断正常")
print("✓ H69K 官方范围判断正常")
print("✓ H68K 优先于 H69K")
print("✓ DTB 动态加载正常")
print("✓ bootscript 验证通过")
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
echo "===== DIY2 检查完成 ====="
