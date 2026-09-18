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

echo "DIY2 - H68K + iStoreOS 24.10"
echo "第三方插件 / 依赖 / 来源优先"


###############################################################################
# 0. 基础目录
###############################################################################

[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"


###############################################################################
# 1. 核心依赖与第三方源码拉取 (优先于扫描逻辑)
###############################################################################

echo
echo "========================================"
echo "拉取/更新 核心依赖与 PassWall 组件"
echo "========================================"

# 1.1 替换 Golang 为 27.x
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

# 1.2 移除官方旧库并拉取 PassWall
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall

rm -rf package/passwall-packages package/passwall-luci

git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

# 1.3 关键：刷新并注册新拉取的包索引到编译环境
echo "更新并安装新依赖索引..."
./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a


###############################################################################
# 2. 第三方依赖预处理 (明确要求的移除项)
###############################################################################

echo
echo "========================================"
echo "第三方依赖预处理"
echo "========================================"

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

    grep -Eq \
        "^CONFIG_PACKAGE_${pkg}=(y|m)$" \
        .config 2>/dev/null
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    [ -n "$pkg" ] || continue
    echo "明确要求：移除官方依赖入口 -> $pkg"
    for official_feed in $OFFICIAL_FEEDS; do
        remove_package_entry "$official_feed" "$pkg"
    done
done


###############################################################################
# 3. 获取包版本函数定义
###############################################################################

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
# 5. 扫描 package/myapp 真正的 Package
###############################################################################

echo
echo "========================================"
echo "扫描 DIY1 独立第三方插件"
echo "========================================"

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

        case "$pkg" in
            '$('*|*'$)'|*'/'*)
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


###############################################################################
# 6. 收集当前 .config 中实际启用的 Package
###############################################################################

echo
echo "========================================"
echo "读取当前 .config"
echo "========================================"

CONFIG_PACKAGES=""

if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

fi

echo "当前启用的第三方/官方 Package 数量：$(printf '%s\n' "$CONFIG_PACKAGES" | sed '/^$/d' | wc -l)"


###############################################################################
# 7. 独立第三方插件优先
###############################################################################

echo
echo "========================================"
echo "独立第三方插件优先"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "检查独立第三方插件: $pkg"

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

            echo "发现重复来源:"
            echo "  $feed/$pkg"
            echo "  版本: $VERSION"
            echo "选择: package/myapp"
            echo "原因: 独立第三方源码优先"

            remove_package_entry "$feed" "$pkg"

        fi

    done

done


###############################################################################
# 8. 第三方集合源优先 (THIRD_PARTY_FEEDS > OFFICIAL_FEEDS)
###############################################################################

echo
echo "========================================"
echo "第三方集合源优先"
echo "========================================"

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
    echo "发现第三方重复包: $pkg"
    echo "第三方来源: ${THIRD_SOURCE}/${pkg}"
    echo "第三方版本: $THIRD_VERSION"

    for official_feed in $OFFICIAL_FEEDS; do

        if package_entry_exists "$official_feed" "$pkg"; then

            OFFICIAL_MAKEFILE="$(package_makefile "$official_feed" "$pkg")"
            OFFICIAL_VERSION="$(get_package_version "$OFFICIAL_MAKEFILE")"

            echo "官方来源: ${official_feed}/${pkg}"
            echo "官方版本: $OFFICIAL_VERSION"

            if [ "$THIRD_VERSION" = "$OFFICIAL_VERSION" ]; then
                echo "版本相同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"
            else
                echo "版本不同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"
                echo "原因: 第三方来源优先，不按版本号自动选择"
            fi

            remove_package_entry "$official_feed" "$pkg"

        fi

    done

done


###############################################################################
# 9. SmartDNS Rust Makefile 修复
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
# 10. 自动添加 LuCI 中文语言包 (移除了内部 make defconfig)
###############################################################################

echo
echo "========================================"
echo "添加 LuCI 中文语言包"
echo "========================================"

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

            echo \
                "CONFIG_PACKAGE_${trans}-zh-cn=y" \
                >> .config

        fi

    done

fi


###############################################################################
# 11. conntrack 调优
###############################################################################

echo
echo "========================================"
echo "设置 conntrack"
echo "========================================"

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    package/base-files/files/etc/sysctl.conf

echo \
    'net.netfilter.nf_conntrack_max=655550' \
    >> package/base-files/files/etc/sysctl.conf

echo "nf_conntrack_max = 655550"


###############################################################################
# 12. Wi-Fi 首次启动自动开启
###############################################################################

echo
echo "========================================"
echo "设置 Wi-Fi 首次启动自动开启"
echo "========================================"

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


###############################################################################
# 13. 最终来源检查
###############################################################################

echo
echo "========================================"
echo "最终第三方插件来源检查"
echo "========================================"

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    echo
    echo "[$pkg]"

    if [ -d "package/myapp" ]; then

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


###############################################################################
# 14. DIY2 完成
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
