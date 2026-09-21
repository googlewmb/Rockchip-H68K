#!/bin/bash
#
# ============================================================
# iStoreOS / OpenWrt KMOD 仓库自动修正
#
# 功能：
#   1. 自动识别源码根目录
#   2. 自动识别 VERSION_NUMBER
#   3. 自动识别 VERSION_REPO
#   4. 不写死任何镜像站
#   5. 自动展开 %V / %v
#   6. 自动识别 BOARD
#   7. 自动识别 SUBTARGET
#   8. 自动识别 ARCH_PACKAGES
#   9. 自动识别 KERNEL_PATCHVER
#  10. 自动获取完整 LINUX_VERSION
#  11. 自动获取 LINUX_RELEASE
#  12. 自动匹配 KMOD VERMAGIC
#  13. 自动识别 APK / OPKG
#  14. 自动检测 packages.adb / Packages.gz
#  15. 写入 .vermagic
#
# ============================================================

set -e

echo "============================================================"
echo " iStoreOS / OpenWrt KMOD 仓库自动修正"
echo "============================================================"


# ============================================================
# 查找源码根目录
# ============================================================

find_openwrt_root() {
    local dir="$PWD"

    while [ "$dir" != "/" ]; do
        if [ -f "$dir/Makefile" ] &&
           [ -f "$dir/rules.mk" ] &&
           [ -d "$dir/include" ] &&
           [ -d "$dir/target" ]; then
            echo "$dir"
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

for file in \
    Makefile \
    rules.mk \
    .config \
    include/version.mk \
    include/kernel.mk \
    include/kernel-version.mk \
    include/kernel-defaults.mk \
    include/feeds.mk \
    include/target.mk
do
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
# 获取 VERSION_NUMBER / VERSION_REPO
# ============================================================

TMP_VERSION_MK="$(mktemp)"

cat > "$TMP_VERSION_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/version.mk

print:
	@echo VERSION_NUMBER=\$(VERSION_NUMBER)
	@echo VERSION_REPO=\$(VERSION_REPO)
EOF

VERSION_OUTPUT="$(make -s -f "$TMP_VERSION_MK" print 2>/dev/null || true)"

rm -f "$TMP_VERSION_MK"


VERSION_NUMBER="$(
    printf '%s\n' "$VERSION_OUTPUT" |
    grep '^VERSION_NUMBER=' |
    tail -n 1 |
    cut -d= -f2-
)"

VERSION_REPO="$(
    printf '%s\n' "$VERSION_OUTPUT" |
    grep '^VERSION_REPO=' |
    tail -n 1 |
    cut -d= -f2-
)"


# ============================================================
# VERSION 回退
# ============================================================

if [ -z "$VERSION_NUMBER" ]; then
    VERSION_NUMBER="$(
        sed -n \
            's/^CONFIG_VERSION_NUMBER="\([^"]*\)".*/\1/p' \
            "$TOPDIR/.config" |
        tail -n 1
    )"
fi


if [ -z "$VERSION_REPO" ]; then
    VERSION_REPO="$(
        sed -n \
            's/^CONFIG_VERSION_REPO="\([^"]*\)".*/\1/p' \
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
echo "$VERSION_REPO"


# ============================================================
# 自动解析 VERSION_REPO
# ============================================================

RESOLVED_VERSION_REPO="$VERSION_REPO"

case "$RESOLVED_VERSION_REPO" in
    *%V*)
        RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO//%V/$VERSION_NUMBER}"
        ;;
esac

case "$RESOLVED_VERSION_REPO" in
    *%v*)
        RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO//%v/$VERSION_NUMBER}"
        ;;
esac

RESOLVED_VERSION_REPO="${RESOLVED_VERSION_REPO%/}"


echo
echo "解析后的 VERSION_REPO："
echo "$RESOLVED_VERSION_REPO"


# ============================================================
# 获取 BOARD
# ============================================================

BOARD="$(
    sed -n \
        's/^CONFIG_TARGET_BOARD="\([^"]*\)".*/\1/p' \
        "$TOPDIR/.config" |
    tail -n 1
)"


# ============================================================
# 获取 SUBTARGET
# ============================================================

SUBTARGET="$(
    sed -n \
        's/^CONFIG_TARGET_SUBTARGET="\([^"]*\)".*/\1/p' \
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
	@echo ARCH_PACKAGES=\$(ARCH_PACKAGES)
EOF

ARCH_OUTPUT="$(make -s -f "$TMP_ARCH_MK" print 2>/dev/null || true)"

rm -f "$TMP_ARCH_MK"


ARCH_PACKAGES="$(
    printf '%s\n' "$ARCH_OUTPUT" |
    grep '^ARCH_PACKAGES=' |
    tail -n 1 |
    cut -d= -f2-
)"


if [ -z "$ARCH_PACKAGES" ]; then
    ARCH_PACKAGES="$(
        sed -n \
            's/^CONFIG_ARCH_PACKAGES="\([^"]*\)".*/\1/p' \
            "$TOPDIR/.config" |
        tail -n 1
    )"
fi


echo
echo "ARCH_PACKAGES：${ARCH_PACKAGES:-未获取}"


# ============================================================
# 获取 KERNEL_PATCHVER
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
        's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*[:?+]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' \
        "$TARGET_MK" |
    tail -n 1
)"


# ============================================================
# KERNEL_PATCHVER 回退
# ============================================================

if [ -z "$KERNEL_PATCHVER" ]; then

    TMP_PATCH_MK="$(mktemp)"

    cat > "$TMP_PATCH_MK" <<EOF
TOPDIR := $TOPDIR

include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/.config
include \$(TOPDIR)/include/target.mk

BOARD := $BOARD
SUBTARGET := $SUBTARGET

include \$(TOPDIR)/target/linux/\$(BOARD)/Makefile

print:
	@echo KERNEL_PATCHVER=\$(KERNEL_PATCHVER)
EOF

    PATCH_OUTPUT="$(make -s -f "$TMP_PATCH_MK" print 2>/dev/null || true)"

    rm -f "$TMP_PATCH_MK"

    KERNEL_PATCHVER="$(
        printf '%s\n' "$PATCH_OUTPUT" |
        grep '^KERNEL_PATCHVER=' |
        tail -n 1 |
        cut -d= -f2-
    )"
fi


if [ -z "$KERNEL_PATCHVER" ]; then
    echo
    echo "错误：无法获取 KERNEL_PATCHVER。"
    exit 1
fi


echo
echo "KERNEL_PATCHVER：$KERNEL_PATCHVER"


# ============================================================
# 获取完整 LINUX_VERSION
# ============================================================

GENERIC_KERNEL_FILE="$TOPDIR/target/linux/generic/kernel-$KERNEL_PATCHVER"

LINUX_VERSION_SUFFIX=""

if [ -f "$GENERIC_KERNEL_FILE" ]; then

    LINUX_VERSION_SUFFIX="$(
        sed -n \
            "s/^[[:space:]]*LINUX_VERSION-${KERNEL_PATCHVER}[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" \
            "$GENERIC_KERNEL_FILE" |
        tail -n 1
    )"

fi


if [ -n "$LINUX_VERSION_SUFFIX" ]; then
    LINUX_VERSION="${KERNEL_PATCHVER}${LINUX_VERSION_SUFFIX}"
else
    LINUX_VERSION=""
fi


# ============================================================
# 如果 generic kernel 文件没有获取到，再让 Make 获取
# ============================================================

if [ -z "$LINUX_VERSION" ]; then

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
	@echo LINUX_VERSION=\$(LINUX_VERSION)
	@echo LINUX_RELEASE=\$(LINUX_RELEASE)
EOF

    LINUX_OUTPUT="$(make -s -f "$TMP_LINUX_MK" print 2>/dev/null || true)"

    rm -f "$TMP_LINUX_MK"

    LINUX_VERSION="$(
        printf '%s\n' "$LINUX_OUTPUT" |
        grep '^LINUX_VERSION=' |
        tail -n 1 |
        cut -d= -f2-
    )"

    LINUX_RELEASE="$(
        printf '%s\n' "$LINUX_OUTPUT" |
        grep '^LINUX_RELEASE=' |
        tail -n 1 |
        cut -d= -f2-
    )"

fi


# ============================================================
# 获取 LINUX_RELEASE
# ============================================================

if [ -z "$LINUX_RELEASE" ]; then

    LINUX_RELEASE="$(
        sed -n \
            's/^[[:space:]]*LINUX_RELEASE[[:space:]]*[:?+]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' \
            "$TOPDIR/include/kernel-version.mk" |
        tail -n 1
    )"

fi


# ============================================================
# 默认 release
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
    echo "  GENERIC FILE    = $GENERIC_KERNEL_FILE"

    exit 1

fi


echo
echo "LINUX_VERSION：$LINUX_VERSION"
echo "LINUX_RELEASE：$LINUX_RELEASE"


# ============================================================
# 构造 KMOD 根目录
# ============================================================

KMOD_ROOT="${RESOLVED_VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"


echo
echo "KMOD 根目录："
echo "  $KMOD_ROOT"


# ============================================================
# 临时文件
# ============================================================

TMP_KMOD_INDEX="$(mktemp)"

cleanup() {
    rm -f "$TMP_KMOD_INDEX"
}

trap cleanup EXIT


# ============================================================
# 获取 KMOD 目录
# ============================================================

echo
echo "正在获取 KMOD 仓库目录..."


if ! curl \
    -fL \
    --retry 3 \
    --connect-timeout 15 \
    --max-time 60 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"
then

    echo
    echo "错误：无法获取 KMOD 仓库目录："
    echo "  $KMOD_ROOT/"
    exit 1

fi


# ============================================================
# 构造匹配前缀
# ============================================================

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"


echo
echo "KMOD 匹配前缀："
echo "  $PREFIX"


# ============================================================
# 搜索 KMOD
# ============================================================

MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -E "^${PREFIX}[^/]+$" |
    sort -u ||
    true
)"


# ============================================================
# 检查匹配结果
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
    echo "远程目录前 50 项："

    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
        sed -E 's/^href="([^"]+)\/"$/\1/' |
        head -n 50 ||
        true

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
    printf '%s\n' "$MATCHES"

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
# ============================================================

VERMAGIC="${KMOD_DIR#"$PREFIX"}"


if [ -z "$VERMAGIC" ] ||
   [ "$VERMAGIC" = "$KMOD_DIR" ]; then

    echo
    echo "错误：无法提取 VERMAGIC。"
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
# 自动识别包管理器
#
# 优先级：
#
#   1. CONFIG_USE_APK=y
#      -> APK
#
#   2. CONFIG_USE_APK 未启用
#      -> OPKG
#
# 不根据 VERSION_NUMBER 判断。
# ============================================================

CONFIG_USE_APK_VALUE="$(
    sed -n \
        's/^CONFIG_USE_APK=\(.*\)$/\1/p' \
        "$TOPDIR/.config" |
    tail -n 1
)"


PACKAGE_MANAGER=""

case "$CONFIG_USE_APK_VALUE" in
    y|Y|1)
        PACKAGE_MANAGER="apk"
        ;;
    *)
        PACKAGE_MANAGER="opkg"
        ;;
esac


echo
echo "自动识别包管理器："
echo "  $PACKAGE_MANAGER"


echo
echo "CONFIG_USE_APK："
echo "  ${CONFIG_USE_APK_VALUE:-未设置}"


# ============================================================
# 自动检测远程 KMOD 索引
#
# APK：
#   packages.adb
#
# OPKG：
#   Packages.gz
#
# 不根据版本号判断。
# ============================================================

KMOD_APK_INDEX="${KMOD_REPO}/packages.adb"
KMOD_OPKG_INDEX="${KMOD_REPO}/Packages.gz"

APK_INDEX_OK=0
OPKG_INDEX_OK=0


# ============================================================
# 检测 packages.adb
# ============================================================

echo
echo "正在检测 APK KMOD 索引："
echo "  $KMOD_APK_INDEX"


if curl \
    -fL \
    --retry 3 \
    --connect-timeout 15 \
    --max-time 60 \
    -o /dev/null \
    "$KMOD_APK_INDEX" \
    >/dev/null 2>&1
then
    APK_INDEX_OK=1
    echo "  packages.adb：存在"
else
    echo "  packages.adb：不存在"
fi


# ============================================================
# 检测 Packages.gz
# ============================================================

echo
echo "正在检测 OPKG KMOD 索引："
echo "  $KMOD_OPKG_INDEX"


if curl \
    -fL \
    --retry 3 \
    --connect-timeout 15 \
    --max-time 60 \
    -o /dev/null \
    "$KMOD_OPKG_INDEX" \
    >/dev/null 2>&1
then
    OPKG_INDEX_OK=1
    echo "  Packages.gz：存在"
else
    echo "  Packages.gz：不存在"
fi


# ============================================================
# 自动确定最终索引
# ============================================================

KMOD_INDEX=""
KMOD_INDEX_TYPE=""


if [ "$PACKAGE_MANAGER" = "apk" ]; then

    if [ "$APK_INDEX_OK" -eq 1 ]; then

        KMOD_INDEX="$KMOD_APK_INDEX"
        KMOD_INDEX_TYPE="packages.adb"

    elif [ "$OPKG_INDEX_OK" -eq 1 ]; then

        echo
        echo "错误：源码配置为 APK，但远程 KMOD 仓库只有 OPKG 索引。"
        echo
        echo "CONFIG_USE_APK：${CONFIG_USE_APK_VALUE:-未设置}"
        echo "APK：$KMOD_APK_INDEX"
        echo "OPKG：$KMOD_OPKG_INDEX"
        exit 1

    else

        echo
        echo "错误：APK KMOD 仓库不存在有效索引。"
        echo
        echo "检查："
        echo "  $KMOD_APK_INDEX"
        echo "  $KMOD_OPKG_INDEX"
        exit 1

    fi

else

    if [ "$OPKG_INDEX_OK" -eq 1 ]; then

        KMOD_INDEX="$KMOD_OPKG_INDEX"
        KMOD_INDEX_TYPE="Packages.gz"

    elif [ "$APK_INDEX_OK" -eq 1 ]; then

        echo
        echo "错误：源码配置为 OPKG，但远程 KMOD 仓库只有 APK 索引。"
        echo
        echo "CONFIG_USE_APK：${CONFIG_USE_APK_VALUE:-未设置}"
        echo "APK：$KMOD_APK_INDEX"
        echo "OPKG：$KMOD_OPKG_INDEX"
        exit 1

    else

        echo
        echo "错误：OPKG KMOD 仓库不存在有效索引。"
        echo
        echo "检查："
        echo "  $KMOD_APK_INDEX"
        echo "  $KMOD_OPKG_INDEX"
        exit 1

    fi

fi


# ============================================================
# 最终索引确认
# ============================================================

if [ -z "$KMOD_INDEX" ] ||
   [ -z "$KMOD_INDEX_TYPE" ]; then

    echo
    echo "错误：无法确定 KMOD 索引类型。"
    exit 1

fi


echo
echo "============================================================"
echo " KMOD 索引自动识别结果"
echo "============================================================"

echo
echo "包管理器："
echo "  $PACKAGE_MANAGER"

echo
echo "索引类型："
echo "  $KMOD_INDEX_TYPE"

echo
echo "索引地址："
echo "  $KMOD_INDEX"


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
    echo "错误：.vermagic 校验失败。"
    exit 1
fi


# ============================================================
# 检查 kernel-defaults.mk
# ============================================================

echo

if grep -q '\$(TOPDIR)/\.vermagic' \
    "$TOPDIR/include/kernel-defaults.mk"
then
    echo "kernel-defaults.mk：已引用 .vermagic"
else
    echo "警告：kernel-defaults.mk 未检测到 .vermagic 引用"
fi


# ============================================================
# 检查 feeds.mk
# ============================================================

if grep -q \
    'kmods/\$(LINUX_VERSION)-\$(LINUX_RELEASE)-\$(LINUX_VERMAGIC)' \
    "$TOPDIR/include/feeds.mk"
then
    echo "feeds.mk：已使用动态 KMOD 路径"
else
    echo "警告：feeds.mk 未检测到动态 KMOD 路径"
fi


# ============================================================
# 最终结果
# ============================================================

echo
echo "============================================================"
echo " KMOD 自动修正完成"
echo "============================================================"

echo
echo "iStoreOS / OpenWrt 版本："
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
echo "包管理器："
echo "  $PACKAGE_MANAGER"

echo
echo "KMOD 目录："
echo "  $KMOD_DIR"

echo
echo "VERMAGIC："
echo "  $VERMAGIC"

echo
echo "KMOD 索引类型："
echo "  $KMOD_INDEX_TYPE"

echo
echo "KMOD 索引："
echo "  $KMOD_INDEX"

echo
echo ".vermagic："
echo "  $VERMAGIC_FILE"

echo
echo "============================================================"
echo " 完成"
echo "============================================================"
