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
# 3.1 SmartDNS Rust Makefile 修复
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
# 3.2 LuCI 中文包检查
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
# 3.3 Conntrack
###############################################################################

echo "== Conntrack 检查 =="

if grep -q '^CONFIG_PACKAGE_conntrack=y$' .config 2>/dev/null; then
    echo "✓ conntrack 已启用"
else
    echo "INFO: conntrack 未直接启用"
fi

###############################################################################
# 3.4 Wi-Fi 自动启用
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
# 4. H66K / H68K / H69K U-Boot 自动 DTB 识别
###############################################################################

echo "== H66K / H68K / H69K U-Boot 自动 DTB 识别修复 =="

BOOT_SCRIPT="target/linux/rockchip/image/legacy/rk3568-hinlink.bootscript"
LEGACY_MK="target/linux/rockchip/image/legacy.mk"

[ -f "$BOOT_SCRIPT" ] || {
    echo "ERROR: 找不到 $BOOT_SCRIPT"
    exit 1
}

[ -f "$LEGACY_MK" ] || {
    echo "ERROR: 找不到 $LEGACY_MK"
    exit 1
}

echo "== 检查 legacy.mk combined DTB 定义 =="

grep -Fq 'define Device/hinlink_opc-h6xk' "$LEGACY_MK" || {
    echo "ERROR: 找不到 hinlink_opc-h6xk"
    exit 1
}

grep -Fq \
    'SUPPORTED_DEVICES += hinlink,opc-h66k hinlink,opc-h68k hinlink,opc-h69k' \
    "$LEGACY_MK" || {
    echo "ERROR: H66K/H68K/H69K SUPPORTED_DEVICES 不完整"
    exit 1
}

grep -Fq \
    'DEVICE_DTS := rk3568/rk3568-opc-h66k rk3568/rk3568-opc-h68k rk3568/rk3568-opc-h69k' \
    "$LEGACY_MK" || {
    echo "ERROR: H66K/H68K/H69K DEVICE_DTS 顺序异常"
    exit 1
}

grep -Fq \
    'BOOT_SCRIPT := rk3568-hinlink' \
    "$LEGACY_MK" || {
    echo "ERROR: legacy.mk 未使用 rk3568-hinlink bootscript"
    exit 1
}

echo "✓ H66K -> rockchip0.dtb"
echo "✓ H68K -> rockchip1.dtb"
echo "✓ H69K -> rockchip10.dtb"
echo "✓ combined target 保持不拆分"
echo "✓ legacy.mk DTS 顺序正确"

echo "== 检查原始 bootscript =="

grep -Fq 'gpio input 143' "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 GPIO143 检测逻辑"
    exit 1
}

grep -Fq \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到 ADC7 命令"
    exit 1
}

grep -Fq \
    'rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 找不到动态 DTB 加载逻辑"
    exit 1
}

echo "✓ GPIO143 检测逻辑存在"
echo "✓ ADC7 检测逻辑存在"
echo "✓ 动态 DTB 加载逻辑存在"

###############################################################################
# 4.1 备份原始 bootscript
###############################################################################

BOOT_BACKUP="${BOOT_SCRIPT}.orig"

if [ ! -f "$BOOT_BACKUP" ]; then
    cp "$BOOT_SCRIPT" "$BOOT_BACKUP"
    echo "✓ 已备份原始 bootscript:"
    echo "  $BOOT_BACKUP"
else
    echo "✓ 原始 bootscript 备份已存在"
fi

###############################################################################
# 4.2 直接生成最终 bootscript
###############################################################################

echo "== 写入 H66K / H68K / H69K 自动识别逻辑 =="

cat > "$BOOT_SCRIPT" <<'EOF'
# hinlink rk3568 combined image

env delete hwflag
env delete adc_value

# using gpio 143 (GPIO4_B7, GMAC1_MDIO_M1) to detect gmac1
if gpio input 143; then
	echo nogmac
	setenv hwflag 0
else
	echo hasgmac1
	setenv hwflag 1

	# using SARADC CH7 to detect hwrev
	adc single saradc@fe720000 7 adc_value

	if test -n "$adc_value"; then
		# h68k 770-795
		if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then
			echo h68k
			setenv hwflag 1

		# h69k official detection:
		# 610-1023 or >=1072265
		elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610 -o "$adc_value" -ge 1072265; then
			echo h69k
			setenv hwflag 10
		fi
	fi
fi

if test "$hwflag" = "10" ; then
	# reset USB modem
	# 1. set RESET(GPIO0_C0) to high, will invert to low on module RESET#
	gpio set 16
	# 2. pull down USB power GPIO0_A5
	# gpio clear 5
fi

env delete adc_value

part uuid mmc ${devnum}:2 uuid

setenv bootargs "console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 root=PARTUUID=${uuid} rw rootwait"

load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb
load mmc ${devnum}:1 ${kernel_addr_r} kernel.img

env delete hwflag

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF

echo "✓ bootscript 已生成"

###############################################################################
# 4.3 严格验证 bootscript
###############################################################################

echo "== 严格验证 H66K / H68K / H69K bootscript =="

python3 - "$BOOT_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()

def fail(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)

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

h69k_pattern = (
    r'^[ \t]*elif[ \t]+test[ \t]+'
    r'"\$adc_value"[ \t]+-lt[ \t]+1024[ \t]+'
    r'-a[ \t]+"\$adc_value"[ \t]+-ge[ \t]+610[ \t]+'
    r'-o[ \t]+"\$adc_value"[ \t]+-ge[ \t]+1072265'
    r'[ \t]*;[ \t]*then[ \t]*$'
)

if count(gpio_pattern) != 1:
    fail("GPIO143 检测数量不是 1")

if text.count(
    'adc single saradc@fe720000 7 adc_value'
) != 1:
    fail("ADC7 命令数量不是 1")

if count(h68k_pattern) != 1:
    fail("H68K ADC 770-795 判断数量不是 1")

if count(h69k_pattern) != 1:
    fail("H69K 判断数量不是 1")

if text.count(
    'load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb'
) != 1:
    fail("动态 DTB 加载命令数量不是 1")

if 'setenv hwflag 0' not in text:
    fail("缺少 H66K hwflag=0")

if 'echo nogmac' not in text:
    fail("缺少 H66K nogmac")

if 'echo h68k' not in text:
    fail("缺少 H68K echo")

if 'setenv hwflag 1' not in text:
    fail("缺少 H68K hwflag=1")

if 'echo h69k' not in text:
    fail("缺少 H69K echo")

if 'setenv hwflag 10' not in text:
    fail("缺少 H69K hwflag=10")

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
    if re.match(h69k_pattern, x)
)

if not (gpio_pos < adc_pos < h68k_pos < h69k_pos):
    fail("GPIO143 -> ADC7 -> H68K -> H69K 顺序异常")

# GPIO143 true 分支必须设置 H66K = 0
nogmac_pos = next(
    i for i, x in enumerate(lines)
    if x.strip() == 'echo nogmac'
)

h66k_pos = next(
    i for i, x in enumerate(lines)
    if x.strip() == 'setenv hwflag 0'
)

if not (gpio_pos < nogmac_pos < h66k_pos < adc_pos):
    fail("H66K hwflag=0 不在 GPIO143 true 分支")

# ADC7 必须位于 GPIO143 else 分支
else_pos = next(
    (i for i, x in enumerate(lines[gpio_pos + 1:], gpio_pos + 1)
     if x.strip() == 'else'),
    None
)

if else_pos is None:
    fail("找不到 GPIO143 else 分支")

if not (else_pos < adc_pos):
    fail("ADC7 不在 GPIO143 else 分支")

# H68K 必须位于 H69K 之前
if not (h68k_pos < h69k_pos):
    fail("H68K 判断没有位于 H69K 之前")

# H68K 范围不能被 H69K 官方范围提前截断
if 'elif test "$adc_value" -lt 1024 -a "$adc_value" -ge 610' not in text:
    fail("H69K 官方判断被错误修改")

print("✓ GPIO143 检测 = 1")
print("✓ H66K hwflag = 0")
print("✓ ADC7 检测 = 1")
print("✓ H68K ADC = 770-795")
print("✓ H68K hwflag = 1")
print("✓ H69K ADC = 官方范围")
print("✓ H69K hwflag = 10")
print("✓ 动态 DTB 加载 = rockchip${hwflag}.dtb")
print("✓ H66K -> rockchip0.dtb")
print("✓ H68K -> rockchip1.dtb")
print("✓ H69K -> rockchip10.dtb")
print("✓ 自动识别顺序正确")
PY

###############################################################################
# 4.4 显示最终 bootscript
###############################################################################

echo
echo "===== 最终 rk3568-hinlink.bootscript ====="
cat "$BOOT_SCRIPT"
echo "=========================================="
echo

echo "===== bootscript SHA256 ====="
sha256sum "$BOOT_SCRIPT"
echo

###############################################################################
# 5. 生成最终配置
###############################################################################

echo "== 生成最终配置 =="

make defconfig >/dev/null

echo "✓ make defconfig 完成"

###############################################################################
# 6. Go 1.27
###############################################################################

# echo "== Go 1.27 =="
#
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
#
# GO_VERSION="$(get_package_version golang)"
#
# echo "Go 版本: ${GO_VERSION:-未知}"

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

# [ -d feeds/packages/lang/golang ] || {
#     echo "ERROR: Golang feed 不存在"
#     exit 1
# }

[ -f "$BOOT_SCRIPT" ] || {
    echo "ERROR: H68K bootscript 不存在"
    exit 1
}

[ -f "$LEGACY_MK" ] || {
    echo "ERROR: legacy.mk 不存在"
    exit 1
}

grep -Fq \
    'SUPPORTED_DEVICES += hinlink,opc-h66k hinlink,opc-h68k hinlink,opc-h69k' \
    "$LEGACY_MK" || {
    echo "ERROR: legacy.mk combined target 异常"
    exit 1
}

grep -Fq \
    'DEVICE_DTS := rk3568/rk3568-opc-h66k rk3568/rk3568-opc-h68k rk3568/rk3568-opc-h69k' \
    "$LEGACY_MK" || {
    echo "ERROR: legacy.mk DTS 顺序异常"
    exit 1
}

grep -Fq \
    'BOOT_SCRIPT := rk3568-hinlink' \
    "$LEGACY_MK" || {
    echo "ERROR: legacy.mk BOOT_SCRIPT 异常"
    exit 1
}

grep -Fq \
    'adc single saradc@fe720000 7 adc_value' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 ADC7"
    exit 1
}

grep -Fq \
    'rockchip${hwflag}.dtb' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少动态 DTB"
    exit 1
}

grep -Fq \
    'if test "$adc_value" -ge 770 -a "$adc_value" -le 795; then' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H68K ADC 770-795"
    exit 1
}

grep -Fq \
    'setenv hwflag 0' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H66K hwflag=0"
    exit 1
}

grep -Fq \
    'setenv hwflag 1' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H68K hwflag=1"
    exit 1
}

grep -Fq \
    'setenv hwflag 10' \
    "$BOOT_SCRIPT" || {
    echo "ERROR: 最终源码缺少 H69K hwflag=10"
    exit 1
}

echo "✓ PassWall packages"
echo "✓ PassWall LuCI"
echo "✓ legacy.mk combined target"
echo "✓ H66K -> rockchip0.dtb"
echo "✓ H68K -> rockchip1.dtb"
echo "✓ H69K -> rockchip10.dtb"
echo "✓ H68K ADC 770-795"
echo "✓ H69K ADC 自动识别"
echo "✓ 动态 DTB 加载"
echo "== DIY2 OK =="
