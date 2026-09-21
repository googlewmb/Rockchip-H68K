#!/bin/bash
#
# ============================================================
# iStoreOS / OpenWrt KMOD APK 仓库自动修正
#
# 适用于 iStoreOS 24.10.x / 25.12.x
#
# 功能：
#   1. 自动识别源码根目录
#   2. 自动读取 VERSION_NUMBER
#   3. 自动读取 VERSION_REPO
#   4. 不写死任何镜像站
#   5. 自动解析 VERSION_REPO 中的版本占位符
#   6. 自动识别 BOARD
#   7. 自动识别 SUBTARGET
#   8. 自动识别 ARCH_PACKAGES
#   9. 自动识别 KERNEL_PATCHVER
#  10. 自动获取完整 LINUX_VERSION
#  11. 自动获取 LINUX_RELEASE
#  12. 自动匹配 KMOD VERMAGIC
#  13. 自动验证 packages.adb
#  14. 写入 TOPDIR/.vermagic
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
include/target.mk
"

for file in $REQUIRED_FILES; do
    if [ ! -f "$TOPDIR/$file" ]; then
        echo "错误：缺少文件：$TOPDIR/$file"
        exit 1
    fi
done


# ============================================================
# 检查 .config
# ============================================================

if [ ! -s "$TOPDIR/.config" ]; then
    echo "错误：.config 不存在或为空。"
    exit 1
fi


# ============================================================
# make defconfig
# ============================================================

echo
echo "正在执行 make defconfig..."

if ! make defconfig >/dev/null; then
    echo "错误：make defconfig 失败。"
    exit 1
fi

echo "make defconfig：完成"


# ============================================================
# 自动读取 VERSION_NUMBER / VERSION_REPO
#
# 注意：
# 不在脚本中写死任何镜像站。
#
# VERSION_REPO 由当前 iStoreOS 源码自己的 Make 变量提供。
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

VERSION_OUTPUT="$(
    make -s -f "$TMP_VERSION_MK" print 2>/dev/null || true
)"

rm -f "$TMP_VERSION_MK"


VERSION_NUMBER="$(
    printf '%s\n' "$VERSION_OUTPUT" |
    sed -n 's/^VERSION_NUMBER=//p' |
    tail -n 1
)"

VERSION_REPO="$(
    printf '%s\n' "$VERSION_OUTPUT" |
    sed -n 's/^VERSION_REPO=//p' |
    tail -n 1
)"


# ============================================================
# 回退：从 .config 获取版本
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
echo
echo "VERSION_REPO："
echo "  $VERSION_REPO"


# ============================================================
# 解析 VERSION_REPO
#
# 不指定镜像站。
#
# 例如源码返回：
#
#   https://mirrors.cernet.edu.cn/openwrt/releases/%V
#
# 这里只负责解析源码中的版本占位符。
#
# 支持：
#   %V
#   %v
#
# 同时兼容已经展开版本号的 URL。
# ============================================================

RESOLVED_VERSION_REPO="$VERSION_REPO"

case "$RESOLVED_VERSION_REPO" in
    *%V*)
        RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO//%V/$VERSION_NUMBER}"
        ;;

    *%v*)
        RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO//%v/$VERSION_NUMBER}"
        ;;
esac

RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO%/}"


echo
echo "解析后的 VERSION_REPO："
echo "  $RESOLVED_VERSION_REPO"


# ============================================================
# 检查版本
# ============================================================

case "$VERSION_NUMBER" in
    24.10.*)
        echo
        echo "检测到 iStoreOS 24.10.x"
        ;;

    25.12.*)
        echo
        echo "检测到 iStoreOS 25.12.x"
        ;;

    *)
        echo
        echo "错误：暂不支持此版本：$VERSION_NUMBER"
        exit 1
        ;;
esac


# ============================================================
# 自动识别 BOARD
# ============================================================

BOARD="$(
    sed -n \
        's/^CONFIG_TARGET_BOARD="\([^"]*\)"/\1/p' \
        "$TOPDIR/.config" |
    tail -n 1
)"


# ============================================================
# 自动识别 SUBTARGET
# ============================================================

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
# 自动识别 ARCH_PACKAGES
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

ARCH_OUTPUT="$(
    make -s -f "$TMP_ARCH_MK" print 2>/dev/null || true
)"

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


if [ -n "$ARCH_PACKAGES" ]; then
    echo "ARCH_PACKAGES：$ARCH_PACKAGES"
else
    echo "ARCH_PACKAGES：未获取"
fi


# ============================================================
# 自动识别 KERNEL_PATCHVER
#
# 首先从当前 BOARD 的 target Makefile 获取。
#
# 例如：
#
# target/linux/rockchip/Makefile
#
# KERNEL_PATCHVER:=6.12
# ============================================================

TARGET_MK="$TOPDIR/target/linux/$BOARD/Makefile"

if [ ! -f "$TARGET_MK" ]; then
    echo
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
# KERNEL_PATCHVER 回退：使用 Make 系统
# ============================================================

if [ -z "$KERNEL_PATCHVER" ]; then

    TMP_KERNEL_PATCH_MK="$(mktemp)"

    cat > "$TMP_KERNEL_PATCH_MK" <<EOF
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

    KERNEL_PATCH_OUTPUT="$(
        make -s -f "$TMP_KERNEL_PATCH_MK" print 2>/dev/null || true
    )"

    rm -f "$TMP_KERNEL_PATCH_MK"

    KERNEL_PATCHVER="$(
        printf '%s\n' "$KERNEL_PATCH_OUTPUT" |
        sed -n 's/^KERNEL_PATCHVER=//p' |
        tail -n 1
    )"
fi


if [ -z "$KERNEL_PATCHVER" ]; then
    echo
    echo "错误：无法获取 KERNEL_PATCHVER。"
    echo "目标文件：$TARGET_MK"
    exit 1
fi


echo "KERNEL_PATCHVER：$KERNEL_PATCHVER"


# ============================================================
# 自动获取完整 LINUX_VERSION
#
# 关键链：
#
# KERNEL_PATCHVER=6.12
#        ↓
# target/linux/generic/kernel-6.12
#        ↓
# LINUX_VERSION-6.12=.94
#        ↓
# LINUX_VERSION=6.12.94
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
#
# 如果 Make 无法直接得到完整版本，
# 再从对应 generic kernel 文件读取版本后缀。
# ============================================================

if [ -z "$LINUX_VERSION" ]; then

    GENERIC_KERNEL_FILE="$TOPDIR/target/linux/generic/kernel-$KERNEL_PATCHVER"

    if [ -f "$GENERIC_KERNEL_FILE" ]; then

        KERNEL_VERSION_SUFFIX="$(
            sed -n \
                "s/^[[:space:]]*LINUX_VERSION-${KERNEL_PATCHVER}[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*$/\1/p" \
                "$GENERIC_KERNEL_FILE" |
            tail -n 1
        )"

        if [ -n "$KERNEL_VERSION_SUFFIX" ]; then
            LINUX_VERSION="${KERNEL_PATCHVER}${KERNEL_VERSION_SUFFIX}"
        fi
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


# ============================================================
# 最终默认值
# ============================================================

if [ -z "$LINUX_RELEASE" ]; then
    LINUX_RELEASE="1"
fi


if [ -z "$LINUX_VERSION" ]; then

    echo
    echo "错误：无法获取 LINUX_VERSION。"
    echo
    echo "当前信息："
    echo "  BOARD           = $BOARD"
    echo "  SUBTARGET       = $SUBTARGET"
    echo "  KERNEL_PATCHVER = $KERNEL_PATCHVER"
    exit 1
fi


echo "LINUX_VERSION：$LINUX_VERSION"
echo "LINUX_RELEASE：$LINUX_RELEASE"


# ============================================================
# 构造 KMOD 根目录
#
# 完全使用自动识别出来的 VERSION_REPO。
#
# 不写死：
#   mirrors.cernet.edu.cn
#   downloads.openwrt.org
# ============================================================

KMOD_ROOT="${RESOLVED_VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"


echo
echo "KMOD 根目录："
echo "  $KMOD_ROOT"


# ============================================================
# 创建临时文件
# ============================================================

TMP_KMOD_INDEX="$(mktemp)"

cleanup() {
    rm -f "$TMP_KMOD_INDEX"
}

trap cleanup EXIT


# ============================================================
# 下载 KMOD 目录索引
# ============================================================

echo
echo "正在获取 KMOD 仓库目录..."


if ! curl -fL \
    --retry 3 \
    --connect-timeout 15 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"; then

    echo
    echo "错误：无法获取 KMOD 仓库目录："
    echo "  $KMOD_ROOT/"
    exit 1
fi


# ============================================================
# 构造匹配前缀
#
# 例如：
#
# LINUX_VERSION = 6.12.94
# LINUX_RELEASE = 1
#
# PREFIX =
#
# 6.12.94-1-
# ============================================================

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"


echo
echo "KMOD 匹配前缀："
echo "  $PREFIX"


# ============================================================
# 自动搜索 KMOD VERMAGIC
#
# 例如：
#
# 6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9
# ============================================================

MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -E "^${PREFIX}[^/]+$" |
    sort -u || true
)"


# ============================================================
# 没有匹配
# ============================================================

if [ -z "$MATCHES" ]; then

    echo
    echo "错误：没有找到匹配的 KMOD 仓库。"
    echo
    echo "搜索位置："
    echo "  $KMOD_ROOT/"
    echo
    echo "搜索前缀："
    echo "  $PREFIX"
    echo
    echo "远程 KMOD 目录前 50 项："

    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
        sed -E 's/^href="([^"]+)\/"$/\1/' |
        head -n 50 || true

    exit 1
fi


# ============================================================
# 必须只有一个匹配
# ============================================================

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


# ============================================================
# 获取 KMOD 目录
# ============================================================

KMOD_DIR="$(
    printf '%s\n' "$MATCHES" |
    head -n 1
)"


# ============================================================
# 提取 VERMAGIC
#
# 例如：
#
# KMOD_DIR：
# 6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9
#
# PREFIX：
# 6.12.94-1-
#
# VERMAGIC：
# 5fab3a97d147fbf8146094eeebd78fd9
# ============================================================

VERMAGIC="${KMOD_DIR#${PREFIX}}"


if [ -z "$VERMAGIC" ] ||
   [ "$VERMAGIC" = "$KMOD_DIR" ]; then

    echo
    echo "错误：无法从 KMOD 目录提取 VERMAGIC。"
    echo
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
echo "  $KMOD_REPO"


# ============================================================
# 验证 packages.adb
# ============================================================

KMOD_PACKAGES_ADB="${KMOD_REPO}/packages.adb"


echo
echo "正在验证 packages.adb..."


if ! curl -fIL \
    --retry 3 \
    --connect-timeout 15 \
    "$KMOD_PACKAGES_ADB" >/dev/null 2>&1; then

    echo
    echo "错误：KMOD 仓库存在，但 packages.adb 无法访问："
    echo "  $KMOD_PACKAGES_ADB"

    exit 1
fi


echo "packages.adb：正常"


# ============================================================
# 写入 .vermagic
# ============================================================

VERMAGIC_FILE="$TOPDIR/.vermagic"

printf '%s\n' "$VERMAGIC" > "$VERMAGIC_FILE"


if [ ! -s "$VERMAGIC_FILE" ]; then
    echo
    echo "错误：写入 .vermagic 失败。"
    exit 1
fi


# ============================================================
# 校验 .vermagic
# ============================================================

WRITTEN_VERMAGIC="$(cat "$VERMAGIC_FILE")"


if [ "$WRITTEN_VERMAGIC" != "$VERMAGIC" ]; then

    echo
    echo "错误：.vermagic 内容校验失败。"
    exit 1
fi


# ============================================================
# 检查 kernel-defaults.mk
# ============================================================

echo

if grep -q '\$(TOPDIR)/\.vermagic' \
    "$TOPDIR/include/kernel-defaults.mk"; then

    echo "kernel-defaults.mk：已引用 .vermagic"

else

    echo "警告：kernel-defaults.mk 未检测到 .vermagic 引用"

fi


# ============================================================
# 检查 feeds.mk
# ============================================================

if grep -q \
    'kmods/\$(LINUX_VERSION)-\$(LINUX_RELEASE)-\$(LINUX_VERMAGIC)' \
    "$TOPDIR/include/feeds.mk"; then

    echo "feeds.mk：已使用动态 KMOD 路径"

else

    echo "警告：feeds.mk 未检测到动态 KMOD 路径"

fi


# ============================================================
# 最终输出
# ============================================================

echo
echo "============================================================"
echo " KMOD 自动修正完成"
echo "============================================================"

echo
echo "iStoreOS 版本："
echo "  $VERSION_NUMBER"

echo
echo "自动识别的 VERSION_REPO："
echo "  $VERSION_REPO"

echo
echo "解析后的 VERSION_REPO："
echo "  $RESOLVED_VERSION_REPO"

echo
echo "BOARD："
echo "  $BOARD"

echo
echo "SUBTARGET："
echo "  $SUBTARGET"

echo
echo "ARCH_PACKAGES："
echo "  ${ARCH_PACKAGES:-未获取}"

echo
echo "KERNEL_PATCHVER："
echo "  $KERNEL_PATCHVER"

echo
echo "LINUX_VERSION："
echo "  $LINUX_VERSION"

echo
echo "LINUX_RELEASE："
echo "  $LINUX_RELEASE"

echo
echo "KMOD 目录："
echo "  $KMOD_DIR"

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
