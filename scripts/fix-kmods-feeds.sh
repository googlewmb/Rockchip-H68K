#!/bin/bash
#
# ============================================================
# iStoreOS / OpenWrt KMOD APK 仓库自动修正
#
# 适用于：
#   iStoreOS 25.12.x
#
# 主要功能：
#   1. 自动识别当前 iStoreOS 版本
#   2. 自动识别 VERSION_REPO
#   3. 自动展开 %V / %v
#   4. 自动识别 BOARD / SUBTARGET
#   5. 自动从当前 target/linux/<BOARD>/Makefile
#      获取 KERNEL_PATCHVER
#   6. 自动计算完整 LINUX_VERSION
#   7. 自动识别 LINUX_RELEASE
#   8. 自动从远程 kmods 目录匹配正确 vermagic
#   9. 写入 TOPDIR/.vermagic
#  10. 检查 iStoreOS KMOD feed 是否已经引用 .vermagic
#
# ============================================================

set -e

echo "============================================================"
echo " iStoreOS / OpenWrt KMOD APK 仓库自动修正"
echo "============================================================"


# ============================================================
# 查找 OpenWrt / iStoreOS 源码根目录
# ============================================================

find_openwrt_root() {
    local dir="$PWD"

    while [ "$dir" != "/" ]; do
        if [ -f "$dir/Makefile" ] &&
           [ -f "$dir/rules.mk" ] &&
           [ -d "$dir/include" ] &&
           [ -d "$dir/target" ]; then
            printf '%s\n' "$dir"
            return 0
        fi

        dir="$(dirname "$dir")"
    done

    return 1
}


TOPDIR="$(find_openwrt_root || true)"

if [ -z "$TOPDIR" ]; then
    echo "错误：无法找到 OpenWrt / iStoreOS 源码根目录。"
    exit 1
fi

cd "$TOPDIR"

echo "源码根目录："
echo "  $TOPDIR"


# ============================================================
# 检查必要文件
# ============================================================

REQUIRED_FILES="
Makefile
rules.mk
.config
include/version.mk
include/kernel.mk
include/kernel-version.mk
include/kernel-defaults.mk
include/feeds.mk
"

for file in $REQUIRED_FILES; do
    if [ ! -f "$TOPDIR/$file" ]; then
        echo "错误：缺少文件：$TOPDIR/$file"
        exit 1
    fi
done

if [ ! -f "$TOPDIR/include/target.mk" ]; then
    echo "错误：缺少：include/target.mk"
    exit 1
fi


# ============================================================
# 检查配置
# ============================================================

if [ ! -s "$TOPDIR/.config" ]; then
    echo "错误：.config 不存在或为空。"
    exit 1
fi


# ============================================================
# make defconfig
#
# 注意：
# 这里允许 iStoreOS 自身产生 WARNING。
# 真正影响本脚本的是最终 make 是否能够正常返回。
# ============================================================

echo
echo "正在执行 make defconfig..."

if ! make defconfig >/dev/null; then
    echo "错误：make defconfig 失败。"
    exit 1
fi

echo "make defconfig：完成"


# ============================================================
# 获取 VERSION_NUMBER / VERSION_REPO
#
# 优先使用 iStoreOS 自己的 Make 变量。
# ============================================================

TMP_VERSION_MK="$(mktemp)"

cat > "$TMP_VERSION_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/version.mk

print:
	@echo "VERSION_NUMBER=\$(VERSION_NUMBER)"
	@echo "VERSION_REPO=\$(VERSION_REPO)"
EOF

VERSION_OUTPUT="$(make -s -f "$TMP_VERSION_MK" print 2>/dev/null || true)"

rm -f "$TMP_VERSION_MK"


VERSION_NUMBER="$(printf '%s\n' "$VERSION_OUTPUT" |
    sed -n 's/^VERSION_NUMBER=//p' |
    tail -n 1)"

VERSION_REPO="$(printf '%s\n' "$VERSION_OUTPUT" |
    sed -n 's/^VERSION_REPO=//p' |
    tail -n 1)"


# ============================================================
# 如果 Make 方式没有获取到，则从 .config 回退
# ============================================================

if [ -z "$VERSION_NUMBER" ]; then
    VERSION_NUMBER="$(
        sed -n \
            's/^CONFIG_VERSION_NUMBER="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
            "$TOPDIR/.config" |
        tail -n 1
    )"
fi

if [ -z "$VERSION_REPO" ]; then
    VERSION_REPO="$(
        sed -n \
            's/^CONFIG_VERSION_REPO="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
            "$TOPDIR/.config" |
        tail -n 1
    )"
fi


if [ -z "$VERSION_NUMBER" ]; then
    echo "错误：无法获取 VERSION_NUMBER。"
    exit 1
fi

if [ -z "$VERSION_REPO" ]; then
    echo "错误：无法获取 VERSION_REPO。"
    exit 1
fi


echo
echo "VERSION_NUMBER：$VERSION_NUMBER"
echo "VERSION_REPO："
echo "$VERSION_REPO"


# ============================================================
# 展开 iStoreOS / OpenWrt 版本仓库变量
#
# 例如：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/%V
#
# 变成：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/25.12.5
#
# 同时兼容：
#   %V
#   %v
# ============================================================

VERSION_REPO="${VERSION_REPO//%V/$VERSION_NUMBER}"
VERSION_REPO="${VERSION_REPO//%v/$VERSION_NUMBER}"
VERSION_REPO="${VERSION_REPO%/}"


echo
echo "展开后的 VERSION_REPO："
echo "$VERSION_REPO"


# ============================================================
# 判断 iStoreOS 版本
# ============================================================

case "$VERSION_NUMBER" in
    24.10.*)
        echo "检测到 iStoreOS 24.10.x"
        ;;

    25.12.*)
        echo "检测到 iStoreOS 25.12.x"
        ;;

    *)
        echo "错误：暂不支持此 iStoreOS / OpenWrt 版本：$VERSION_NUMBER"
        exit 1
        ;;
esac


# ============================================================
# 获取 BOARD / SUBTARGET
# ============================================================

BOARD="$(
    sed -n \
        's/^CONFIG_TARGET_BOARD="\([^"]*\)"/\1/p' \
        "$TOPDIR/.config" |
    tail -n 1
)"

SUBTARGET="$(
    sed -n \
        's/^CONFIG_TARGET_SUBTARGET="\([^"]*\)"/\1/p' \
        "$TOPDIR/.config" |
    tail -n 1
)"


if [ -z "$BOARD" ]; then
    echo "错误：无法获取 BOARD。"
    exit 1
fi

if [ -z "$SUBTARGET" ]; then
    echo "错误：无法获取 SUBTARGET。"
    exit 1
fi


echo
echo "BOARD：$BOARD"
echo "SUBTARGET：$SUBTARGET"


# ============================================================
# 获取 ARCH_PACKAGES
#
# 使用当前源码的 Make 系统，而不是硬编码架构名称。
# ============================================================

TMP_ARCH_MK="$(mktemp)"

cat > "$TMP_ARCH_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/.config
include \$(TOPDIR)/include/target.mk

BOARD := $BOARD
SUBTARGET := $SUBTARGET

include \$(TOPDIR)/target/linux/\$(BOARD)/Makefile
include \$(TOPDIR)/target/linux/\$(BOARD)/\$(SUBTARGET)/target.mk

print:
	@echo "ARCH_PACKAGES=\$(ARCH_PACKAGES)"
EOF

ARCH_OUTPUT="$(make -s -f "$TMP_ARCH_MK" print 2>/dev/null || true)"

rm -f "$TMP_ARCH_MK"


ARCH_PACKAGES="$(
    printf '%s\n' "$ARCH_OUTPUT" |
    sed -n 's/^ARCH_PACKAGES=//p' |
    tail -n 1
)"


# ============================================================
# ARCH_PACKAGES 回退
# ============================================================

if [ -z "$ARCH_PACKAGES" ]; then
    ARCH_PACKAGES="$(
        sed -n \
            's/^CONFIG_ARCH_PACKAGES="\([^"]*\)"/\1/p' \
            "$TOPDIR/.config" |
        tail -n 1
    )"
fi


if [ -z "$ARCH_PACKAGES" ]; then
    echo "警告：无法获取 ARCH_PACKAGES。"
    echo "将继续执行，因为 KMOD 仓库路径本身不依赖该变量。"
else
    echo "ARCH_PACKAGES：$ARCH_PACKAGES"
fi


# ============================================================
# 获取 KERNEL_PATCHVER
#
# 关键：
# iStoreOS 25.12 的 Rockchip target Makefile 中定义：
#
#   KERNEL_PATCHVER:=6.12
#
# 因此不能单独从 include/kernel-version.mk 猜测完整版本。
# ============================================================

TARGET_MK="$TOPDIR/target/linux/$BOARD/Makefile"

if [ ! -f "$TARGET_MK" ]; then
    echo "错误：找不到目标 Makefile："
    echo "  $TARGET_MK"
    exit 1
fi


KERNEL_PATCHVER="$(
    sed -n \
        's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*[:?+]*=[[:space:]]*\([^[:space:]#]*\).*$/\1/p' \
        "$TARGET_MK" |
    tail -n 1
)"


# ============================================================
# 如果直接解析失败，则使用 Make 系统获取
# ============================================================

if [ -z "$KERNEL_PATCHVER" ]; then

    TMP_KERNEL_MK="$(mktemp)"

    cat > "$TMP_KERNEL_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/.config
include \$(TOPDIR)/include/target.mk

BOARD := $BOARD
SUBTARGET := $SUBTARGET

include \$(TOPDIR)/target/linux/\$(BOARD)/Makefile

print:
	@echo "KERNEL_PATCHVER=\$(KERNEL_PATCHVER)"
EOF

    KERNEL_PATCHVER_OUTPUT="$(
        make -s -f "$TMP_KERNEL_MK" print 2>/dev/null || true
    )"

    rm -f "$TMP_KERNEL_MK"

    KERNEL_PATCHVER="$(
        printf '%s\n' "$KERNEL_PATCHVER_OUTPUT" |
        sed -n 's/^KERNEL_PATCHVER=//p' |
        tail -n 1
    )"
fi


if [ -z "$KERNEL_PATCHVER" ]; then
    echo "错误：无法获取 KERNEL_PATCHVER。"
    echo "目标文件：$TARGET_MK"
    exit 1
fi


echo "KERNEL_PATCHVER：$KERNEL_PATCHVER"


# ============================================================
# 获取完整 LINUX_VERSION
#
# 必须让 Make 系统加载：
#
#   target/linux/<BOARD>/Makefile
#       ↓
#   KERNEL_PATCHVER
#       ↓
#   include/kernel-version.mk
#       ↓
#   LINUX_VERSION-6.12=.94
#       ↓
#   LINUX_VERSION=6.12.94
#
# 不能简单使用 KERNEL_PATCHVER=6.12 作为最终版本。
# ============================================================

TMP_LINUX_MK="$(mktemp)"

cat > "$TMP_LINUX_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/.config
include \$(TOPDIR)/include/target.mk

BOARD := $BOARD
SUBTARGET := $SUBTARGET

include \$(TOPDIR)/target/linux/\$(BOARD)/Makefile
include \$(TOPDIR)/include/kernel-version.mk

print:
	@echo "LINUX_VERSION=\$(LINUX_VERSION)"
	@echo "LINUX_RELEASE=\$(LINUX_RELEASE)"
EOF

LINUX_OUTPUT="$(
    make -s -f "$TMP_LINUX_MK" print 2>/dev/null || true
)"

rm -f "$TMP_LINUX_MK"


LINUX_VERSION="$(
    printf '%s\n' "$LINUX_OUTPUT" |
    sed -n 's/^LINUX_VERSION=//p' |
    tail -n 1
)"

LINUX_RELEASE="$(
    printf '%s\n' "$LINUX_OUTPUT" |
    sed -n 's/^LINUX_RELEASE=//p' |
    tail -n 1
)"


# ============================================================
# LINUX_VERSION 回退
# ============================================================

if [ -z "$LINUX_VERSION" ]; then

    KERNEL_VERSION_SUFFIX="$(
        sed -n \
            "s/^[[:space:]]*LINUX_VERSION-${KERNEL_PATCHVER}[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*$/\1/p" \
            "$TOPDIR/target/linux/generic/kernel-$KERNEL_PATCHVER" |
        tail -n 1
    )"

    if [ -n "$KERNEL_VERSION_SUFFIX" ]; then
        LINUX_VERSION="${KERNEL_PATCHVER}${KERNEL_VERSION_SUFFIX}"
    fi
fi


# ============================================================
# LINUX_RELEASE 回退
# ============================================================

if [ -z "$LINUX_RELEASE" ]; then

    LINUX_RELEASE="$(
        sed -n \
            's/^[[:space:]]*LINUX_RELEASE[[:space:]]*[:?+]*=[[:space:]]*\([^[:space:]#]*\).*$/\1/p' \
            "$TOPDIR/include/kernel-version.mk" |
        tail -n 1
    )
fi


# iStoreOS/OpenWrt 默认 kernel release 通常为 1
if [ -z "$LINUX_RELEASE" ]; then
    LINUX_RELEASE="1"
fi


if [ -z "$LINUX_VERSION" ]; then
    echo
    echo "错误：无法获取 LINUX_VERSION。"
    echo
    echo "当前信息："
    echo "  BOARD          = $BOARD"
    echo "  SUBTARGET      = $SUBTARGET"
    echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
    exit 1
fi


echo "LINUX_VERSION：$LINUX_VERSION"
echo "LINUX_RELEASE：$LINUX_RELEASE"


# ============================================================
# 构造 KMOD 根目录
#
# 例如：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/25.12.5
#   /targets/rockchip/armv8/kmods
# ============================================================

KMOD_ROOT="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"


echo
echo "KMOD 根目录："
echo "$KMOD_ROOT"


# ============================================================
# 下载远程 KMOD index
# ============================================================

TMP_KMOD_INDEX="$(mktemp)"

cleanup() {
    rm -f "$TMP_KMOD_INDEX"
}

trap cleanup EXIT


echo
echo "正在获取 KMOD 仓库目录..."


if ! curl -fL --retry 3 --connect-timeout 15 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"; then

    echo
    echo "错误：无法获取 KMOD 仓库目录："
    echo "$KMOD_ROOT/"
    exit 1
fi


# ============================================================
# 匹配：
#
# 6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9/
#
# 前缀：
#
# 6.12.94-1-
# ============================================================

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"


echo
echo "KMOD 匹配前缀："
echo "$PREFIX"


MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -E "^${PREFIX}[^/]+$" |
    sort -u || true
)"


if [ -z "$MATCHES" ]; then
    echo
    echo "错误：没有找到匹配的 KMOD 仓库。"
    echo
    echo "搜索位置："
    echo "$KMOD_ROOT/"
    echo
    echo "搜索前缀："
    echo "$PREFIX"
    echo
    echo "远程目录内容："
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" |
        sed -E 's/^href="([^"]+)\/"$/\1/' |
        head -n 50 || true
    exit 1
fi


MATCH_COUNT="$(
    printf '%s\n' "$MATCHES" |
    sed '/^[[:space:]]*$/d' |
    wc -l
)"


if [ "$MATCH_COUNT" -ne 1 ]; then
    echo
    echo "错误：找到多个匹配的 KMOD 仓库。"
    echo
    echo "$MATCHES"
    exit 1
fi


KMOD_DIR="$(
    printf '%s\n' "$MATCHES" |
    head -n 1
)"


# ============================================================
# 从：
#
# 6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9
#
# 提取：
#
# 5fab3a97d147fbf8146094eeebd78fd9
# ============================================================

VERMAGIC="${KMOD_DIR#${PREFIX}}"


if [ -z "$VERMAGIC" ] ||
   [ "$VERMAGIC" = "$KMOD_DIR" ]; then

    echo
    echo "错误：无法从 KMOD 目录中提取 VERMAGIC。"
    echo "KMOD_DIR：$KMOD_DIR"
    echo "PREFIX：$PREFIX"
    exit 1
fi


echo
echo "匹配到 KMOD："
echo "  $KMOD_DIR"

echo
echo "VERMAGIC："
echo "  $VERMAGIC"


# ============================================================
# 最终 KMOD 仓库
# ============================================================

KMOD_REPO="${KMOD_ROOT}/${KMOD_DIR}"


echo
echo "最终 KMOD 仓库："
echo "$KMOD_REPO"


# ============================================================
# 验证 packages.adb
# ============================================================

KMOD_PACKAGES_ADB="${KMOD_REPO}/packages.adb"


echo
echo "正在验证 packages.adb..."


if ! curl -fIL --retry 3 --connect-timeout 15 \
    "$KMOD_PACKAGES_ADB" >/dev/null 2>&1; then

    echo
    echo "错误：KMOD 仓库存在，但 packages.adb 无法访问："
    echo "$KMOD_PACKAGES_ADB"
    exit 1
fi


echo "packages.adb：正常"


# ============================================================
# 写入 .vermagic
#
# iStoreOS 后续 feeds.mk 会使用：
#
# $(TOPDIR)/.vermagic
#
# ============================================================

VERMAGIC_FILE="$TOPDIR/.vermagic"

printf '%s\n' "$VERMAGIC" > "$VERMAGIC_FILE"


if [ ! -s "$VERMAGIC_FILE" ]; then
    echo "错误：写入 .vermagic 失败。"
    exit 1
fi


# ============================================================
# 验证 .vermagic
# ============================================================

WRITTEN_VERMAGIC="$(cat "$VERMAGIC_FILE")"


if [ "$WRITTEN_VERMAGIC" != "$VERMAGIC" ]; then
    echo "错误：.vermagic 内容校验失败。"
    exit 1
fi


# ============================================================
# 检查 kernel-defaults.mk
# ============================================================

if grep -q '\$(TOPDIR)/\.vermagic' \
    "$TOPDIR/include/kernel-defaults.mk"; then

    echo
    echo "kernel-defaults.mk：已引用 .vermagic"
else
    echo
    echo "警告：kernel-defaults.mk 未检测到 .vermagic 引用。"
fi


# ============================================================
# 检查 feeds.mk
# ============================================================

if grep -q 'kmods/\$(LINUX_VERSION)-\$(LINUX_RELEASE)-\$(LINUX_VERMAGIC)' \
    "$TOPDIR/include/feeds.mk"; then

    echo "feeds.mk：已使用动态 KMOD 路径"
else
    echo "警告：feeds.mk 未检测到动态 KMOD 路径。"
fi


# ============================================================
# 最终结果
# ============================================================

echo
echo "============================================================"
echo " KMOD 自动修正完成"
echo "============================================================"

echo
echo "iStoreOS 版本："
echo "  $VERSION_NUMBER"

echo
echo "KMOD 仓库："
echo "  $KMOD_REPO"

echo
echo "Kernel："
echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
echo "  LINUX_VERSION   = $LINUX_VERSION"
echo "  LINUX_RELEASE   = $LINUX_RELEASE"

echo
echo "VERMAGIC："
echo "  $VERMAGIC"

echo
echo ".vermagic："
echo "  $VERMAGIC_FILE"

echo
echo "packages.adb："
echo "  $KMOD_PACKAGES_ADB"

echo
echo "============================================================"
echo " 完成"
echo "============================================================"
