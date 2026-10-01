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
# H68K：
#   RTL8211F 1G 网口修复
#
# 特点：
#   1. 自动识别 Rockchip KERNEL_PATCHVER
#   2. 不依赖旧版 include/kernel-version.mk 格式
#   3. 先由 OpenWrt 自己下载 kernel
#   4. 自动寻找 dl/linux-6.18*.tar.*
#   5. 从实际 archive 自动获取 kernel 版本
#   6. 根据真实 H68K DTS 动态生成 patch
#   7. 自动执行 OpenWrt target/linux/prepare
#   8. git apply --check --reverse 验证
#   9. 验证失败立即停止
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
# 0.1 SONiC FullCone NAT
###############################################################################

echo
echo "========================================"
echo "添加 SONiC FullCone NAT"
echo "========================================"

SONIC_FULLCONE_SCRIPT="/tmp/add_sonic_fullcone.sh"

rm -f "$SONIC_FULLCONE_SCRIPT"

curl -fsSL \
    https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh \
    -o "$SONIC_FULLCONE_SCRIPT"

bash "$SONIC_FULLCONE_SCRIPT"

rm -f "$SONIC_FULLCONE_SCRIPT"

echo "SONiC FullCone NAT 添加完成"


###############################################################################
# 1. 核心依赖与第三方源码拉取
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


# 1.2 移除官方旧库并拉取 PassWall

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}

rm -rf feeds/luci/applications/luci-app-passwall

rm -rf package/passwall-packages package/passwall-luci


git clone \
    --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
    package/passwall-packages


git clone \
    --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall \
    package/passwall-luci


# 1.3 刷新 feeds

echo "更新并安装新依赖索引..."

./scripts/feeds install -p packages golang || true

./scripts/feeds install -f microsocks || true

./scripts/feeds install -a


###############################################################################
# 2. 第三方依赖预处理
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
        "^CONFIG_PACKAGE_${pkg}=(y|m)" \
        .config 2>/dev/null
}


for pkg in $REMOVE_OFFICIAL_DEPS; do

    [ -n "$pkg" ] || continue

    echo "明确要求：移除官方依赖入口 -> $pkg"

    for official_feed in $OFFICIAL_FEEDS; do

        remove_package_entry \
            "$official_feed" \
            "$pkg"

    done

done


###############################################################################
# 3. 获取包版本函数
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
# 4. H68K 1G 网口修复
#
# 重要：
#
# 不直接修改：
#
#   target/linux/rockchip/dts
#
# 不使用固定 @@ 行号。
#
# 流程：
#
#   1. 获取 Rockchip KERNEL_PATCHVER
#   2. 让 OpenWrt 自己执行 target/linux/download
#   3. 自动寻找实际 linux-6.18*.tar.*
#   4. 从 archive 文件名获取实际 kernel 版本
#   5. 解压真实 kernel source
#   6. 找到真实 H68K DTS
#   7. 建立临时 git baseline
#   8. 动态修改 DTS
#   9. git diff 生成 patch
#  10. 安装到 patches-${KERNEL_PATCHVER}
#  11. 清理 kernel prepare
#  12. OpenWrt target/linux/prepare
#  13. 建立验证 git repo
#  14. git apply --check --reverse
#  15. reverse apply 完整性检查
#  16. 最终 DTS 参数检查
#
###############################################################################

echo
echo "========================================"
echo "H68K RTL8211F 1G 网口修复"
echo "========================================"


###############################################################################
# 4.1 检查必要工具
###############################################################################

for cmd in \
    git \
    make \
    sed \
    awk \
    grep \
    find \
    tar \
    sort \
    head \
    tail \
    mktemp \
    python3 \
    curl
do

    if ! command -v "$cmd" >/dev/null 2>&1; then

        echo
        echo "ERROR: 缺少必要工具: $cmd"

        exit 1

    fi

done


###############################################################################
# 4.2 读取 Rockchip KERNEL_PATCHVER
###############################################################################

ROCKCHIP_MAKEFILE="target/linux/rockchip/Makefile"


if [ ! -f "$ROCKCHIP_MAKEFILE" ]; then

    echo
    echo "ERROR: 找不到:"
    echo "  $ROCKCHIP_MAKEFILE"

    exit 1

fi


KERNEL_PATCHVER="$(
    sed -nE \
        's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*([0-9]+\.[0-9]+).*$/\1/p' \
        "$ROCKCHIP_MAKEFILE" |
    head -n 1
)"


if [ -z "$KERNEL_PATCHVER" ]; then

    echo
    echo "ERROR: 无法读取 Rockchip KERNEL_PATCHVER"

    exit 1

fi


echo "Rockchip KERNEL_PATCHVER: $KERNEL_PATCHVER"


###############################################################################
# 4.3 关键修复：
#
# 不再从 include/kernel-version.mk 强行解析完整版本。
#
# 对新版 OpenWrt / iStoreOS：
#
#   6.18
#
# 的具体 kernel 版本由 OpenWrt 自己的 Makefile 体系解析。
#
# 所以直接：
#
#   make target/linux/download
#
# 然后从 dl/ 中寻找实际下载出来的：
#
#   linux-6.18*.tar.*
#
# 这是最可靠的方式。
###############################################################################

echo
echo "========================================"
echo "由 OpenWrt 自动解析并下载 Linux kernel"
echo "========================================"


make target/linux/download V=s


###############################################################################
# 4.4 自动寻找实际 kernel archive
###############################################################################

echo
echo "========================================"
echo "寻找实际 Linux kernel archive"
echo "========================================"


KERNEL_ARCHIVE=""

KERNEL_ARCHIVE_LIST="$(
    find dl \
        -maxdepth 1 \
        -type f \
        \( \
            -name "linux-${KERNEL_PATCHVER}*.tar.xz" \
            -o -name "linux-${KERNEL_PATCHVER}*.tar.zst" \
            -o -name "linux-${KERNEL_PATCHVER}*.tar.gz" \
            -o -name "linux-${KERNEL_PATCHVER}*.tar.bz2" \
        \) \
        -print 2>/dev/null |
    sort -V
)"


if [ -z "$KERNEL_ARCHIVE_LIST" ]; then

    echo
    echo "ERROR: OpenWrt 已执行 target/linux/download，"
    echo "但 dl/ 中没有找到对应 Linux kernel archive。"

    echo
    echo "当前 dl/ 中 Linux kernel 文件："

    find dl \
        -maxdepth 1 \
        -type f \
        -iname 'linux-*' \
        -print 2>/dev/null |
    sort -V ||
        true

    exit 1

fi


KERNEL_ARCHIVE="$(
    printf '%s\n' "$KERNEL_ARCHIVE_LIST" |
    tail -n 1
)"


echo
echo "找到 kernel archive:"
echo "  $KERNEL_ARCHIVE"


###############################################################################
# 4.5 从实际 archive 名称获取完整 kernel 版本
###############################################################################

KERNEL_ARCHIVE_NAME="$(basename "$KERNEL_ARCHIVE")"


LINUX_VERSION="$(
    printf '%s\n' "$KERNEL_ARCHIVE_NAME" |
    sed -nE \
        's/^linux-([0-9]+\.[0-9]+\.[0-9]+).*\.tar\.(xz|zst|gz|bz2)$/\1/p'
)"


if [ -z "$LINUX_VERSION" ]; then

    echo
    echo "ERROR: 无法从实际 kernel archive 获取完整版本:"
    echo "  $KERNEL_ARCHIVE_NAME"

    exit 1

fi


echo
echo "实际 Linux kernel 版本:"
echo "  $LINUX_VERSION"


###############################################################################
# 4.6 确定 patch 目录
###############################################################################

H68K_PATCH_DIR="target/linux/rockchip/patches-${KERNEL_PATCHVER}"

H68K_PATCH_FILE="${H68K_PATCH_DIR}/999-h68k-gmac-rgmii-fix.patch"


mkdir -p "$H68K_PATCH_DIR"


echo
echo "Kernel patch directory:"
echo "  $H68K_PATCH_DIR"


###############################################################################
# 4.7 建立临时 kernel source
###############################################################################

H68K_WORK_DIR="$(mktemp -d)"


cleanup_h68k()
{
    rm -rf "$H68K_WORK_DIR"
}


trap cleanup_h68k EXIT


echo
echo "========================================"
echo "解压 kernel source"
echo "========================================"


case "$KERNEL_ARCHIVE" in

    *.tar.xz)

        tar -xJf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.zst)

        tar --zstd -xf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.gz)

        tar -xzf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.bz2)

        tar -xjf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *)

        echo
        echo "ERROR: 不支持的 kernel archive:"
        echo "  $KERNEL_ARCHIVE"

        exit 1

        ;;

esac


###############################################################################
# 4.8 自动找到 kernel 根目录
###############################################################################

REAL_KERNEL_DIR=""


while IFS= read -r -d '' dir; do

    if [ -d "$dir/arch/arm64/boot/dts/rockchip" ]; then

        REAL_KERNEL_DIR="$dir"

        break

    fi

done < <(
    find "$H68K_WORK_DIR" \
        -mindepth 1 \
        -maxdepth 2 \
        -type d \
        -path '*/arch/arm64/boot/dts/rockchip' \
        -print0 2>/dev/null |
    sed -z 's@/arch/arm64/boot/dts/rockchip$@@' |
    while IFS= read -r -d '' d; do
        printf '%s\0' "$d"
    done
)


if [ -z "$REAL_KERNEL_DIR" ]; then

    for dir in "$H68K_WORK_DIR"/linux-*; do

        if [ -d "$dir/arch/arm64/boot/dts/rockchip" ]; then

            REAL_KERNEL_DIR="$dir"

            break

        fi

    done

fi


if [ -z "$REAL_KERNEL_DIR" ]; then

    echo
    echo "ERROR: 解压后的 kernel source 无法识别"

    echo
    echo "H68K_WORK_DIR:"
    echo "  $H68K_WORK_DIR"

    exit 1

fi


echo
echo "Kernel source:"
echo "  $REAL_KERNEL_DIR"


###############################################################################
# 4.9 找到真实 H68K DTS
###############################################################################

H68K_DTS_REL="arch/arm64/boot/dts/rockchip/rk3568-hinlink-h68k.dts"

H68K_DTS="${REAL_KERNEL_DIR}/${H68K_DTS_REL}"


if [ ! -f "$H68K_DTS" ]; then

    echo
    echo "ERROR: 当前 kernel source 中不存在 H68K DTS:"
    echo "  $H68K_DTS_REL"

    echo
    echo "当前 rockchip DTS 中与 hinlink/h68k 相关的文件："

    find \
        "$REAL_KERNEL_DIR/arch/arm64/boot/dts/rockchip" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname '*hinlink*' \
            -o -iname '*h68k*' \
        \) \
        -print |
    sort ||
        true

    exit 1

fi


echo
echo "真实 H68K DTS:"
echo "  $H68K_DTS"


###############################################################################
# 4.10 建立临时 git baseline
###############################################################################

cd "$REAL_KERNEL_DIR"


git init -q


git config \
    user.name \
    "DIY2"


git config \
    user.email \
    "diy2@localhost"


git add \
    "$H68K_DTS_REL"


git commit \
    -q \
    -m "DIY2 H68K baseline DTS"


###############################################################################
# 4.11 检查真实 H68K DTS 基础结构
###############################################################################

echo
echo "========================================"
echo "检查真实 H68K DTS"
echo "========================================"


for node in \
    '&gmac0 {' \
    '&gmac1 {' \
    '&mdio0 {' \
    '&mdio1 {'
do

    if ! grep -qF \
        "$node" \
        "$H68K_DTS"
    then

        echo
        echo "ERROR: H68K DTS 不存在:"
        echo "  $node"

        exit 1

    fi

done


echo "gmac0: OK"
echo "gmac1: OK"
echo "mdio0: OK"
echo "mdio1: OK"


###############################################################################
# 4.12 动态修改真实 DTS
###############################################################################

echo
echo "========================================"
echo "根据真实 DTS 生成 H68K GMAC patch"
echo "========================================"


python3 - "$H68K_DTS" <<'PY'
import re
import sys
from pathlib import Path


path = Path(sys.argv[1])

text = path.read_text()


def node_block(text, start, end="\n};"):

    pos = text.find(start)

    if pos < 0:
        raise SystemExit(
            f"ERROR: 找不到节点: {start}"
        )

    endpos = text.find(end, pos)

    if endpos < 0:
        raise SystemExit(
            f"ERROR: 找不到节点结束: {start}"
        )

    endpos += len(end)

    return pos, endpos, text[pos:endpos]


# ============================================================================
# GMAC0
# ============================================================================

a, b, gmac0 = node_block(
    text,
    "&gmac0 {"
)


# phy-mode

if 'phy-mode = "rgmii-id";' in gmac0:

    gmac0 = gmac0.replace(
        'phy-mode = "rgmii-id";',
        'phy-mode = "rgmii";',
        1
    )

elif 'phy-mode = "rgmii";' not in gmac0:

    gmac0 = gmac0.replace(
        "&gmac0 {",
        '&gmac0 {\n\tphy-mode = "rgmii";',
        1
    )


# clock_in_out

if 'clock_in_out = "input";' in gmac0:

    gmac0 = gmac0.replace(
        'clock_in_out = "input";',
        'clock_in_out = "output";',
        1
    )

elif 'clock_in_out = "output";' not in gmac0:

    gmac0 = gmac0.replace(
        "&gmac0 {",
        '&gmac0 {\n\tclock_in_out = "output";',
        1
    )


# reset

if 'snps,reset-gpio' not in gmac0:

    gmac0 = gmac0.replace(
        "&gmac0 {",
        """&gmac0 {
\tsnps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;
\tsnps,reset-active-low;
\tsnps,reset-delays-us = <0 20000 100000>;""",
        1
    )


# clock parent

old_parent = (
    "assigned-clock-parents = <&cru SCLK_GMAC0_RGMII_SPEED>;"
)

new_parent = """assigned-clock-parents = <&cru SCLK_GMAC0_RGMII_SPEED>,
\t\t\t\t<&cru CLK_MAC0_2TOP>;"""


if old_parent in gmac0:

    gmac0 = gmac0.replace(
        old_parent,
        new_parent,
        1
    )

elif "CLK_MAC0_2TOP" not in gmac0:

    raise SystemExit(
        "ERROR: GMAC0 assigned-clock-parents 无法修改"
    )


# pinctrl

gmac0 = gmac0.replace(
    "&gmac0_tx_bus2",
    "&gmac0_tx_bus2_level3",
    1
)

gmac0 = gmac0.replace(
    "&gmac0_rgmii_clk",
    "&gmac0_rgmii_clk_level2",
    1
)

gmac0 = gmac0.replace(
    "&gmac0_rgmii_bus",
    "&gmac0_rgmii_bus_level3",
    1
)


# delay

gmac0 = re.sub(
    r'^[ \t]*tx_delay\s*=\s*<[^>]+>;\s*\n',
    '',
    gmac0,
    flags=re.M
)

gmac0 = re.sub(
    r'^[ \t]*rx_delay\s*=\s*<[^>]+>;\s*\n',
    '',
    gmac0,
    flags=re.M
)


# status

if 'status = "okay";' in gmac0:

    gmac0 = gmac0.replace(
        'status = "okay";',
        'tx_delay = <0x26>;\n'
        '\trx_delay = <0x2a>;\n'
        '\tstatus = "okay";',
        1
    )

else:

    gmac0 += (
        '\n\ttx_delay = <0x26>;\n'
        '\trx_delay = <0x2a>;\n'
    )


text = text[:a] + gmac0 + text[b:]


# ============================================================================
# GMAC1
# ============================================================================

a, b, gmac1 = node_block(
    text,
    "&gmac1 {"
)


# phy-mode

if 'phy-mode = "rgmii-id";' in gmac1:

    gmac1 = gmac1.replace(
        'phy-mode = "rgmii-id";',
        'phy-mode = "rgmii";',
        1
    )

elif 'phy-mode = "rgmii";' not in gmac1:

    gmac1 = gmac1.replace(
        "&gmac1 {",
        '&gmac1 {\n\tphy-mode = "rgmii";',
        1
    )


# clock_in_out

if 'clock_in_out = "input";' in gmac1:

    gmac1 = gmac1.replace(
        'clock_in_out = "input";',
        'clock_in_out = "output";',
        1
    )

elif 'clock_in_out = "output";' not in gmac1:

    gmac1 = gmac1.replace(
        "&gmac1 {",
        '&gmac1 {\n\tclock_in_out = "output";',
        1
    )


# reset

if 'snps,reset-gpio' not in gmac1:

    gmac1 = gmac1.replace(
        "&gmac1 {",
        """&gmac1 {
\tsnps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;
\tsnps,reset-active-low;
\tsnps,reset-delays-us = <0 15000 50000>;""",
        1
    )


# clock parent

old_parent = (
    "assigned-clock-parents = <&cru SCLK_GMAC1_RGMII_SPEED>;"
)

new_parent = """assigned-clock-parents = <&cru SCLK_GMAC1_RGMII_SPEED>,
\t\t\t\t<&cru CLK_MAC1_2TOP>;"""


if old_parent in gmac1:

    gmac1 = gmac1.replace(
        old_parent,
        new_parent,
        1
    )

elif "CLK_MAC1_2TOP" not in gmac1:

    raise SystemExit(
        "ERROR: GMAC1 assigned-clock-parents 无法修改"
    )


# delay

gmac1 = re.sub(
    r'^[ \t]*tx_delay\s*=\s*<[^>]+>;\s*\n',
    '',
    gmac1,
    flags=re.M
)

gmac1 = re.sub(
    r'^[ \t]*rx_delay\s*=\s*<[^>]+>;\s*\n',
    '',
    gmac1,
    flags=re.M
)

gmac1 = re.sub(
    r'^[ \t]*phy-supply\s*=\s*<[^>]+>;\s*\n',
    '',
    gmac1,
    flags=re.M
)


if 'status = "okay";' in gmac1:

    gmac1 = gmac1.replace(
        'status = "okay";',
        'tx_delay = <0x34>;\n'
        '\trx_delay = <0x22>;\n'
        '\tphy-supply = <&vccio_acodec>;\n'
        '\tstatus = "okay";',
        1
    )

else:

    gmac1 += (
        '\n\ttx_delay = <0x34>;\n'
        '\trx_delay = <0x22>;\n'
        '\tphy-supply = <&vccio_acodec>;\n'
    )


text = text[:a] + gmac1 + text[b:]


# ============================================================================
# MDIO0
# ============================================================================

a, b, mdio0 = node_block(
    text,
    "&mdio0 {"
)


if "rgmii_phy0:" not in mdio0:

    raise SystemExit(
        "ERROR: MDIO0 不存在 rgmii_phy0"
    )


if "pinctrl-0 = <&eth_phy0_reset_pin>;" not in mdio0:

    mdio0 = re.sub(
        r'^[ \t]*reset-assert-us\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio0,
        flags=re.M
    )

    mdio0 = re.sub(
        r'^[ \t]*reset-deassert-us\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio0,
        flags=re.M
    )

    mdio0 = re.sub(
        r'^[ \t]*reset-gpios\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio0,
        flags=re.M
    )


    if '\t\treg = <0x1>;' not in mdio0:

        raise SystemExit(
            "ERROR: MDIO0 rgmii_phy0 找不到 reg = <0x1>"
        )


    mdio0 = mdio0.replace(
        '\t\treg = <0x1>;',
        '\t\treg = <0x1>;\n'
        '\t\tpinctrl-0 = <&eth_phy0_reset_pin>;\n'
        '\t\tpinctrl-names = "default";',
        1
    )


text = text[:a] + mdio0 + text[b:]


# ============================================================================
# MDIO1
# ============================================================================

a, b, mdio1 = node_block(
    text,
    "&mdio1 {"
)


if "rgmii_phy1:" not in mdio1:

    raise SystemExit(
        "ERROR: MDIO1 不存在 rgmii_phy1"
    )


if "pinctrl-0 = <&eth_phy1_reset_pin>;" not in mdio1:

    mdio1 = re.sub(
        r'^[ \t]*reset-assert-us\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio1,
        flags=re.M
    )

    mdio1 = re.sub(
        r'^[ \t]*reset-deassert-us\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio1,
        flags=re.M
    )

    mdio1 = re.sub(
        r'^[ \t]*reset-gpios\s*=\s*<[^>]+>;\s*\n',
        '',
        mdio1,
        flags=re.M
    )


    if '\t\treg = <0x1>;' not in mdio1:

        raise SystemExit(
            "ERROR: MDIO1 rgmii_phy1 找不到 reg = <0x1>"
        )


    mdio1 = mdio1.replace(
        '\t\treg = <0x1>;',
        '\t\treg = <0x1>;\n'
        '\t\tpinctrl-0 = <&eth_phy1_reset_pin>;\n'
        '\t\tpinctrl-names = "default";',
        1
    )


text = text[:a] + mdio1 + text[b:]


# ============================================================================
# pinctrl
# ============================================================================

if "eth_phy0_reset_pin:" not in text:

    text += """

&pinctrl {
\tgmac0 {
\t\teth_phy0_reset_pin: eth-phy0-reset-pin {
\t\t\trockchip,pins = <2 RK_PD3 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};

\tgmac1 {
\t\teth_phy1_reset_pin: eth-phy1-reset-pin {
\t\t\trockchip,pins = <1 RK_PB0 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};
};
"""


if "eth_phy1_reset_pin:" not in text:

    raise SystemExit(
        "ERROR: DTS 中无法加入 eth_phy1_reset_pin"
    )


path.write_text(text)
PY


###############################################################################
# 4.13 检查生成后的 DTS
###############################################################################

echo
echo "========================================"
echo "检查生成后的 H68K DTS"
echo "========================================"


check_text()
{
    local pattern="$1"
    local description="$2"

    if ! grep -Fq \
        "$pattern" \
        "$H68K_DTS"
    then

        echo
        echo "ERROR: 缺少:"
        echo "  $description"
        echo "  $pattern"

        exit 1

    fi
}


check_text \
    'phy-mode = "rgmii";' \
    "RGMII mode"


check_text \
    'tx_delay = <0x26>;' \
    "GMAC0 TX delay"


check_text \
    'rx_delay = <0x2a>;' \
    "GMAC0 RX delay"


check_text \
    'tx_delay = <0x34>;' \
    "GMAC1 TX delay"


check_text \
    'rx_delay = <0x22>;' \
    "GMAC1 RX delay"


check_text \
    'CLK_MAC0_2TOP' \
    "GMAC0 clock parent"


check_text \
    'CLK_MAC1_2TOP' \
    "GMAC1 clock parent"


check_text \
    'snps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;' \
    "GMAC0 reset GPIO"


check_text \
    'snps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;' \
    "GMAC1 reset GPIO"


check_text \
    'snps,reset-delays-us = <0 20000 100000>;' \
    "GMAC0 reset timing"


check_text \
    'snps,reset-delays-us = <0 15000 50000>;' \
    "GMAC1 reset timing"


check_text \
    'eth_phy0_reset_pin:' \
    "PHY0 reset pinctrl"


check_text \
    'eth_phy1_reset_pin:' \
    "PHY1 reset pinctrl"


check_text \
    'phy-supply = <&vccio_acodec>;' \
    "GMAC1 vccio_acodec"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$H68K_DTS"
then

    echo
    echo "ERROR: 修复后的 H68K DTS 仍然存在 rgmii-id"

    exit 1

fi


echo
echo "H68K DTS 参数检查通过"


###############################################################################
# 4.14 生成真正的 Git patch
###############################################################################

git add \
    "$H68K_DTS_REL"


H68K_PATCH_TEMP="${H68K_WORK_DIR}/999-h68k-gmac-rgmii-fix.patch"


git diff \
    --cached \
    --no-ext-diff \
    --binary \
    -- "$H68K_DTS_REL" \
    > "$H68K_PATCH_TEMP"


if [ ! -s "$H68K_PATCH_TEMP" ]; then

    echo
    echo "ERROR: Git patch 生成失败"

    exit 1

fi


###############################################################################
# 4.15 安装 patch
###############################################################################

cd "$TOPDIR"


mkdir -p \
    "$H68K_PATCH_DIR"


rm -f \
    "$H68K_PATCH_FILE"


cp \
    "$H68K_PATCH_TEMP" \
    "$H68K_PATCH_FILE"


echo
echo "H68K patch 已生成:"
echo "  $H68K_PATCH_FILE"


###############################################################################
# 4.16 Patch 基本检查
###############################################################################

grep -q \
    'diff --git a/arch/arm64/boot/dts/rockchip/rk3568-hinlink-h68k.dts' \
    "$H68K_PATCH_FILE" || {

    echo
    echo "ERROR: patch 目标 DTS 错误"

    exit 1

}


for pattern in \
    'CLK_MAC0_2TOP' \
    'CLK_MAC1_2TOP' \
    'tx_delay = <0x26>;' \
    'rx_delay = <0x2a>;' \
    'tx_delay = <0x34>;' \
    'rx_delay = <0x22>;' \
    'eth_phy0_reset_pin:' \
    'eth_phy1_reset_pin:'
do

    if ! grep -qF \
        "$pattern" \
        "$H68K_PATCH_FILE"
    then

        echo
        echo "ERROR: patch 缺少:"
        echo "  $pattern"

        exit 1

    fi

done


echo "Patch 基本检查通过"


###############################################################################
# 4.17 OpenWrt kernel prepare
###############################################################################

echo
echo "========================================"
echo "OpenWrt kernel patch 实际应用验证"
echo "========================================"


echo
echo "清理旧 kernel prepare 状态..."


make \
    target/linux/clean \
    V=s


echo
echo "重新 prepare kernel..."


make \
    target/linux/prepare \
    V=s


###############################################################################
# 4.18 找到 OpenWrt 实际准备好的 kernel source
###############################################################################

echo
echo "========================================"
echo "寻找 OpenWrt 实际 kernel source"
echo "========================================"


OPENWRT_H68K_DTS=""


while IFS= read -r -d '' file; do

    OPENWRT_H68K_DTS="$file"

    break

done < <(
    find build_dir \
        -type f \
        -path "*/$H68K_DTS_REL" \
        -print0 2>/dev/null ||
        true
)


if [ -z "$OPENWRT_H68K_DTS" ]; then

    echo
    echo "ERROR: OpenWrt prepare 后找不到 H68K kernel DTS"

    exit 1

fi


OPENWRT_KERNEL_DIR="$(
    cd "$(dirname "$(dirname "$(dirname "$(dirname "$OPENWRT_H68K_DTS")")")")" &&
    pwd
)"


# 上面的路径计算只是辅助显示。
# 实际 DTS 路径始终以 find 得到的文件为准。


echo
echo "OpenWrt 实际 H68K DTS:"
echo "  $OPENWRT_H68K_DTS"


###############################################################################
# 4.19 建立验证 git repository
#
# OpenWrt build_dir 中的 kernel source 不一定存在 .git。
#
# 因此复制：
#
#   OpenWrt prepare 后的 H68K DTS
#
# 到临时 git repo。
#
# 然后：
#
#   git apply --check --reverse
#
# 验证 patch 是否能够完整反向匹配当前 DTS。
###############################################################################

echo
echo "========================================"
echo "执行 git apply --check --reverse"
echo "========================================"


VERIFY_DIR="$(mktemp -d)"

VERIFY_DTS_DIR="$(
    dirname "$H68K_DTS_REL"
)"


mkdir -p \
    "$VERIFY_DIR/$VERIFY_DTS_DIR"


cp \
    "$OPENWRT_H68K_DTS" \
    "$VERIFY_DIR/$H68K_DTS_REL"


cd "$VERIFY_DIR"


git init -q


git config \
    user.name \
    "DIY2 Verify"


git config \
    user.email \
    "diy2-verify@localhost"


git add \
    "$H68K_DTS_REL"


git commit \
    -q \
    -m "OpenWrt prepared H68K DTS"


###############################################################################
# 4.20 git apply --check --reverse
###############################################################################

if ! git apply \
    --check \
    --reverse \
    "$TOPDIR/$H68K_PATCH_FILE"
then

    echo
    echo "========================================"
    echo "ERROR: H68K patch git apply --check 失败"
    echo "========================================"

    echo
    echo "Patch:"
    echo "  $TOPDIR/$H68K_PATCH_FILE"

    echo
    echo "OpenWrt DTS:"
    echo "  $OPENWRT_H68K_DTS"

    echo
    echo "停止编译。"

    rm -rf \
        "$VERIFY_DIR"

    exit 1

fi


echo
echo "git apply --check --reverse: PASS"


###############################################################################
# 4.21 reverse apply 完整验证
###############################################################################

echo
echo "验证 reverse apply 后是否回到 baseline..."


if ! git apply \
    --reverse \
    "$TOPDIR/$H68K_PATCH_FILE"
then

    echo
    echo "ERROR: git apply reverse 实际应用失败"

    rm -rf \
        "$VERIFY_DIR"

    exit 1

fi


if ! git diff \
    --exit-code \
    -- "$H68K_DTS_REL"
then

    echo
    echo "ERROR: reverse apply 后 DTS 与 baseline 不一致"

    rm -rf \
        "$VERIFY_DIR"

    exit 1

fi


echo "reverse apply 完整性验证: PASS"


rm -rf \
    "$VERIFY_DIR"


###############################################################################
# 4.22 最终 H68K DTS 参数验证
###############################################################################

echo
echo "========================================"
echo "最终 H68K GMAC 参数验证"
echo "========================================"


final_check()
{
    local pattern="$1"
    local description="$2"

    if ! grep -Fq \
        "$pattern" \
        "$OPENWRT_H68K_DTS"
    then

        echo
        echo "ERROR: OpenWrt prepare 后缺少:"
        echo "  $description"
        echo "  $pattern"

        exit 1

    fi
}


final_check \
    'phy-mode = "rgmii";' \
    "RGMII mode"


final_check \
    'tx_delay = <0x26>;' \
    "GMAC0 TX delay"


final_check \
    'rx_delay = <0x2a>;' \
    "GMAC0 RX delay"


final_check \
    'tx_delay = <0x34>;' \
    "GMAC1 TX delay"


final_check \
    'rx_delay = <0x22>;' \
    "GMAC1 RX delay"


final_check \
    'CLK_MAC0_2TOP' \
    "GMAC0 clock parent"


final_check \
    'CLK_MAC1_2TOP' \
    "GMAC1 clock parent"


final_check \
    'snps,reset-delays-us = <0 20000 100000>;' \
    "GMAC0 reset timing"


final_check \
    'snps,reset-delays-us = <0 15000 50000>;' \
    "GMAC1 reset timing"


final_check \
    'phy-supply = <&vccio_acodec>;' \
    "GMAC1 phy-supply"


final_check \
    'eth_phy0_reset_pin:' \
    "PHY0 reset pinctrl"


final_check \
    'eth_phy1_reset_pin:' \
    "PHY1 reset pinctrl"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$OPENWRT_H68K_DTS"
then

    echo
    echo "ERROR: OpenWrt prepare 后仍然存在 rgmii-id"

    exit 1

fi


###############################################################################
# 4.23 H68K 修复完成
###############################################################################

echo
echo "========================================"
echo "H68K 1G 网口修复验证全部通过"
echo "========================================"


echo
echo "Kernel:"
echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
echo "  LINUX_VERSION   = $LINUX_VERSION"


echo
echo "GMAC0:"
echo "  phy-mode       = rgmii"
echo "  clock parent   = CLK_MAC0_2TOP"
echo "  tx_delay       = 0x26"
echo "  rx_delay       = 0x2a"
echo "  reset GPIO     = GPIO2_PD3"
echo "  reset timing   = 0 / 20ms / 100ms"


echo
echo "GMAC1:"
echo "  phy-mode       = rgmii"
echo "  clock parent   = CLK_MAC1_2TOP"
echo "  tx_delay       = 0x34"
echo "  rx_delay       = 0x22"
echo "  reset GPIO     = GPIO1_PB0"
echo "  reset timing   = 0 / 15ms / 50ms"
echo "  phy-supply     = vccio_acodec"


echo
echo "Patch:"
echo "  $H68K_PATCH_FILE"


echo
echo "git apply --check --reverse: PASS"
echo "reverse apply 完整性: PASS"
echo "OpenWrt target/linux/prepare: PASS"
echo "最终 DTS 参数检查: PASS"


echo
echo "H68K 1G RTL8211F 修复已实际套入 OpenWrt kernel source。"
echo "继续执行后续 DIY2。"


###############################################################################
# 5. 扫描 package/myapp 真正的 Package
###############################################################################

cd "$TOPDIR"


echo
echo "========================================"
echo "扫描 DIY1 独立第三方插件"
echo "========================================"


MYAPP_PACKAGES=""


if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

        case "$pkg" in
            \(*|\(*\)*|*/*)
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
        sort -u ||
            true
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
            "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*" \
            "$mf" 2>/dev/null
        then

            MYAPP_MAKEFILE="$mf"

            break

        fi

    done < <(
        find package/myapp \
            -type f \
            -name Makefile \
            -print0 2>/dev/null ||
            true
    )


    if [ -n "$MYAPP_MAKEFILE" ]; then

        MYAPP_VERSION="$(
            get_package_version \
                "$MYAPP_MAKEFILE"
        )"

        echo "package/myapp 版本: $MYAPP_VERSION"

    else

        MYAPP_VERSION="unknown"

    fi


    for feed in \
        $THIRD_PARTY_FEEDS \
        $OFFICIAL_FEEDS
    do

        if package_entry_exists \
            "$feed" \
            "$pkg"
        then

            MAKEFILE="$(
                package_makefile \
                    "$feed" \
                    "$pkg"
            )"

            VERSION="$(
                get_package_version \
                    "$MAKEFILE"
            )"


            echo "发现重复来源:"
            echo "  $feed/$pkg"
            echo "  版本: $VERSION"
            echo "选择: package/myapp"
            echo "原因: 独立第三方源码优先"


            remove_package_entry \
                "$feed" \
                "$pkg"

        fi

    done

done


###############################################################################
# 8. 第三方集合源优先
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


    for third_feed in \
        $THIRD_PARTY_FEEDS
    do

        if package_entry_exists \
            "$third_feed" \
            "$pkg"
        then

            THIRD_SOURCE="$third_feed"

            break

        fi

    done


    [ -n "$THIRD_SOURCE" ] || continue


    THIRD_MAKEFILE="$(
        package_makefile \
            "$THIRD_SOURCE" \
            "$pkg"
    )"


    THIRD_VERSION="$(
        get_package_version \
            "$THIRD_MAKEFILE"
    )"


    echo
    echo "发现第三方重复包: $pkg"
    echo "第三方来源: ${THIRD_SOURCE}/${pkg}"
    echo "第三方版本: $THIRD_VERSION"


    for official_feed in \
        $OFFICIAL_FEEDS
    do

        if package_entry_exists \
            "$official_feed" \
            "$pkg"
        then

            OFFICIAL_MAKEFILE="$(
                package_makefile \
                    "$official_feed" \
                    "$pkg"
            )"


            OFFICIAL_VERSION="$(
                get_package_version \
                    "$OFFICIAL_MAKEFILE"
            )"


            echo "官方来源: ${official_feed}/${pkg}"
            echo "官方版本: $OFFICIAL_VERSION"


            if [ "$THIRD_VERSION" = "$OFFICIAL_VERSION" ]; then

                echo "版本相同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"

            else

                echo "版本不同 -> 选择: 第三方 ${THIRD_SOURCE}/${pkg}"
                echo "原因: 第三方来源优先，不按版本号自动选择"

            fi


            remove_package_entry \
                "$official_feed" \
                "$pkg"

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
# 10. 自动添加 LuCI 中文语言包
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
            .config 2>/dev/null
        then

            continue

        fi


        if grep -rnq \
            "Package.*${trans}-zh-cn" \
            package feeds 2>/dev/null
        then

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


mkdir -p \
    files/etc/uci-defaults


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


chmod +x \
    files/etc/uci-defaults/zz-enable-wifi


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


    if [ -d package/myapp ]; then

        FOUND_MYAPP=""


        while IFS= read -r -d '' mf; do

            [ -f "$mf" ] || continue


            if grep -q \
                "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*" \
                "$mf" 2>/dev/null
            then

                FOUND_MYAPP="$mf"

                break

            fi

        done < <(
            find package/myapp \
                -type f \
                -name Makefile \
                -print0 2>/dev/null ||
                true
        )


        if [ -n "$FOUND_MYAPP" ]; then

            echo "  package/myapp"

            echo \
                "  version: $(get_package_version "$FOUND_MYAPP")"

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


echo
echo "H68K 1G RTL8211F 修复状态:"
echo "  KERNEL_PATCHVER:          $KERNEL_PATCHVER"
echo "  LINUX_VERSION:            $LINUX_VERSION"
echo "  Patch:                    OK"
echo "  OpenWrt prepare:          OK"
echo "  git apply --check:        PASS"
echo "  reverse apply:            PASS"
echo "  DTS 参数验证:             OK"


echo
echo "GMAC0:"
echo "  phy-mode       = rgmii"
echo "  clock parent   = CLK_MAC0_2TOP"
echo "  tx_delay       = 0x26"
echo "  rx_delay       = 0x2a"
echo "  reset GPIO     = GPIO2_PD3"
echo "  reset timing   = 0 / 20ms / 100ms"


echo
echo "GMAC1:"
echo "  phy-mode       = rgmii"
echo "  clock parent   = CLK_MAC1_2TOP"
echo "  tx_delay       = 0x34"
echo "  rx_delay       = 0x22"
echo "  reset GPIO     = GPIO1_PB0"
echo "  reset timing   = 0 / 15ms / 50ms"
echo "  phy-supply     = vccio_acodec"


echo
echo "H68K patch:"
echo "  $H68K_PATCH_FILE"


echo
echo "========================================"
echo "DIY2 全部完成"
echo "========================================"

echo
echo "可以继续正式编译。"
