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
# 4. H68K DTS / rk3568-hinlink.dtsi 修复
#
# 重要原则：
#   1. H68K DTS 只复制，不修改
#   2. 只修改 rk3568-hinlink.dtsi
#   3. 只删除已经确认与 H68K 重复的板级节点
#   4. PMIC / RK809 / CPU / pinctrl 不盲删
###############################################################################

echo
echo "========================================"
echo "H68K DTS / DTSI 修复"
echo "========================================"

DTS_SOURCE="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"

DTSI_FILE="target/linux/rockchip/dts/rk3568/rk3568-hinlink.dtsi"

H68K_DTS1="target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts"
H68K_DTS2="target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts"
H68K_DTS3="target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts"


###############################################################################
# 4.1 复制 H68K DTS
###############################################################################

if [ -f "$DTS_SOURCE" ]; then

    mkdir -p target/linux/rockchip/dts/rk3568
    mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

    cp -f "$DTS_SOURCE" "$H68K_DTS1"
    cp -f "$DTS_SOURCE" "$H68K_DTS2"
    cp -f "$DTS_SOURCE" "$H68K_DTS3"

    echo "H68K DTS 已复制"

else

    echo "WARNING: 未找到 H68K DTS:"
    echo "$DTS_SOURCE"

fi


###############################################################################
# 4.2 检查 DTSI
###############################################################################

if [ ! -f "$DTSI_FILE" ]; then

    echo "ERROR: 未找到 H68K 公共 DTSI:"
    echo "$DTSI_FILE"
    exit 1

fi

echo "DTSI: $DTSI_FILE"


###############################################################################
# 4.3 备份 DTSI，便于日志确认
###############################################################################

cp -f "$DTSI_FILE" "${DTSI_FILE}.diy2.bak"

echo "已备份 DTSI:"
echo "${DTSI_FILE}.diy2.bak"


###############################################################################
# 4.4 使用 Python 精确删除 DTS/DTSI 顶层节点
#
# 删除目标：
#   aliases
#   chosen
#   gpio-keys
#   leds
#   hdmi-con
#
#   dc_12v
#   vcc5v0_sys
#   vcc3v3_sys
#   vcc5v0_otg
#   vcc3v3_pcie
#
#   &hdmi_in
#   &hdmi_out
#   &vp0
#
# 注意：
#   不删除 PCIe controller
#   不删除 HDMI controller
#   不删除 PMIC / RK809
#   不删除 CPU regulator
#   不删除 pinctrl
###############################################################################

python3 - "$DTSI_FILE" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

remove_patterns = [
    # 根节点 / 板级节点
    r'^\s*aliases\s*\{',
    r'^\s*chosen\s*\{',
    r'^\s*gpio-keys\s*\{',
    r'^\s*leds\s*\{',
    r'^\s*hdmi-con\s*\{',

    # H68K 已经重新定义的 regulator
    r'^\s*dc_12v\s*:\s*[^\{]+\{',
    r'^\s*vcc5v0_sys\s*:\s*[^\{]+\{',
    r'^\s*vcc3v3_sys\s*:\s*[^\{]+\{',
    r'^\s*vcc5v0_otg\s*:\s*[^\{]+\{',
    r'^\s*vcc3v3_pcie\s*:\s*[^\{]+\{',

    # H68K 已经重新定义的 HDMI endpoint fragments
    r'^\s*&hdmi_in\s*\{',
    r'^\s*&hdmi_out\s*\{',
    r'^\s*&vp0\s*\{',
]

lines = text.splitlines(True)
remove_ranges = []

i = 0

while i < len(lines):

    line = lines[i]

    matched = False

    for pattern in remove_patterns:
        if re.match(pattern, line):
            matched = True
            break

    if not matched:
        i += 1
        continue

    start = i

    # 从当前行开始计算花括号深度。
    # 当前目标均为顶层 DTS 节点。
    depth = 0
    seen_open = False

    while i < len(lines):

        current = lines[i]

        # 简单去除双引号内容，避免字符串中的 { } 干扰。
        stripped = re.sub(r'"(?:\\.|[^"\\])*"', '""', current)

        opens = stripped.count("{")
        closes = stripped.count("}")

        if opens:
            seen_open = True

        depth += opens
        depth -= closes

        i += 1

        if seen_open and depth == 0:
            break

    remove_ranges.append((start, i))

new_lines = []
last = 0

for start, end in remove_ranges:
    new_lines.extend(lines[last:start])
    last = end

new_lines.extend(lines[last:])

new_text = "".join(new_lines)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_text)

print("DTSI 板级重复节点清理完成")
print("删除块数量:", len(remove_ranges))
PY


###############################################################################
# 4.5 vcc5v0_otg 引用改为 H68K 的 vcc5v0_usb_otg
###############################################################################

echo "修复 vcc5v0_otg 引用..."

sed -i \
    's/&vcc5v0_otg\b/&vcc5v0_usb_otg/g' \
    "$DTSI_FILE"


###############################################################################
# 4.6 删除旧 vcc3v3_pcie supply
#
# 只删除 supply 属性，不删除 PCIe controller。
###############################################################################

echo "删除公共 PCIe 电源 supply 引用..."

sed -i \
    '/^[[:space:]]*vpcie3v3-supply[[:space:]]*=[[:space:]]*<&vcc3v3_pcie>;[[:space:]]*$/d' \
    "$DTSI_FILE"


###############################################################################
# 4.7 严格检查已删除的旧 regulator 是否还有残留引用
###############################################################################

echo
echo "检查 DTSI 残留旧 regulator 引用..."

OLD_OTG_REMAIN="$(
    grep -nE '\bvcc5v0_otg\b' "$DTSI_FILE" 2>/dev/null || true
)"

if [ -n "$OLD_OTG_REMAIN" ]; then

    echo "ERROR: DTSI 仍然残留 vcc5v0_otg："
    echo "$OLD_OTG_REMAIN"

    exit 1

fi

OLD_PCIE_REMAIN="$(
    grep -nE '\bvpcie3v3-supply[[:space:]]*=[[:space:]]*<&vcc3v3_pcie>' \
        "$DTSI_FILE" 2>/dev/null || true
)"

if [ -n "$OLD_PCIE_REMAIN" ]; then

    echo "ERROR: DTSI 仍然残留旧 vcc3v3_pcie supply："
    echo "$OLD_PCIE_REMAIN"

    exit 1

fi

echo "✓ 旧 regulator 引用清理完成"


###############################################################################
# 4.8 检查 H68K DTS 中明确的重复 label
#
# 这里只报警，不自动删除 PMIC / CPU / pinctrl 等内容。
###############################################################################

echo
echo "检查 H68K DTS / DTSI 重复 label..."

if [ -f "$DTS_SOURCE" ]; then

    python3 - "$DTSI_FILE" "$DTS_SOURCE" <<'PY'
import re
import sys

dtsi = sys.argv[1]
dts  = sys.argv[2]

def labels(path):
    result = set()

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = re.sub(r'/\*.*?\*/', '', line)
            m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:', line)

            if m:
                result.add(m.group(1))

    return result

a = labels(dtsi)
b = labels(dts)

duplicates = sorted(a & b)

if duplicates:
    print("WARNING: 发现 DTSI / H68K DTS 同名 label：")
    for x in duplicates:
        print("  " + x)
    print("注意：这里只报告，不自动删除 PMIC / CPU / pinctrl 等内容。")
else:
    print("✓ 未发现 DTSI / H68K DTS 重复 label")
PY

fi


###############################################################################
# 4.9 检查明确应该删除的公共板级节点是否仍然存在
###############################################################################

echo
echo "检查公共板级节点清理结果..."

for label in \
    dc_12v \
    vcc5v0_sys \
    vcc3v3_sys \
    vcc5v0_otg \
    vcc3v3_pcie
do

    if grep -Eq \
        "^[[:space:]]*${label}[[:space:]]*:" \
        "$DTSI_FILE"; then

        echo "ERROR: DTSI 仍存在 ${label} 定义"
        exit 1

    fi

done

for node in \
    aliases \
    chosen \
    gpio-keys \
    leds \
    hdmi-con
do

    if grep -Eq \
        "^[[:space:]]*${node}[[:space:]]*\{" \
        "$DTSI_FILE"; then

        echo "ERROR: DTSI 仍存在 ${node} 节点"
        exit 1

    fi

done

echo "✓ 公共板级重复节点清理完成"


###############################################################################
# 4.10 检查 HDMI 重复 fragments
###############################################################################

for fragment in \
    '&hdmi_in' \
    '&hdmi_out' \
    '&vp0'
do

    if grep -Eq \
        "^[[:space:]]*${fragment}[[:space:]]*\{" \
        "$DTSI_FILE"; then

        echo "ERROR: DTSI 仍存在重复 HDMI fragment: ${fragment}"
        exit 1

    fi

done

echo "✓ 重复 HDMI endpoint fragments 清理完成"


###############################################################################
# 4.11 验证 H68K DTS 完全没有被 DIY2 修改
###############################################################################

echo
echo "检查 H68K DTS 是否保持原文件一致..."

if [ -f "$DTS_SOURCE" ]; then

    if ! cmp -s "$DTS_SOURCE" "$H68K_DTS1"; then
        echo "ERROR: $H68K_DTS1 与原始 H68K DTS 不一致"
        exit 1
    fi

    if ! cmp -s "$DTS_SOURCE" "$H68K_DTS2"; then
        echo "ERROR: $H68K_DTS2 与原始 H68K DTS 不一致"
        exit 1
    fi

    if ! cmp -s "$DTS_SOURCE" "$H68K_DTS3"; then
        echo "ERROR: $H68K_DTS3 与原始 H68K DTS 不一致"
        exit 1
    fi

    echo "✓ H68K DTS 三份文件均与源文件完全一致"
    echo "✓ 本脚本没有修改 H68K DTS"

fi


###############################################################################
# 4.12 DTSI 修复完成
###############################################################################

echo
echo "========================================"
echo "H68K DTSI 修复完成"
echo "========================================"

echo "修改文件:"
echo "  $DTSI_FILE"

echo
echo "处理内容:"
echo "  ✓ aliases"
echo "  ✓ chosen"
echo "  ✓ gpio-keys"
echo "  ✓ leds"
echo "  ✓ hdmi-con"
echo "  ✓ dc_12v"
echo "  ✓ vcc5v0_sys"
echo "  ✓ vcc3v3_sys"
echo "  ✓ vcc5v0_otg -> vcc5v0_usb_otg"
echo "  ✓ vcc3v3_pcie"
echo "  ✓ PCIe 旧 supply"
echo "  ✓ HDMI endpoint fragments"

echo
echo "保留内容:"
echo "  ✓ PCIe controller"
echo "  ✓ HDMI controller"
echo "  ✓ USB PHY/controller"
echo "  ✓ PMIC / RK809"
echo "  ✓ CPU regulator"
echo "  ✓ pinctrl"
echo "  ✓ 其它公共 RK3568 硬件配置"


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
# 12.5 自动判断 .config 中的插件依赖完整性
###############################################################################

echo
echo "========================================"
echo "检查 .config 中插件依赖完整性"
echo "========================================"

if [ -f .config ]; then

    MISSING_DEPS_FOUND=0

    # 遍历 .config 中所有已启用的 package
    for pkg in $CONFIG_PACKAGES; do

        [ -n "$pkg" ] || continue

        # 查找该包的 Makefile 位置 (优先找 package/，其次 feeds/)
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
                -print0 2>/dev/null || true
        )

        [ -n "$pkg_makefile" ] || continue

        # 解析 Package/pkg 块内的 DEPENDS 字段
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

        # 清理依赖表达式
        parsed_deps="$(
            echo "$raw_depends" |
            sed -E \
                's/\+@?[A-Za-z0-9_:-]+//g;
                 s/\+/\ /g;
                 s/@[A-Za-z0-9_:-]+//g' |
            tr ' ' '\n' |
            sed \
                -e 's/^[[:space:]]*//' \
                -e 's/[[:space:]]*$//' |
            grep -v -E '^$|^\+|^\%|^!' |
            sort -u || true
        )"

        # 检查每个依赖是否在 .config 或源码目录中可用
        for dep in $parsed_deps; do

            [ -n "$dep" ] || continue

            # 忽略核心内建/虚拟包
            case "$dep" in
                libc|librt|libpthread|kernel|kmod-*|luci-base|luci-compat)
                    continue
                    ;;
            esac

            # 1. 检查 .config 是否已被选中 (=y 或 =m)
            if ! grep -Eq \
                "^CONFIG_PACKAGE_${dep}=(y|m)$" \
                .config 2>/dev/null; then

                # 2. 如果 .config 没选，检查源码树中是否存在该依赖
                dep_exists=0

                if grep -rnq \
                    "^[[:space:]]*define[[:space:]]\+Package/${dep}[[:space:]]*$" \
                    package/ feeds/ 2>/dev/null; then

                    dep_exists=1

                fi

                if [ "$dep_exists" -eq 0 ]; then

                    echo "❌ [警告] 插件 [$pkg] 依赖 [$dep]，但源码树及 package/feeds 中缺失该依赖！"

                    MISSING_DEPS_FOUND=1

                else

                    echo "⚠️ [提示] 插件 [$pkg] 依赖 [$dep]，但未在 .config 中启用 (=y)。(编译时可能自动补全)"

                fi

            fi

        done

    done

    if [ "$MISSING_DEPS_FOUND" -eq 0 ]; then

        echo "✓ 所有启用的插件依赖完整性检查通过！"

    else

        echo "⚠️ 注意：发现缺失的第三方依赖，请检查是否删除了必要的 package/feed 入口。"

    fi

fi


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
