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
if [ -d feeds/packages/lang/golang ]; then
    echo "删除旧 Golang"
    rm -rf feeds/packages/lang/golang
fi

git clone \
    -b 27.x \
    --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang

# 1.2 移除官方旧库
# PassWall 已由 DIY1 拉取到 package/myapp，这里不重复拉取
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall

# DIY1 已下载：
# package/myapp/passwall-packages
# package/myapp/passwall
#
# DIY2 不重复 Clone，以下仅保留原逻辑为注释
# rm -rf package/passwall-packages package/passwall-luci
# git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
# git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

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
# 15. HINLINK H66K / H68K / H69K 独立编译目标
###############################################################################

echo
echo "========================================"
echo "配置 HINLINK H66K / H68K / H69K"
echo "========================================"

echo "H66K -> H66K DTS + H66K boot script"
echo "H68K -> H68K DTS + H68K boot script"
echo "H69K -> H69K DTS + H69K boot script"
echo "不使用 GPIO / ADC / hwflag 自动识别"
echo "不使用 H66K/H68K/H69K combined target"


###############################################################################
# 15.1 定位 Rockchip image / legacy.mk
###############################################################################

echo
echo "== 15.1 定位 Rockchip image 配置 =="

IMAGE_DIR="$TOPDIR/target/linux/rockchip/image"
LEGACY_MK="$IMAGE_DIR/legacy.mk"
BOOT_DIR="$IMAGE_DIR/legacy"

if [ ! -d "$IMAGE_DIR" ]; then
	echo "错误：找不到 $IMAGE_DIR"
	exit 1
fi

if [ ! -f "$LEGACY_MK" ]; then
	echo "错误：找不到 $LEGACY_MK"
	exit 1
fi

mkdir -p "$BOOT_DIR"

echo "IMAGE_DIR : $IMAGE_DIR"
echo "LEGACY_MK : $LEGACY_MK"
echo "BOOT_DIR  : $BOOT_DIR"


###############################################################################
# 15.2 检查 HINLINK combined target
###############################################################################

echo
echo "== 15.2 检查 HINLINK H6xK 定义 =="

python3 - "$LEGACY_MK" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

combined_start = "define Device/hinlink_opc-h6xk"
combined_end = "TARGET_DEVICES += hinlink_opc-h6xk"

split_targets = [
    "define Device/hinlink_opc-h66k",
    "define Device/hinlink_opc-h68k",
    "define Device/hinlink_opc-h69k",
]

if combined_start in text:

    if text.count(combined_start) != 1:
        print("错误：旧的 hinlink_opc-h6xk 定义出现次数不是 1")
        sys.exit(1)

    if text.count(combined_end) != 1:
        print("错误：旧的 hinlink_opc-h6xk TARGET_DEVICES 出现次数不是 1")
        sys.exit(1)

    start_pos = text.find(combined_start)
    end_pos = text.find(combined_end, start_pos)

    if end_pos == -1 or end_pos < start_pos:
        print("错误：无法正确定位旧 HINLINK combined block")
        sys.exit(1)

    print("原始 HINLINK combined target 检查通过")

else:
    print("检测到 HINLINK 已经是拆分状态，继续执行")

for target in split_targets:
    count = text.count(target)

    if count > 1:
        print(f"错误：{target} 出现次数异常：{count}")
        sys.exit(1)

print("HINLINK target 结构检查通过")
PY


###############################################################################
# 15.3 拆分 H66K / H68K / H69K
###############################################################################

echo
echo "== 15.3 拆分 H66K / H68K / H69K =="

python3 - "$LEGACY_MK" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

old = """define Device/hinlink_opc-h6xk
$(call Device/rk3568/hinlink,$(1))
  DEVICE_MODEL := OPC-H69K/H68K/H66K combined
  SUPPORTED_DEVICES += hinlink,opc-h66k hinlink,opc-h68k hinlink,opc-h69k
  DEVICE_DTS := rk3568/rk3568-opc-h66k rk3568/rk3568-opc-h68k rk3568/rk3568-opc-h69k
  BOOT_SCRIPT := rk3568-hinlink
endef
TARGET_DEVICES += hinlink_opc-h6xk"""

new = """define Device/hinlink_opc-h66k
$(call Device/rk3568/hinlink,$(1))
  DEVICE_MODEL := OPC-H66K
  SUPPORTED_DEVICES += hinlink,opc-h66k
  DEVICE_DTS := rk3568/rk3568-opc-h66k
  BOOT_SCRIPT := rk3568-hinlink-h66k
endef
TARGET_DEVICES += hinlink_opc-h66k

define Device/hinlink_opc-h68k
$(call Device/rk3568/hinlink,$(1))
  DEVICE_MODEL := OPC-H68K
  SUPPORTED_DEVICES += hinlink,opc-h68k
  DEVICE_DTS := rk3568/rk3568-opc-h68k
  BOOT_SCRIPT := rk3568-hinlink-h68k
endef
TARGET_DEVICES += hinlink_opc-h68k

define Device/hinlink_opc-h69k
$(call Device/rk3568/hinlink,$(1))
  DEVICE_MODEL := OPC-H69K
  SUPPORTED_DEVICES += hinlink,opc-h69k
  DEVICE_DTS := rk3568/rk3568-opc-h69k
  BOOT_SCRIPT := rk3568-hinlink-h69k
endef
TARGET_DEVICES += hinlink_opc-h69k"""

count = text.count(old)

if count == 1:

    text = text.replace(old, new, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

    print("HINLINK H6xK combined target 已成功拆分为三个独立 target")

elif count == 0:

    print("HINLINK combined block 不存在，检查是否已经完成拆分")

else:

    print("错误：原始 HINLINK combined block 匹配次数为", count)
    print("为防止误修改，停止执行。")
    sys.exit(1)
PY


###############################################################################
# 15.4 创建 H66K boot script
###############################################################################

echo
echo "== 15.4 创建 H66K boot script =="

cat > "$BOOT_DIR/rk3568-hinlink-h66k.bootscript" <<'EOF'
# HINLINK RK3568 H66K

part uuid mmc ${devnum}:2 uuid

setenv bootargs "console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 root=PARTUUID=${uuid} rw rootwait"

load mmc ${devnum}:1 ${fdt_addr_r} rockchip0.dtb
load mmc ${devnum}:1 ${kernel_addr_r} kernel.img

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF


###############################################################################
# 15.5 创建 H68K boot script
###############################################################################

echo
echo "== 15.5 创建 H68K boot script =="

cat > "$BOOT_DIR/rk3568-hinlink-h68k.bootscript" <<'EOF'
# HINLINK RK3568 H68K

part uuid mmc ${devnum}:2 uuid

setenv bootargs "console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 root=PARTUUID=${uuid} rw rootwait"

load mmc ${devnum}:1 ${fdt_addr_r} rockchip0.dtb
load mmc ${devnum}:1 ${kernel_addr_r} kernel.img

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF


###############################################################################
# 15.6 创建 H69K boot script
###############################################################################

echo
echo "== 15.6 创建 H69K boot script =="

cat > "$BOOT_DIR/rk3568-hinlink-h69k.bootscript" <<'EOF'
# HINLINK RK3568 H69K

part uuid mmc ${devnum}:2 uuid

setenv bootargs "console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 root=PARTUUID=${uuid} rw rootwait"

load mmc ${devnum}:1 ${fdt_addr_r} rockchip0.dtb
load mmc ${devnum}:1 ${kernel_addr_r} kernel.img

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF


###############################################################################
# 15.7 检查 DTS 是否存在
###############################################################################

echo
echo "== 15.7 检查 H66K / H68K / H69K DTS =="

DTS_DIR="$TOPDIR/target/linux/rockchip/dts/rk3568"

for dts in \
	"rk3568-opc-h66k.dts" \
	"rk3568-opc-h68k.dts" \
	"rk3568-opc-h69k.dts"
do
	if [ ! -f "$DTS_DIR/$dts" ]; then
		echo "错误：找不到 DTS：$DTS_DIR/$dts"
		exit 1
	fi

	echo "OK: $DTS_DIR/$dts"
done


###############################################################################
# 15.8 检查 boot script 是否存在
###############################################################################

echo
echo "== 15.8 检查三个 boot script =="

for script in \
	"rk3568-hinlink-h66k.bootscript" \
	"rk3568-hinlink-h68k.bootscript" \
	"rk3568-hinlink-h69k.bootscript"
do
	if [ ! -f "$BOOT_DIR/$script" ]; then
		echo "错误：找不到 boot script：$BOOT_DIR/$script"
		exit 1
	fi

	echo "OK: $BOOT_DIR/$script"
done


###############################################################################
# 15.9 检查 legacy.mk 最终配置
###############################################################################

echo
echo "== 15.9 检查 legacy.mk 最终 HINLINK 配置 =="

grep -A6 -B1 \
	"define Device/hinlink_opc-h66k" \
	"$LEGACY_MK"

echo

grep -A6 -B1 \
	"define Device/hinlink_opc-h68k" \
	"$LEGACY_MK"

echo

grep -A6 -B1 \
	"define Device/hinlink_opc-h69k" \
	"$LEGACY_MK"


###############################################################################
# 15.10 严格检查三个 target 是否一对一
###############################################################################

echo
echo "== 15.10 检查 DTS / BOOT_SCRIPT 一对一关系 =="

python3 - "$LEGACY_MK" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

expected = {
    "hinlink_opc-h66k": (
        "rk3568/rk3568-opc-h66k",
        "rk3568-hinlink-h66k",
    ),
    "hinlink_opc-h68k": (
        "rk3568/rk3568-opc-h68k",
        "rk3568-hinlink-h68k",
    ),
    "hinlink_opc-h69k": (
        "rk3568/rk3568-opc-h69k",
        "rk3568-hinlink-h69k",
    ),
}

for target, (dts, boot) in expected.items():

    start_marker = f"define Device/{target}"
    target_marker = f"TARGET_DEVICES += {target}"

    start = text.find(start_marker)
    end = text.find(target_marker, start)

    if start == -1:
        print(f"错误：找不到 target：{target}")
        sys.exit(1)

    if end == -1:
        print(f"错误：找不到 TARGET_DEVICES：{target}")
        sys.exit(1)

    block = text[start:end + len(target_marker)]

    if f"DEVICE_DTS := {dts}" not in block:
        print(f"错误：{target} DTS 不正确")
        sys.exit(1)

    if f"BOOT_SCRIPT := {boot}" not in block:
        print(f"错误：{target} BOOT_SCRIPT 不正确")
        sys.exit(1)

    if block.count("DEVICE_DTS :=") != 1:
        print(f"错误：{target} DEVICE_DTS 定义异常")
        sys.exit(1)

    if block.count("BOOT_SCRIPT :=") != 1:
        print(f"错误：{target} BOOT_SCRIPT 定义异常")
        sys.exit(1)

    print(f"OK: {target}")
    print(f"    DTS         = {dts}")
    print(f"    BOOT_SCRIPT = {boot}")

if "define Device/hinlink_opc-h6xk" in text:
    print("错误：旧的 hinlink_opc-h6xk combined target 仍然存在")
    sys.exit(1)

if "TARGET_DEVICES += hinlink_opc-h6xk" in text:
    print("错误：旧的 combined TARGET_DEVICES 仍然存在")
    sys.exit(1)

print()
print("HINLINK H66K/H68K/H69K 拆分配置检查全部通过")
PY


###############################################################################
# 15.11 检查 boot script 中不存在运行时自动识别逻辑
###############################################################################

echo
echo "== 15.11 检查 boot script 是否彻底移除 GPIO / ADC / hwflag =="

for script in \
	"rk3568-hinlink-h66k.bootscript" \
	"rk3568-hinlink-h68k.bootscript" \
	"rk3568-hinlink-h69k.bootscript"
do

	if grep -Eq 'hwflag|adc_value|gpio input|gpio set|gpio clear|adc single|rockchip\$\{hwflag\}' \
		"$BOOT_DIR/$script"
	then
		echo "错误：$script 仍然包含运行时硬件检测逻辑"
		exit 1
	fi

	echo "OK: $script 无 GPIO / ADC / hwflag 自动检测"
done


###############################################################################
# 15.12 检查每个 boot script 固定使用 rockchip0.dtb
###############################################################################

echo
echo "== 15.12 检查固定 DTS 加载 =="

for script in \
	"rk3568-hinlink-h66k.bootscript" \
	"rk3568-hinlink-h68k.bootscript" \
	"rk3568-hinlink-h69k.bootscript"
do

	if ! grep -Fq \
		'load mmc ${devnum}:1 ${fdt_addr_r} rockchip0.dtb' \
		"$BOOT_DIR/$script"
	then
		echo "错误：$script 没有固定加载 rockchip0.dtb"
		exit 1
	fi

	if ! grep -Fq \
		'load mmc ${devnum}:1 ${kernel_addr_r} kernel.img' \
		"$BOOT_DIR/$script"
	then
		echo "错误：$script 没有加载 kernel.img"
		exit 1
	fi

	if ! grep -Fq \
		'booti ${kernel_addr_r} - ${fdt_addr_r}' \
		"$BOOT_DIR/$script"
	then
		echo "错误：$script 没有正确执行 booti"
		exit 1
	fi

	echo "OK: $script"
done


###############################################################################
# 15.13 检查三个 boot script 的机器名称
###############################################################################

echo
echo "== 15.13 检查 boot script 与设备名称 =="

declare -A BOOT_NAMES=(
	["rk3568-hinlink-h66k.bootscript"]="H66K"
	["rk3568-hinlink-h68k.bootscript"]="H68K"
	["rk3568-hinlink-h69k.bootscript"]="H69K"
)

for script in "${!BOOT_NAMES[@]}"
do
	name="${BOOT_NAMES[$script]}"

	if ! grep -Fq "# HINLINK RK3568 $name" "$BOOT_DIR/$script"; then
		echo "错误：$script 设备名称不匹配"
		exit 1
	fi

	echo "OK: $script -> $name"
done


###############################################################################
# 15.14 检查旧 combined boot script 是否仍被引用
###############################################################################

echo
echo "== 15.14 检查旧 combined boot script 引用 =="

if grep -R -n \
	-E 'BOOT_SCRIPT[[:space:]]*:=[[:space:]]*rk3568-hinlink([[:space:]]|$)|rk3568-hinlink\.bootscript' \
	target/linux/rockchip \
	--exclude='rk3568-hinlink.bootscript' \
	2>/dev/null
then
	echo "错误：仍有其他 Rockchip 配置引用旧的 rk3568-hinlink boot script"
	exit 1
else
	echo "OK: 没有其他 Rockchip 配置引用旧 combined boot script"
fi


###############################################################################
# 15.15 显示最终 HINLINK 配置
###############################################################################

echo
echo "========================================"
echo "HINLINK H66K / H68K / H69K 配置完成"
echo "========================================"

echo
echo "legacy.mk:"
echo "  $LEGACY_MK"

echo
echo "DTS:"
echo "  $DTS_DIR/rk3568-opc-h66k.dts"
echo "  $DTS_DIR/rk3568-opc-h68k.dts"
echo "  $DTS_DIR/rk3568-opc-h69k.dts"

echo
echo "Boot scripts:"
echo "  $BOOT_DIR/rk3568-hinlink-h66k.bootscript"
echo "  $BOOT_DIR/rk3568-hinlink-h68k.bootscript"
echo "  $BOOT_DIR/rk3568-hinlink-h69k.bootscript"

echo
echo "对应关系:"
echo "  H66K -> rk3568-opc-h66k.dts -> rk3568-hinlink-h66k.bootscript"
echo "  H68K -> rk3568-opc-h68k.dts -> rk3568-hinlink-h68k.bootscript"
echo "  H69K -> rk3568-opc-h69k.dts -> rk3568-hinlink-h69k.bootscript"

echo
echo "========================================"
echo "检查完成"
echo "HINLINK 三个设备已经完全一对一拆分"
echo "========================================"


###############################################################################
# 16. DIY2 完成
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"
