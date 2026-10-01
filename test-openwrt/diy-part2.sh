#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#
# 唯一功能：
#   H68K RTL8211F 1G 网口修复
#
# 修复内容：
#   1. 自动识别 Rockchip KERNEL_PATCHVER
#   2. OpenWrt 自己下载实际 Linux kernel
#   3. 自动寻找实际 kernel archive
#   4. 自动获取完整 Linux kernel 版本
#   5. 自动找到 H68K DTS
#   6. 动态修改 GMAC0 / GMAC1
#   7. 修复 RGMII 模式
#   8. 修复 RGMII 时钟方向
#   9. 修复 GMAC clock parent
#  10. 设置 TX/RX delay
#  11. 设置 RTL8211F reset GPIO
#  12. 设置 PHY reset 时序
#  13. 设置 MDIO PHY pinctrl
#  14. 设置 PHY supply
#  15. 自动生成 kernel patch
#  16. git apply --check --reverse 验证
#  17. target/linux/prepare 实际应用验证
#  18. 最终检查 H68K DTS
#
# 注意：
#   本 DIY2 不处理任何 feeds / 软件包 / PassWall /
#   Golang / SONiC / SmartDNS / LuCI / Wi-Fi / conntrack。
#

set -e


###############################################################################
# 0. 基础目录
###############################################################################

[ -n "${TOPDIR:-}" ] || TOPDIR="$(pwd)"

cd "$TOPDIR"


echo
echo "============================================================"
echo " DIY2 - H68K RTL8211F 1G 网口修复"
echo "============================================================"
echo
echo "TOPDIR:"
echo "  $TOPDIR"
echo


###############################################################################
# 1. 基础检查
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
    python3
do

    if ! command -v "$cmd" >/dev/null 2>&1; then

        echo
        echo "ERROR: 缺少必要工具：$cmd"
        echo

        exit 1

    fi

done


if [ ! -f "$TOPDIR/target/linux/rockchip/Makefile" ]; then

    echo
    echo "ERROR: 当前源码不是有效的 Rockchip OpenWrt/iStoreOS 源码"
    echo
    echo "缺少："
    echo "  target/linux/rockchip/Makefile"
    echo

    exit 1

fi


###############################################################################
# 2. 获取 Rockchip KERNEL_PATCHVER
###############################################################################

echo
echo "============================================================"
echo " 1. 获取 Rockchip KERNEL_PATCHVER"
echo "============================================================"


ROCKCHIP_MAKEFILE="$TOPDIR/target/linux/rockchip/Makefile"


KERNEL_PATCHVER="$(
    sed -nE \
        's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*([0-9]+\.[0-9]+).*$/\1/p' \
        "$ROCKCHIP_MAKEFILE" |
    head -n 1
)"


if [ -z "$KERNEL_PATCHVER" ]; then

    echo
    echo "ERROR: 无法读取 KERNEL_PATCHVER"
    echo

    exit 1

fi


echo
echo "KERNEL_PATCHVER:"
echo "  $KERNEL_PATCHVER"


###############################################################################
# 3. OpenWrt 下载实际 kernel
###############################################################################

echo
echo "============================================================"
echo " 2. 下载实际 Linux kernel"
echo "============================================================"


make \
    target/linux/download \
    V=s


###############################################################################
# 4. 搜索实际 kernel archive
###############################################################################

echo
echo "============================================================"
echo " 3. 搜索 Linux kernel archive"
echo "============================================================"


KERNEL_ARCHIVE_LIST="$(
    find "$TOPDIR/dl" \
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

    echo "当前 dl/ 中 Linux 文件："

    find "$TOPDIR/dl" \
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
# 5. 获取完整 kernel 版本
###############################################################################

LINUX_VERSION="$(
    printf '%s\n' "$KERNEL_ARCHIVE_NAME" |
    sed -nE \
        's/^linux-([0-9]+\.[0-9]+\.[0-9]+).*\.tar\.(xz|zst|gz|bz2)$/\1/p'
)"


if [ -z "$LINUX_VERSION" ]; then

    echo
    echo "ERROR: 无法从 kernel archive 获取完整版本"
    echo
    echo "$KERNEL_ARCHIVE_NAME"
    echo

    exit 1

fi


echo
echo "实际 Linux kernel:"
echo "  $LINUX_VERSION"


###############################################################################
# 6. 创建临时 kernel 工作目录
###############################################################################

H68K_WORK_DIR="$(
    mktemp -d
)"


cleanup_h68k()
{
    rm -rf "$H68K_WORK_DIR"
}


trap cleanup_h68k EXIT


###############################################################################
# 7. 解压 kernel
###############################################################################

echo
echo "============================================================"
echo " 4. 解压 Linux kernel"
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
        echo "$KERNEL_ARCHIVE"

        exit 1

        ;;

esac


###############################################################################
# 8. 自动寻找 kernel 根目录
###############################################################################

echo
echo "============================================================"
echo " 5. 寻找 kernel source"
echo "============================================================"


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

    DTS_DIR="$(
        find "$H68K_WORK_DIR" \
            -type d \
            -path '*/arch/arm64/boot/dts/rockchip' \
            -print \
            -quit 2>/dev/null
    )"


    if [ -n "$DTS_DIR" ]; then

        REAL_KERNEL_DIR="$(
            printf '%s\n' "$DTS_DIR" |
            sed 's@/arch/arm64/boot/dts/rockchip$@@'
        )

    fi

fi


if [ -z "$REAL_KERNEL_DIR" ]; then

    echo
    echo "ERROR: 无法找到 kernel source"
    echo

    exit 1

fi


echo
echo "Kernel source:"
echo "  $REAL_KERNEL_DIR"


###############################################################################
# 9. H68K DTS
###############################################################################

H68K_DTS_REL="arch/arm64/boot/dts/rockchip/rk3568-hinlink-h68k.dts"

H68K_DTS="$REAL_KERNEL_DIR/$H68K_DTS_REL"


echo
echo "============================================================"
echo " 6. 寻找 H68K DTS"
echo "============================================================"


if [ ! -f "$H68K_DTS" ]; then

    echo
    echo "ERROR: 当前 kernel 中找不到："
    echo
    echo "  $H68K_DTS_REL"
    echo

    echo "相关 DTS："

    find \
        "$REAL_KERNEL_DIR/arch/arm64/boot/dts/rockchip" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname '*h68k*' \
            -o -iname '*hinlink*' \
        \) \
        -print 2>/dev/null |
    sort ||
        true

    exit 1

fi


echo
echo "H68K DTS:"
echo "  $H68K_DTS"


###############################################################################
# 10. DTS 基础结构检查
###############################################################################

echo
echo "============================================================"
echo " 7. 检查 H68K DTS 基础节点"
echo "============================================================"


for node in \
    '&gmac0 {' \
    '&gmac1 {' \
    '&mdio0 {' \
    '&mdio1 {'
do

    if ! grep -qF "$node" "$H68K_DTS"; then

        echo
        echo "ERROR: DTS 缺少："
        echo "  $node"

        exit 1

    fi

done


if ! grep -qF 'rgmii_phy0:' "$H68K_DTS"; then

    echo
    echo "ERROR: DTS 缺少 rgmii_phy0"

    exit 1

fi


if ! grep -qF 'rgmii_phy1:' "$H68K_DTS"; then

    echo
    echo "ERROR: DTS 缺少 rgmii_phy1"

    exit 1

fi


echo "GMAC0       : PASS"
echo "GMAC1       : PASS"
echo "MDIO0       : PASS"
echo "MDIO1       : PASS"
echo "rgmii_phy0  : PASS"
echo "rgmii_phy1  : PASS"


###############################################################################
# 11. 建立 baseline
###############################################################################

cd "$REAL_KERNEL_DIR"


git init -q


git config \
    user.name \
    "DIY2-H68K"


git config \
    user.email \
    "diy2-h68k@localhost"


git add \
    "$H68K_DTS_REL"


git commit \
    -q \
    -m "H68K RTL8211F baseline"


###############################################################################
# 12. 动态修改 H68K DTS
###############################################################################

echo
echo "============================================================"
echo " 8. 修复 H68K RTL8211F"
echo "============================================================"


python3 - "$H68K_DTS" <<'PY'
import re
import sys
from pathlib import Path


path = Path(sys.argv[1])

text = path.read_text()


###############################################################################
# 找到完整 DTS 节点
###############################################################################

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


###############################################################################
# 属性替换 / 添加
###############################################################################

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

    brace = block.find("{")

    if brace < 0:
        raise SystemExit(
            f"ERROR: 节点没有 {{ : {name}"
        )

    pos = brace + 1

    return (
        block[:pos] +
        "\n" +
        replacement +
        block[pos:]
    )


###############################################################################
# GMAC0
###############################################################################

a, b, gmac0 = find_node(
    text,
    "&gmac0 {"
)


# RGMII
gmac0 = replace_or_insert_property(
    gmac0,
    "phy-mode",
    '"rgmii"'
)


# 时钟方向
gmac0 = replace_or_insert_property(
    gmac0,
    "clock_in_out",
    '"output"'
)


# RTL8211F reset
if "snps,reset-gpio" not in gmac0:

    gmac0 = gmac0.replace(
        "&gmac0 {",
        """&gmac0 {
\tsnps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;
\tsnps,reset-active-low;
\tsnps,reset-delays-us = <0 20000 100000>;""",
        1
    )


# 删除旧 delay
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


# 删除旧 clock parent
gmac0 = re.sub(
    r'^[ \t]*assigned-clock-parents\s*=.*?;\s*$',
    '',
    gmac0,
    flags=re.M
)


# GMAC0 clock
gmac0 = replace_or_insert_property(
    gmac0,
    "assigned-clock-parents",
    '<&cru SCLK_GMAC0_RGMII_SPEED>,\n\t\t\t\t<&cru CLK_MAC0_2TOP>'
)


# RGMII delay
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


# 状态
gmac0 = replace_or_insert_property(
    gmac0,
    "status",
    '"okay"'
)


# level3 / level2 clocks
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


text = text[:a] + gmac0 + text[b:]


###############################################################################
# GMAC1
###############################################################################

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

gmac1 = re.sub(
    r'^[ \t]*assigned-clock-parents\s*=.*?;\s*$',
    '',
    gmac1,
    flags=re.M
)


gmac1 = replace_or_insert_property(
    gmac1,
    "assigned-clock-parents",
    '<&cru SCLK_GMAC1_RGMII_SPEED>,\n\t\t\t\t<&cru CLK_MAC1_2TOP>'
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


###############################################################################
# MDIO0
###############################################################################

a, b, mdio0 = find_node(
    text,
    "&mdio0 {"
)


if "rgmii_phy0:" not in mdio0:

    raise SystemExit(
        "ERROR: MDIO0 不存在 rgmii_phy0"
    )


# 删除旧 reset 属性
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


# PHY0 pinctrl
if "pinctrl-0 = <&eth_phy0_reset_pin>;" not in mdio0:

    phy_pos = mdio0.find("rgmii_phy0:")

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


###############################################################################
# MDIO1
###############################################################################

a, b, mdio1 = find_node(
    text,
    "&mdio1 {"
)


if "rgmii_phy1:" not in mdio1:

    raise SystemExit(
        "ERROR: MDIO1 不存在 rgmii_phy1"
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


###############################################################################
# pinctrl
###############################################################################

def add_pinctrl_block(text):

    additions = ""


    if "eth_phy0_reset_pin:" not in text:

        additions += """
\tgmac0 {
\t\teth_phy0_reset_pin: eth-phy0-reset-pin {
\t\t\trockchip,pins = <2 RK_PD3 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};
"""


    if "eth_phy1_reset_pin:" not in text:

        additions += """
\tgmac1 {
\t\teth_phy1_reset_pin: eth-phy1-reset-pin {
\t\t\trockchip,pins = <1 RK_PB0 RK_FUNC_GPIO &pcfg_pull_up>;
\t\t};
\t};
"""


    if not additions:

        return text


    if "&pinctrl {" in text:

        a, b, pinctrl = find_node(
            text,
            "&pinctrl {"
        )


        close = pinctrl.rfind("}")


        pinctrl = (
            pinctrl[:close] +
            additions +
            pinctrl[close:]
        )


        return text[:a] + pinctrl + text[b:]


    return text + """

&pinctrl {
""" + additions + """
};
"""


text = add_pinctrl_block(text)


###############################################################################
# 最终检查
###############################################################################

required = [

    'phy-mode = "rgmii";',

    'clock_in_out = "output";',

    'CLK_MAC0_2TOP',
    'CLK_MAC1_2TOP',

    'tx_delay = <0x26>;',
    'rx_delay = <0x2a>;',

    'tx_delay = <0x34>;',
    'rx_delay = <0x22>;',

    'snps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;',
    'snps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;',

    'snps,reset-delays-us = <0 20000 100000>;',
    'snps,reset-delays-us = <0 15000 50000>;',

    'pinctrl-0 = <&eth_phy0_reset_pin>;',
    'pinctrl-0 = <&eth_phy1_reset_pin>;',

    'eth_phy0_reset_pin:',
    'eth_phy1_reset_pin:',

    'phy-supply = <&vccio_acodec>;',

]


for item in required:

    if item not in text:

        raise SystemExit(
            f"ERROR: RTL8211F 修复后缺少：{item}"
        )


if 'phy-mode = "rgmii-id";' in text:

    raise SystemExit(
        'ERROR: 修复后仍然存在 phy-mode = "rgmii-id";'
    )


path.write_text(text)

PY


###############################################################################
# 13. 检查 DTS 修改结果
###############################################################################

echo
echo "============================================================"
echo " 9. RTL8211F DTS 修改检查"
echo "============================================================"


check()
{
    pattern="$1"
    name="$2"


    if ! grep -Fq "$pattern" "$H68K_DTS"; then

        echo
        echo "ERROR: $name"
        echo "缺少：$pattern"

        exit 1

    fi


    echo "PASS: $name"
}


check \
    'phy-mode = "rgmii";' \
    "RGMII"


check \
    'clock_in_out = "output";' \
    "RGMII clock output"


check \
    'CLK_MAC0_2TOP' \
    "GMAC0 clock parent"


check \
    'CLK_MAC1_2TOP' \
    "GMAC1 clock parent"


check \
    'tx_delay = <0x26>;' \
    "GMAC0 TX delay"


check \
    'rx_delay = <0x2a>;' \
    "GMAC0 RX delay"


check \
    'tx_delay = <0x34>;' \
    "GMAC1 TX delay"


check \
    'rx_delay = <0x22>;' \
    "GMAC1 RX delay"


check \
    'snps,reset-gpio = <&gpio2 RK_PD3 GPIO_ACTIVE_LOW>;' \
    "GMAC0 reset GPIO"


check \
    'snps,reset-gpio = <&gpio1 RK_PB0 GPIO_ACTIVE_LOW>;' \
    "GMAC1 reset GPIO"


check \
    'snps,reset-delays-us = <0 20000 100000>;' \
    "GMAC0 reset timing"


check \
    'snps,reset-delays-us = <0 15000 50000>;' \
    "GMAC1 reset timing"


check \
    'pinctrl-0 = <&eth_phy0_reset_pin>;' \
    "PHY0 reset pinctrl"


check \
    'pinctrl-0 = <&eth_phy1_reset_pin>;' \
    "PHY1 reset pinctrl"


check \
    'eth_phy0_reset_pin:' \
    "PHY0 reset pin"


check \
    'eth_phy1_reset_pin:' \
    "PHY1 reset pin"


check \
    'phy-supply = <&vccio_acodec>;' \
    "PHY supply"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$H68K_DTS"
then

    echo
    echo "ERROR: rgmii-id 仍然存在"

    exit 1

fi


###############################################################################
# 14. 生成 patch
###############################################################################

echo
echo "============================================================"
echo " 10. 生成 H68K RTL8211F patch"
echo "============================================================"


git add \
    "$H68K_DTS_REL"


H68K_PATCH_TEMP="$H68K_WORK_DIR/999-h68k-rtl8211f-rgmii-fix.patch"


git diff \
    --cached \
    --no-ext-diff \
    --binary \
    -- "$H68K_DTS_REL" \
    > "$H68K_PATCH_TEMP"


if [ ! -s "$H68K_PATCH_TEMP" ]; then

    echo
    echo "ERROR: H68K patch 为空"

    exit 1

fi


###############################################################################
# 15. 安装 patch
###############################################################################

cd "$TOPDIR"


H68K_PATCH_DIR="$TOPDIR/target/linux/rockchip/patches-${KERNEL_PATCHVER}"

H68K_PATCH_FILE="$H68K_PATCH_DIR/999-h68k-rtl8211f-rgmii-fix.patch"


mkdir -p \
    "$H68K_PATCH_DIR"


rm -f \
    "$H68K_PATCH_FILE"


cp \
    "$H68K_PATCH_TEMP" \
    "$H68K_PATCH_FILE"


echo
echo "H68K patch:"
echo "  $H68K_PATCH_FILE"


###############################################################################
# 16. patch 内容检查
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
echo "Patch 内容检查 PASS"


###############################################################################
# 17. Kernel clean
###############################################################################

echo
echo "============================================================"
echo " 11. target/linux/clean"
echo "============================================================"


make \
    target/linux/clean \
    V=s


###############################################################################
# 18. Kernel prepare
###############################################################################

echo
echo "============================================================"
echo " 12. target/linux/prepare"
echo "============================================================"


make \
    target/linux/prepare \
    V=s


###############################################################################
# 19. 找 prepare 后 H68K DTS
###############################################################################

echo
echo "============================================================"
echo " 13. 检查 prepare 后 H68K DTS"
echo "============================================================"


OPENWRT_H68K_DTS="$(
    find "$TOPDIR/build_dir" \
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
echo "Prepared H68K DTS:"
echo "  $OPENWRT_H68K_DTS"


###############################################################################
# 20. prepare 后最终 DTS 检查
###############################################################################

echo
echo "============================================================"
echo " 14. prepare 后 RTL8211F 最终检查"
echo "============================================================"


final_check()
{
    pattern="$1"
    name="$2"


    if ! grep -Fq \
        "$pattern" \
        "$OPENWRT_H68K_DTS"
    then

        echo
        echo "ERROR: prepare 后缺少："
        echo "  $name"
        echo "  $pattern"

        exit 1

    fi


    echo "PASS: $name"
}


final_check \
    'phy-mode = "rgmii";' \
    "RGMII"


final_check \
    'clock_in_out = "output";' \
    "RGMII clock output"


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
    'pinctrl-0 = <&eth_phy0_reset_pin>;' \
    "PHY0 pinctrl"


final_check \
    'pinctrl-0 = <&eth_phy1_reset_pin>;' \
    "PHY1 pinctrl"


final_check \
    'eth_phy0_reset_pin:' \
    "PHY0 reset pin"


final_check \
    'eth_phy1_reset_pin:' \
    "PHY1 reset pin"


final_check \
    'phy-supply = <&vccio_acodec>;' \
    "PHY supply"


if grep -Fq \
    'phy-mode = "rgmii-id";' \
    "$OPENWRT_H68K_DTS"
then

    echo
    echo "ERROR: prepare 后仍存在 rgmii-id"

    exit 1

fi


###############################################################################
# 21. git apply --check --reverse
###############################################################################

echo
echo "============================================================"
echo " 15. git apply --check --reverse"
echo "============================================================"


VERIFY_DIR="$(
    mktemp -d
)"


mkdir -p \
    "$VERIFY_DIR/$(dirname "$H68K_DTS_REL")"


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
    -m "H68K prepared DTS"


if ! git apply \
    --check \
    --reverse \
    "$TOPDIR/$H68K_PATCH_FILE"
then

    echo
    echo "============================================================"
    echo " ERROR: git apply --check --reverse FAILED"
    echo "============================================================"

    rm -rf \
        "$VERIFY_DIR"

    exit 1

fi


echo
echo "git apply --check --reverse: PASS"


###############################################################################
# 22. reverse apply
###############################################################################

echo
echo "============================================================"
echo " 16. reverse apply"
echo "============================================================"


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


###############################################################################
# 23. 最终完成
###############################################################################

cd "$TOPDIR"


echo
echo
echo "============================================================"
echo "              DIY2 H68K RTL8211F 修复完成"
echo "============================================================"
echo
echo "唯一功能："
echo "  H68K RTL8211F 1G 网口修复"
echo
echo "Kernel:"
echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
echo "  LINUX_VERSION   = $LINUX_VERSION"
echo
echo "Patch:"
echo "  $H68K_PATCH_FILE"
echo
echo "验证结果："
echo "  Kernel download             PASS"
echo "  H68K DTS                    PASS"
echo "  RTL8211F modification      PASS"
echo "  Patch generation            PASS"
echo "  target/linux/clean          PASS"
echo "  target/linux/prepare        PASS"
echo "  git apply --check --reverse PASS"
echo "  reverse apply               PASS"
echo "  Final DTS validation        PASS"
echo
echo "============================================================"
echo " DIY2 SUCCESS"
echo "============================================================"
echo
