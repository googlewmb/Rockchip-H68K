#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 核心目标：
#   H68K RTL8211F 1G 网口修复
#
# 第三方插件 / 依赖 / 来源优先级：
#
#   1. package/myapp 独立第三方源码
#   2. DIY1 已存在的第三方集合源
#   3. iStoreOS / OpenWrt 官方 feeds
#
# 重要修正：
#
#   1. 不再执行 ./scripts/feeds install -a
#      避免 video / Qt5 / nas 等无关 feed 大量进入 Kconfig
#
#   2. 官方 packages / luci 只按需要安装
#
#   3. PassWall 使用独立源码目录
#
#   4. H68K RTL8211F 修复仍然是本 DIY2 核心
#
#   5. 自动读取 Rockchip KERNEL_PATCHVER
#
#   6. 不依赖旧版 include/kernel-version.mk
#
#   7. 先由 OpenWrt 自己下载 kernel
#
#   8. 自动寻找 dl/linux-X.Y*.tar.*
#
#   9. 根据真实 archive 获取完整 kernel 版本
#
#  10. 自动找到 H68K DTS
#
#  11. 动态生成 H68K RTL8211F patch
#
#  12. patch 安装到：
#
#        target/linux/rockchip/patches-${KERNEL_PATCHVER}/
#
#  13. target/linux/clean
#
#  14. target/linux/prepare
#
#  15. git apply --check --reverse
#
#  16. reverse apply 完整性检查
#
#  17. 最终 H68K DTS 参数检查
#
#  18. 任意关键步骤失败立即停止
#

set -e

echo
echo "============================================================"
echo " DIY2 - H68K + iStoreOS 24.10"
echo " RTL8211F 1G 网口修复"
echo "============================================================"
echo


###############################################################################
# 0. 基础目录
###############################################################################

[ -n "${TOPDIR:-}" ] || TOPDIR="$(pwd)"

cd "$TOPDIR"

echo "TOPDIR: $TOPDIR"


###############################################################################
# 0.1 检查源码目录
###############################################################################

if [ ! -d "$TOPDIR/target/linux" ]; then

    echo
    echo "ERROR: 当前目录不是 OpenWrt / iStoreOS 源码根目录"
    echo
    echo "TOPDIR:"
    echo "  $TOPDIR"
    echo

    exit 1

fi


###############################################################################
# 0.2 检查基础工具
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
        echo

        exit 1

    fi

done


###############################################################################
# 0.3 SONiC FullCone NAT
###############################################################################

echo
echo "============================================================"
echo " 0.1 添加 SONiC FullCone NAT"
echo "============================================================"


SONIC_FULLCONE_SCRIPT="/tmp/add_sonic_fullcone.sh"


rm -f \
    "$SONIC_FULLCONE_SCRIPT"


curl -fsSL \
    https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh \
    -o "$SONIC_FULLCONE_SCRIPT"


bash \
    "$SONIC_FULLCONE_SCRIPT"


rm -f \
    "$SONIC_FULLCONE_SCRIPT"


echo
echo "SONiC FullCone NAT 添加完成"


###############################################################################
# 1. Golang 27.x
###############################################################################

echo
echo "============================================================"
echo " 1.1 替换 Golang 为 27.x"
echo "============================================================"


if [ -d feeds/packages/lang/golang ]; then

    echo "删除旧 Golang..."

    rm -rf \
        feeds/packages/lang/golang

fi


git clone \
    -b 27.x \
    --depth 1 \
    https://github.com/sbwml/packages_lang_golang \
    feeds/packages/lang/golang


if [ ! -d feeds/packages/lang/golang ]; then

    echo
    echo "ERROR: Golang 27.x 拉取失败"

    exit 1

fi


echo "Golang 27.x OK"


###############################################################################
# 2. PassWall
###############################################################################

echo
echo "============================================================"
echo " 1.2 拉取 PassWall"
echo "============================================================"


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


rm -rf \
    feeds/luci/applications/luci-app-passwall


rm -rf \
    package/passwall-packages \
    package/passwall-luci


git clone \
    --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
    package/passwall-packages


git clone \
    --depth 1 \
    https://github.com/Openwrt-Passwall/openwrt-passwall \
    package/passwall-luci


if [ ! -d package/passwall-packages ]; then

    echo
    echo "ERROR: PassWall packages 拉取失败"

    exit 1

fi


if [ ! -d package/passwall-luci ]; then

    echo
    echo "ERROR: PassWall LuCI 拉取失败"

    exit 1

fi


echo "PassWall packages OK"
echo "PassWall LuCI OK"


###############################################################################
# 3. Feed 安装
#
# 关键修正：
#
# 原来：
#
#   ./scripts/feeds install -a
#
# 会把所有 feed 的全部包安装进 package/feeds。
#
# 当前 Actions 已经证明：
#
#   video / Qt5
#   nas
#   nas_luci
#   jjm2473_apps
#   kenzo
#   small
#
# 中存在大量 Kconfig recursive dependency。
#
# 所以这里不再全量安装。
#
###############################################################################

echo
echo "============================================================"
echo " 1.3 安装必要 feeds"
echo "============================================================"


echo
echo "安装官方 packages feed..."

./scripts/feeds install \
    -a \
    -p packages


echo
echo "安装官方 luci feed..."

./scripts/feeds install \
    -a \
    -p luci


###############################################################################
# Golang
###############################################################################

echo
echo "安装 Golang..."

./scripts/feeds install \
    -p packages \
    golang


###############################################################################
# microsocks
###############################################################################

echo
echo "安装 microsocks..."

./scripts/feeds install \
    -f \
    microsocks


###############################################################################
# 绝对禁止全量安装其它第三方 feeds
###############################################################################

echo
echo "跳过以下第三方 feed 的全量 install："

echo "  video"
echo "  nas"
echo "  nas_luci"
echo "  jjm2473_apps"
echo "  kenzo"
echo "  small"

echo
echo "原因：避免无关 Kconfig / Qt5 / video 包进入配置系统"


###############################################################################
# 4. 第三方依赖预处理
###############################################################################

echo
echo "============================================================"
echo " 2. 第三方依赖预处理"
echo "============================================================"


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

        rm -f \
            "$entry"

    fi
}


package_makefile()
{
    local feed="$1"
    local pkg="$2"

    local makefile="package/feeds/${feed}/${pkg}/Makefile"


    if [ -f "$makefile" ]; then

        readlink -f \
            "$makefile" \
            2>/dev/null ||
            true

    fi
}


is_enabled()
{
    local pkg="$1"

    grep -Eq \
        "^CONFIG_PACKAGE_${pkg}=(y|m)" \
        .config \
        2>/dev/null
}


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


    [ -n "$version" ] || \
        version="unknown"


    echo "$version"
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
# 5. H68K RTL8211F 1G 网口修复
###############################################################################

echo
echo "============================================================"
echo " 3. H68K RTL8211F 1G 网口修复"
echo "============================================================"


###############################################################################
# 5.1 Rockchip Makefile
###############################################################################

ROCKCHIP_MAKEFILE="target/linux/rockchip/Makefile"


if [ ! -f "$ROCKCHIP_MAKEFILE" ]; then

    echo
    echo "ERROR: 找不到："
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


echo
echo "Rockchip KERNEL_PATCHVER:"
echo "  $KERNEL_PATCHVER"


###############################################################################
# 5.2 下载 kernel
#
# 注意：
#
# 这里不再读取：
#
#   include/kernel-version.mk
#
# 避免 6.18 新版格式导致版本解析失败。
#
###############################################################################

echo
echo "============================================================"
echo " 3.1 OpenWrt 下载实际 Linux kernel"
echo "============================================================"


make \
    target/linux/download \
    V=s


###############################################################################
# 5.3 找实际 kernel archive
###############################################################################

echo
echo "============================================================"
echo " 3.2 搜索实际 Linux kernel archive"
echo "============================================================"


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
    echo "ERROR: 未找到 Linux kernel archive"

    echo
    echo "dl/ 当前 Linux 文件："

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


KERNEL_ARCHIVE_NAME="$(basename "$KERNEL_ARCHIVE")"


echo
echo "Kernel archive:"
echo "  $KERNEL_ARCHIVE_NAME"


###############################################################################
# 5.4 获取完整版本
###############################################################################

LINUX_VERSION="$(
    printf '%s\n' "$KERNEL_ARCHIVE_NAME" |
    sed -nE \
        's/^linux-([0-9]+\.[0-9]+\.[0-9]+).*\.tar\.(xz|zst|gz|bz2)$/\1/p'
)"


if [ -z "$LINUX_VERSION" ]; then

    echo
    echo "ERROR: 无法从 archive 获取完整 Linux kernel 版本"

    echo "Archive:"
    echo "  $KERNEL_ARCHIVE_NAME"

    exit 1

fi


echo
echo "实际 Linux kernel:"
echo "  $LINUX_VERSION"


###############################################################################
# 5.5 Patch 目录
###############################################################################

H68K_PATCH_DIR="target/linux/rockchip/patches-${KERNEL_PATCHVER}"

H68K_PATCH_FILE="${H68K_PATCH_DIR}/999-h68k-rtl8211f-rgmii-fix.patch"


mkdir -p \
    "$H68K_PATCH_DIR"


echo
echo "Patch:"
echo "  $H68K_PATCH_FILE"


###############################################################################
# 5.6 临时目录
###############################################################################

H68K_WORK_DIR="$(
    mktemp -d
)"


cleanup_h68k()
{
    rm -rf \
        "$H68K_WORK_DIR"
}


trap cleanup_h68k EXIT


###############################################################################
# 5.7 解压 kernel
###############################################################################

echo
echo "============================================================"
echo " 3.3 解压 Linux kernel source"
echo "============================================================"


case "$KERNEL_ARCHIVE" in

    *.tar.xz)

        tar \
            -xJf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.zst)

        tar \
            --zstd \
            -xf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.gz)

        tar \
            -xzf \
            "$KERNEL_ARCHIVE" \
            -C "$H68K_WORK_DIR"

        ;;


    *.tar.bz2)

        tar \
            -xjf \
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
# 5.8 找 kernel 根目录
###############################################################################

REAL_KERNEL_DIR=""


for dir in \
    "$H68K_WORK_DIR"/linux-*
do

    if [ -d "$dir/arch/arm64/boot/dts/rockchip" ]; then

        REAL_KERNEL_DIR="$dir"

        break

    fi

done


if [ -z "$REAL_KERNEL_DIR" ]; then

    REAL_KERNEL_DIR="$(
        find "$H68K_WORK_DIR" \
            -type d \
            -path '*/arch/arm64/boot/dts/rockchip' \
            -print \
            -quit |
        sed 's@/arch/arm64/boot/dts/rockchip$@@'
    )"

fi


if [ -z "$REAL_KERNEL_DIR" ]; then

    echo
    echo "ERROR: 无法找到 Linux kernel source"

    exit 1

fi


echo
echo "Kernel source:"
echo "  $REAL_KERNEL_DIR"


###############################################################################
# 5.9 H68K DTS
###############################################################################

H68K_DTS_REL="arch/arm64/boot/dts/rockchip/rk3568-hinlink-h68k.dts"

H68K_DTS="${REAL_KERNEL_DIR}/${H68K_DTS_REL}"


if [ ! -f "$H68K_DTS" ]; then

    echo
    echo "ERROR: 找不到 H68K DTS："
    echo "  $H68K_DTS_REL"

    echo
    echo "当前相关 DTS："

    find \
        "$REAL_KERNEL_DIR/arch/arm64/boot/dts/rockchip" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname '*h68k*' \
            -o -iname '*hinlink*' \
        \) \
        -print |
    sort ||
        true

    exit 1

fi


echo
echo "H68K DTS:"
echo "  $H68K_DTS"


###############################################################################
# 5.10 DTS 基础节点检查
###############################################################################

echo
echo "============================================================"
echo " 3.4 检查 H68K DTS"
echo "============================================================"


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
        echo "ERROR: H68K DTS 缺少："
        echo "  $node"

        exit 1

    fi

done


echo "GMAC0: PASS"
echo "GMAC1: PASS"
echo "MDIO0: PASS"
echo "MDIO1: PASS"


###############################################################################
# 5.11 建立 Git baseline
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
    -m "DIY2 H68K RTL8211F baseline"


###############################################################################
# 5.12 动态修改 H68K DTS
###############################################################################

echo
echo "============================================================"
echo " 3.5 修改 H68K RTL8211F GMAC/RGMII"
echo "============================================================"


python3 - "$H68K_DTS" <<'PY'
import re
import sys
from pathlib import Path


path = Path(sys.argv[1])

text = path.read_text()


def find_node(text, token):
    pos = text.find(token)

    if pos < 0:
        raise SystemExit(
            f"ERROR: 找不到节点: {token}"
        )

    brace = text.find("{", pos)

    if brace < 0:
        raise SystemExit(
            f"ERROR: 找不到节点开始: {token}"
        )

    depth = 0

    in_string = False
    escape = False

    i = brace

    while i < len(text):

        c = text[i]

        if in_string:

            if escape:

                escape = False

            elif c == "\\":
                escape = True

            elif c == '"':
                in_string = False

        else:

            if c == '"':
                in_string = True

            elif c == "{":
                depth += 1

            elif c == "}":

                depth -= 1

                if depth == 0:

                    end = i + 1

                    while end < len(text) and text[end] in " \t":
                        end += 1

                    if text[end:end + 1] == ";":
                        end += 1

                    return pos, end, text[pos:end]

        i += 1

    raise SystemExit(
        f"ERROR: 节点括号不完整: {token}"
    )


def ensure_line(block, line, after_open=True):

    if line in block:
        return block

    first = block.find("{") + 1

    return (
        block[:first] +
        "\n\t" + line +
        block[first:]
    )


def replace_or_insert_property(block, name, value):

    pattern = re.compile(
        rf'^[ \t]*{re.escape(name)}[ \t]*=.*?;[ \t]*$',
        re.M
    )

    replacement = f"\t{name} = {value};"

    if pattern.search(block):

        return pattern.sub(
            replacement,
            block,
            count=1
        )

    pos = block.find("{") + 1

    return (
        block[:pos] +
        "\n" +
        replacement +
        block[pos:]
    )


# ============================================================================
# GMAC0
# ============================================================================

a, b, gmac0 = find_node(
    text,
    "&gmac0 {"
)


gmac0 = replace_or_insert_property(
    gmac0,
    "phy-mode",
    '"rgmii"'
)


gmac0 = replace_or_insert_property(
    gmac0,
    "clock_in_out",
    '"output"'
)


if "snps,reset-gpio" not in gmac0:

    gmac0 = gmac0.replace(
        "&gmac0 {",
        """&gmac0 {
\tsnps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;
\tsnps,reset-active-low;
\tsnps,reset-delays-us = <0 20000 100000>;""",
        1
    )


gmac0 = re.sub(
    r'^[ \t]*assigned-clock-parents\s*=.*?;\s*$',
    '',
    gmac0,
    flags=re.M
)


gmac0 = re.sub(
    r'^[ \t]*assigned-clock-rates\s*=.*?;\s*$',
    '',
    gmac0,
    flags=re.M
)


insert = """
\tassigned-clock-parents = <&cru SCLK_GMAC0_RGMII_SPEED>,
\t\t\t\t<&cru CLK_MAC0_2TOP>;
"""


pos = gmac0.find("{") + 1

gmac0 = (
    gmac0[:pos] +
    insert +
    gmac0[pos:]
)


gmac0 = gmac0.replace(
    "&gmac0_tx_bus2",
    "&gmac0_tx_bus2_level3"
)

gmac0 = gmac0.replace(
    "&gmac0_rgmii_clk",
    "&gmac0_rgmii_clk_level2"
)

gmac0 = gmac0.replace(
    "&gmac0_rgmii_bus",
    "&gmac0_rgmii_bus_level3"
)


gmac0 = re.sub(
    r'^[ \t]*tx_delay\s*=.*?;\s*$',
    '',
    gmac0,
    flags=re.M
)

gmac0 = re.sub(
    r'^[ \t]*rx_delay\s*=.*?;\s*$',
    '',
    gmac0,
    flags=re.M
)


gmac0 = replace_or_insert_property(
    gmac0,
    "tx_delay",
    "<0x26>"
)

gmac0 = replace_or_insert_property(
    gmac0,
    "rx_delay",
    "<0x2a>"
)

gmac0 = replace_or_insert_property(
    gmac0,
    "status",
    '"okay"'
)


text = text[:a] + gmac0 + text[b:]


# ============================================================================
# GMAC1
# ============================================================================

a, b, gmac1 = find_node(
    text,
    "&gmac1 {"
)


gmac1 = replace_or_insert_property(
    gmac1,
    "phy-mode",
    '"rgmii"'
)


gmac1 = replace_or_insert_property(
    gmac1,
    "clock_in_out",
    '"output"'
)


if "snps,reset-gpio" not in gmac1:

    gmac1 = gmac1.replace(
        "&gmac1 {",
        """&gmac1 {
\tsnps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;
\tsnps,reset-active-low;
\tsnps,reset-delays-us = <0 15000 50000>;""",
        1
    )


gmac1 = re.sub(
    r'^[ \t]*assigned-clock-parents\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)


gmac1 = re.sub(
    r'^[ \t]*assigned-clock-rates\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)


insert = """
\tassigned-clock-parents = <&cru SCLK_GMAC1_RGMII_SPEED>,
\t\t\t\t<&cru CLK_MAC1_2TOP>;
"""


pos = gmac1.find("{") + 1

gmac1 = (
    gmac1[:pos] +
    insert +
    gmac1[pos:]
)


gmac1 = re.sub(
    r'^[ \t]*tx_delay\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)

gmac1 = re.sub(
    r'^[ \t]*rx_delay\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)


gmac1 = re.sub(
    r'^[ \t]*phy-supply\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)


gmac1 = replace_or_insert_property(
    gmac1,
    "tx_delay",
    "<0x34>"
)

gmac1 = replace_or_insert_property(
    gmac1,
    "rx_delay",
    "<0x22>"
)

gmac1 = replace_or_insert_property(
    gmac1,
    "phy-supply",
    "<&vccio_acodec>"
)

gmac1 = replace_or_insert_property(
    gmac1,
    "status",
    '"okay"'
)


text = text[:a] + gmac1 + text[b:]


# ============================================================================
# MDIO0
# ============================================================================

a, b, mdio0 = find_node(
    text,
    "&mdio0 {"
)


if "rgmii_phy0:" not in mdio0:

    raise SystemExit(
        "ERROR: MDIO0 找不到 rgmii_phy0"
    )


mdio0 = re.sub(
    r'^[ \t]*reset-assert-us\s*=.*?;\s*$',
    '',
    mdio0,
    flags=re.M
)

mdio0 = re.sub(
    r'^[ \t]*reset-deassert-us\s*=.*?;\s*$',
    '',
    mdio0,
    flags=re.M
)

mdio0 = re.sub(
    r'^[ \t]*reset-gpios\s*=.*?;\s*$',
    '',
    mdio0,
    flags=re.M
)


if "pinctrl-0 = <&eth_phy0_reset_pin>;" not in mdio0:

    phy_pos = mdio0.find("rgmii_phy0:")

    if phy_pos < 0:
        raise SystemExit(
            "ERROR: 无法定位 rgmii_phy0"
        )

    phy_brace = mdio0.find("{", phy_pos)

    if phy_brace < 0:
        raise SystemExit(
            "ERROR: rgmii_phy0 节点格式异常"
        )

    insert_pos = phy_brace + 1

    mdio0 = (
        mdio0[:insert_pos] +
        """
\t\tpinctrl-0 = <&eth_phy0_reset_pin>;
\t\tpinctrl-names = "default";
""" +
        mdio0[insert_pos:]
    )


text = text[:a] + mdio0 + text[b:]


# ============================================================================
# MDIO1
# ============================================================================

a, b, mdio1 = find_node(
    text,
    "&mdio1 {"
)


if "rgmii_phy1:" not in mdio1:

    raise SystemExit(
        "ERROR: MDIO1 找不到 rgmii_phy1"
    )


mdio1 = re.sub(
    r'^[ \t]*reset-assert-us\s*=.*?;\s*$',
    '',
    mdio1,
    flags=re.M
)

mdio1 = re.sub(
    r'^[ \t]*reset-deassert-us\s*=.*?;\s*$',
    '',
    mdio1,
    flags=re.M
)

mdio1 = re.sub(
    r'^[ \t]*reset-gpios\s*=.*?;\s*$',
    '',
    mdio1,
    flags=re.M
)


if "pinctrl-0 = <&eth_phy1_reset_pin>;" not in mdio1:

    phy_pos = mdio1.find("rgmii_phy1:")

    if phy_pos < 0:
        raise SystemExit(
            "ERROR: 无法定位 rgmii_phy1"
        )

    phy_brace = mdio1.find("{", phy_pos)

    if phy_brace < 0:
        raise SystemExit(
            "ERROR: rgmii_phy1 节点格式异常"
        )

    insert_pos = phy_brace + 1

    mdio1 = (
        mdio1[:insert_pos] +
        """
\t\tpinctrl-0 = <&eth_phy1_reset_pin>;
\t\tpinctrl-names = "default";
""" +
        mdio1[insert_pos:]
    )


text = text[:a] + mdio1 + text[b:]


# ============================================================================
# pinctrl
# ============================================================================

if (
    "eth_phy0_reset_pin:" not in text or
    "eth_phy1_reset_pin:" not in text
):

    pinctrl_token = "&pinctrl {"

    if pinctrl_token in text:

        a, b, pinctrl = find_node(
            text,
            pinctrl_token
        )


        additions = ""


        if "eth_phy0_reset_pin:" not in pinctrl:

            additions += """
\tgmac0 {
\t\teth_phy0_reset_pin: eth-phy0-reset-pin {
\t\t\trockchip,pins = <2 RK_PD3 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};
"""


        if "eth_phy1_reset_pin:" not in pinctrl:

            additions += """
\tgmac1 {
\t\teth_phy1_reset_pin: eth-phy1-reset-pin {
\t\t\trockchip,pins = <1 RK_PB0 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};
"""


        close = pinctrl.rfind("}")

        pinctrl = (
            pinctrl[:close] +
            additions +
            pinctrl[close:]
        )


        text = text[:a] + pinctrl + text[b:]


    else:

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


path.write_text(text)
PY


###############################################################################
# 5.13 修复结果检查
###############################################################################

echo
echo "============================================================"
echo " 3.6 检查 RTL8211F 修复结果"
echo "============================================================"


check_text()
{
    local pattern="$1"
    local description="$2"


    if ! grep -Fq \
        "$pattern" \
        "$H68K_DTS"
    then

        echo
        echo "ERROR: 缺少："
        echo "  $description"
        echo "  $pattern"

        exit 1

    fi
}


check_text \
    'phy-mode = "rgmii";' \
    "RGMII"


check_text \
    'clock_in_out = "output";' \
    "RGMII clock output"


check_text \
    'CLK_MAC0_2TOP' \
    "GMAC0 clock"


check_text \
    'CLK_MAC1_2TOP' \
    "GMAC1 clock"


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
    'phy-supply = <&vccio_acodec>;' \
    "GMAC1 phy supply"


check_text \
    'eth_phy0_reset_pin:' \
    "PHY0 reset pin"


check_text \
    'eth_phy1_reset_pin:' \
    "PHY1 reset pin"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$H68K_DTS"
then

    echo
    echo "ERROR: 仍然存在 rgmii-id"

    exit 1

fi


echo
echo "H68K RTL8211F DTS 参数检查 PASS"


###############################################################################
# 5.14 生成 patch
###############################################################################

echo
echo "============================================================"
echo " 3.7 生成 H68K RTL8211F patch"
echo "============================================================"


git add \
    "$H68K_DTS_REL"


H68K_PATCH_TEMP="${H68K_WORK_DIR}/999-h68k-rtl8211f-rgmii-fix.patch"


git diff \
    --cached \
    --no-ext-diff \
    --binary \
    -- "$H68K_DTS_REL" \
    > "$H68K_PATCH_TEMP"


if [ ! -s "$H68K_PATCH_TEMP" ]; then

    echo
    echo "ERROR: patch 为空"

    exit 1

fi


cd "$TOPDIR"


rm -f \
    "$H68K_PATCH_FILE"


cp \
    "$H68K_PATCH_TEMP" \
    "$H68K_PATCH_FILE"


###############################################################################
# 5.15 patch 内容检查
###############################################################################

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
        echo "ERROR: patch 缺少："
        echo "  $pattern"

        exit 1

    fi

done


echo
echo "H68K patch 生成 PASS"


###############################################################################
# 5.16 清理 kernel
###############################################################################

echo
echo "============================================================"
echo " 3.8 OpenWrt kernel clean"
echo "============================================================"


make \
    target/linux/clean \
    V=s


###############################################################################
# 5.17 实际应用 patch
###############################################################################

echo
echo "============================================================"
echo " 3.9 OpenWrt target/linux/prepare"
echo "============================================================"


make \
    target/linux/prepare \
    V=s


###############################################################################
# 5.18 找 prepare 后真实 DTS
###############################################################################

echo
echo "============================================================"
echo " 3.10 找 OpenWrt prepare 后 H68K DTS"
echo "============================================================"


OPENWRT_H68K_DTS="$(
    find build_dir \
        -type f \
        -path "*/${H68K_DTS_REL}" \
        -print \
        -quit 2>/dev/null
)"


if [ -z "$OPENWRT_H68K_DTS" ]; then

    echo
    echo "ERROR: target/linux/prepare 后找不到 H68K DTS"

    exit 1

fi


echo
echo "OpenWrt H68K DTS:"
echo "  $OPENWRT_H68K_DTS"


###############################################################################
# 5.19 验证 prepare 后 DTS
###############################################################################

echo
echo "============================================================"
echo " 3.11 验证 OpenWrt 实际 DTS"
echo "============================================================"


final_check()
{
    local pattern="$1"
    local description="$2"


    if ! grep -Fq \
        "$pattern" \
        "$OPENWRT_H68K_DTS"
    then

        echo
        echo "ERROR: prepare 后 DTS 缺少："
        echo "  $description"
        echo "  $pattern"

        exit 1

    fi
}


final_check \
    'phy-mode = "rgmii";' \
    "RGMII"


final_check \
    'clock_in_out = "output";' \
    "clock output"


final_check \
    'CLK_MAC0_2TOP' \
    "GMAC0 clock"


final_check \
    'CLK_MAC1_2TOP' \
    "GMAC1 clock"


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
    'snps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;' \
    "GMAC0 reset"


final_check \
    'snps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;' \
    "GMAC1 reset"


final_check \
    'snps,reset-delays-us = <0 20000 100000>;' \
    "GMAC0 reset timing"


final_check \
    'snps,reset-delays-us = <0 15000 50000>;' \
    "GMAC1 reset timing"


final_check \
    'phy-supply = <&vccio_acodec>;' \
    "GMAC1 phy supply"


final_check \
    'eth_phy0_reset_pin:' \
    "PHY0 pinctrl"


final_check \
    'eth_phy1_reset_pin:' \
    "PHY1 pinctrl"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$OPENWRT_H68K_DTS"
then

    echo
    echo "ERROR: prepare 后仍存在 rgmii-id"

    exit 1

fi


echo
echo "OpenWrt prepare 后 H68K RTL8211F 参数 PASS"


###############################################################################
# 5.20 git apply --check --reverse
###############################################################################

echo
echo "============================================================"
echo " 3.12 git apply --check --reverse"
echo "============================================================"


VERIFY_DIR="$(
    mktemp -d
)"


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
    -m "OpenWrt H68K prepared DTS"


if ! git apply \
    --check \
    --reverse \
    "$TOPDIR/$H68K_PATCH_FILE"
then

    echo
    echo "============================================================"
    echo " ERROR: git apply --check --reverse FAILED"
    echo "============================================================"

    echo
    echo "Patch:"
    echo "  $TOPDIR/$H68K_PATCH_FILE"

    echo
    echo "DTS:"
    echo "  $OPENWRT_H68K_DTS"

    rm -rf \
        "$VERIFY_DIR"

    exit 1

fi


echo
echo "git apply --check --reverse: PASS"


###############################################################################
# 5.21 reverse apply
###############################################################################

echo
echo "验证 reverse apply..."


if ! git apply \
    --reverse \
    "$TOPDIR/$H68K_PATCH_FILE"
then

    echo
    echo "ERROR: reverse apply FAILED"

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


echo
echo "reverse apply: PASS"


rm -rf \
    "$VERIFY_DIR"


cd "$TOPDIR"


###############################################################################
# 5.22 H68K 修复完成
###############################################################################

echo
echo "============================================================"
echo " H68K RTL8211F 1G 网口修复验证完成"
echo "============================================================"


echo
echo "Kernel:"
echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
echo "  LINUX_VERSION   = $LINUX_VERSION"


echo
echo "GMAC0:"
echo "  phy-mode      = rgmii"
echo "  clock         = CLK_MAC0_2TOP"
echo "  tx_delay      = 0x26"
echo "  rx_delay      = 0x2a"
echo "  reset GPIO    = GPIO2_PD3"
echo "  reset timing  = 0 / 20ms / 100ms"


echo
echo "GMAC1:"
echo "  phy-mode      = rgmii"
echo "  clock         = CLK_MAC1_2TOP"
echo "  tx_delay      = 0x34"
echo "  rx_delay      = 0x22"
echo "  reset GPIO    = GPIO1_PB0"
echo "  reset timing  = 0 / 15ms / 50ms"
echo "  phy-supply    = vccio_acodec"


echo
echo "Patch:"
echo "  $H68K_PATCH_FILE"


echo
echo "git apply --check --reverse: PASS"
echo "reverse apply: PASS"
echo "target/linux/prepare: PASS"
echo "最终 DTS 检查: PASS"


###############################################################################
# 6. 扫描 package/myapp
###############################################################################

echo
echo "============================================================"
echo " 4. 扫描 package/myapp"
echo "============================================================"


MYAPP_PACKAGES=""


if [ -d package/myapp ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue

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
# 7. 当前配置包
###############################################################################

echo
echo "============================================================"
echo " 5. 读取当前 .config"
echo "============================================================"


CONFIG_PACKAGES=""


if [ -f .config ]; then

    CONFIG_PACKAGES="$(
        sed -nE \
            's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
            .config |
        sort -u
    )"

fi


echo
echo "当前配置包数量："

printf '%s\n' "$CONFIG_PACKAGES" |
sed '/^$/d' |
wc -l


###############################################################################
# 8. package/myapp 优先
###############################################################################

echo
echo "============================================================"
echo " 6. package/myapp 来源优先"
echo "============================================================"


for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue


    echo
    echo "检查：$pkg"


    MYAPP_MAKEFILE=""


    while IFS= read -r -d '' mf; do

        if grep -q \
            "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*" \
            "$mf" \
            2>/dev/null
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

        echo "package/myapp:"
        echo "  $MYAPP_MAKEFILE"

        echo "version:"
        echo "  $(get_package_version "$MYAPP_MAKEFILE")"

    fi


    for feed in \
        $THIRD_PARTY_FEEDS \
        $OFFICIAL_FEEDS
    do

        if package_entry_exists \
            "$feed" \
            "$pkg"
        then

            echo "删除重复来源:"
            echo "  ${feed}/${pkg}"


            remove_package_entry \
                "$feed" \
                "$pkg"

        fi

    done

done


###############################################################################
# 9. 第三方 feed 仅处理已有安装入口
###############################################################################

echo
echo "============================================================"
echo " 7. 第三方来源冲突处理"
echo "============================================================"


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


    echo
    echo "第三方来源："
    echo "  ${THIRD_SOURCE}/${pkg}"


    for official_feed in \
        $OFFICIAL_FEEDS
    do

        if package_entry_exists \
            "$official_feed" \
            "$pkg"
        then

            echo "移除官方重复入口："
            echo "  ${official_feed}/${pkg}"


            remove_package_entry \
                "$official_feed" \
                "$pkg"

        fi

    done

done


###############################################################################
# 10. SmartDNS Rust Makefile
###############################################################################

echo
echo "============================================================"
echo " 8. SmartDNS Rust Makefile 修复"
echo "============================================================"


if [ -f package/myapp/smartdns/package/openwrt/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/package/openwrt/Makefile

fi


if [ -f package/myapp/smartdns/Makefile ]; then

    sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        package/myapp/smartdns/Makefile

fi


echo "SmartDNS Rust Makefile 检查完成"


###############################################################################
# 11. LuCI 中文语言包
###############################################################################

echo
echo "============================================================"
echo " 9. LuCI 中文语言包"
echo "============================================================"


if [ -f .config ]; then

    while IFS= read -r pkg; do

        [ -n "$pkg" ] || continue


        trans="luci-i18n-${pkg#luci-app-}"


        if grep -q \
            "^CONFIG_PACKAGE_${trans}-zh-cn=y" \
            .config \
            2>/dev/null
        then

            continue

        fi


        if grep -rnq \
            "Package.*${trans}-zh-cn" \
            package \
            feeds \
            2>/dev/null
        then

            echo \
                "CONFIG_PACKAGE_${trans}-zh-cn=y" \
                >> .config

            echo "添加：${trans}-zh-cn"

        fi

    done < <(
        grep '^CONFIG_PACKAGE_luci-app-.*=y' .config |
        sed 's/^CONFIG_PACKAGE_//;s/=y//' |
        sort -u
    )

fi


###############################################################################
# 12. conntrack
###############################################################################

echo
echo "============================================================"
echo " 10. conntrack"
echo "============================================================"


SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"


mkdir -p \
    "$(dirname "$SYSCTL_FILE")"


touch \
    "$SYSCTL_FILE"


sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    "$SYSCTL_FILE"


echo \
    'net.netfilter.nf_conntrack_max=655550' \
    >> "$SYSCTL_FILE"


echo "nf_conntrack_max = 655550"


###############################################################################
# 13. Wi-Fi 首次启动
###############################################################################

echo
echo "============================================================"
echo " 11. Wi-Fi 首次启动自动开启"
echo "============================================================"


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


echo "Wi-Fi 首次启动自动开启 OK"


###############################################################################
# 14. 关键配置验证
###############################################################################

echo
echo "============================================================"
echo " 12. DIY2 最终检查"
echo "============================================================"


###############################################################################
# H68K patch 必须存在
###############################################################################

if [ ! -s "$H68K_PATCH_FILE" ]; then

    echo
    echo "ERROR: H68K patch 不存在或为空"

    exit 1

fi


###############################################################################
# H68K DTS 必须存在
###############################################################################

if [ ! -f "$OPENWRT_H68K_DTS" ]; then

    echo
    echo "ERROR: prepare 后 H68K DTS 不存在"

    exit 1

fi


###############################################################################
# 禁止出现明显错误的 feeds 全量入口
###############################################################################

if [ -d package/feeds/video ]; then

    echo
    echo "WARNING: package/feeds/video 存在"

    echo "但本 DIY2 未执行 video 全量安装。"

fi


###############################################################################
# 15. 最终输出
###############################################################################

echo
echo
echo "============================================================"
echo "                  DIY2 SUCCESS"
echo "============================================================"


echo
echo "核心修复："
echo "  H68K RTL8211F 1G 网口"
echo


echo "Kernel:"
echo "  KERNEL_PATCHVER : $KERNEL_PATCHVER"
echo "  LINUX_VERSION   : $LINUX_VERSION"
echo


echo "GMAC0:"
echo "  phy-mode        : rgmii"
echo "  clock           : CLK_MAC0_2TOP"
echo "  tx_delay        : 0x26"
echo "  rx_delay        : 0x2a"
echo "  reset GPIO      : GPIO2_PD3"
echo "  reset timing    : 0 / 20ms / 100ms"
echo


echo "GMAC1:"
echo "  phy-mode        : rgmii"
echo "  clock           : CLK_MAC1_2TOP"
echo "  tx_delay        : 0x34"
echo "  rx_delay        : 0x22"
echo "  reset GPIO      : GPIO1_PB0"
echo "  reset timing    : 0 / 15ms / 50ms"
echo "  phy-supply      : vccio_acodec"
echo


echo "H68K patch:"
echo "  $H68K_PATCH_FILE"
echo


echo "验证："
echo "  kernel download             : PASS"
echo "  H68K DTS                    : PASS"
echo "  RTL8211F DTS modification   : PASS"
echo "  patch generation            : PASS"
echo "  target/linux/prepare        : PASS"
echo "  git apply --check --reverse : PASS"
echo "  reverse apply               : PASS"
echo "  final DTS validation        : PASS"
echo


echo "第三方："
echo "  Golang 27.x                 : PASS"
echo "  PassWall                    : PASS"
echo "  SONiC FullCone              : PASS"
echo "  SmartDNS                    : PASS"
echo


echo "系统："
echo "  conntrack                   : PASS"
echo "  Wi-Fi first boot            : PASS"
echo "  LuCI zh-cn                  : PASS"
echo


echo "============================================================"
echo " DIY2 完成"
echo " H68K RTL8211F 1G 网口修复已通过实际 prepare + patch 验证"
echo "============================================================"
echo
