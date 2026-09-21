#!/bin/bash
#
# fix-kmods-feeds.sh
#
# iStoreOS 24.10.x / 25.12.x
# KMOD APK 仓库自动修正
#
# 专门适配：
#   https://github.com/istoreos/istoreos
#
# 功能：
#   1. 自动识别当前 iStoreOS 源码根目录
#   2. 使用当前 .config
#   3. 从 iStoreOS include/version.mk 获取：
#        VERSION_NUMBER
#        VERSION_REPO
#   4. 从当前 .config 获取：
#        BOARD
#        SUBTARGET
#   5. 使用 iStoreOS Make 系统获取：
#        ARCH_PACKAGES
#        LINUX_VERSION
#        LINUX_RELEASE
#   6. 自动处理 VERSION_REPO 中的 %V
#   7. 自动查询 KMOD APK 仓库
#   8. 自动匹配：
#        <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/
#   9. 自动验证 packages.adb
#  10. 写入：
#        <源码根目录>/.vermagic
#
# 不修改：
#   include/feeds.mk
#   include/kernel.mk
#   include/kernel-defaults.mk
#   include/kernel-version.mk
#
# 不硬编码：
#   Linux 版本
#   Linux Release
#   VERMAGIC
#   具体 24.10.x / 25.12.x 小版本
#

set -e

export LC_ALL=C


###############################################################################
# 1. 查找 iStoreOS 源码根目录
###############################################################################

find_openwrt_root() {

    local dir

    dir="$(pwd)"

    if [ -f "$dir/Makefile" ] &&
       [ -d "$dir/include" ] &&
       [ -f "$dir/include/kernel.mk" ] &&
       [ -f "$dir/include/version.mk" ]; then

        printf '%s\n' "$dir"
        return 0
    fi


    if [ -n "${TOPDIR:-}" ] &&
       [ -f "$TOPDIR/Makefile" ] &&
       [ -d "$TOPDIR/include" ] &&
       [ -f "$TOPDIR/include/kernel.mk" ] &&
       [ -f "$TOPDIR/include/version.mk" ]; then

        printf '%s\n' "$(cd "$TOPDIR" && pwd)"
        return 0
    fi


    if [ -n "${GITHUB_WORKSPACE:-}" ]; then

        for dir in \
            "$GITHUB_WORKSPACE" \
            "$GITHUB_WORKSPACE/openwrt" \
            "$GITHUB_WORKSPACE/istore" \
            "$GITHUB_WORKSPACE/istore/istore" \
            "$GITHUB_WORKSPACE/istore/openwrt" \
            "$GITHUB_WORKSPACE/istore/istore/openwrt"
        do

            if [ -f "$dir/Makefile" ] &&
               [ -d "$dir/include" ] &&
               [ -f "$dir/include/kernel.mk" ] &&
               [ -f "$dir/include/version.mk" ]; then

                printf '%s\n' "$(cd "$dir" && pwd)"
                return 0
            fi

        done

    fi


    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    while [ "$dir" != "/" ]; do

        if [ -f "$dir/Makefile" ] &&
           [ -d "$dir/include" ] &&
           [ -f "$dir/include/kernel.mk" ] &&
           [ -f "$dir/include/version.mk" ]; then

            printf '%s\n' "$dir"
            return 0
        fi

        dir="$(dirname "$dir")"

    done

    return 1
}


OPENWRT_ROOT="$(find_openwrt_root)" || {

    echo
    echo "============================================================"
    echo "错误：无法定位 iStoreOS 源码根目录"
    echo "============================================================"
    echo
    echo "当前目录："
    pwd
    echo
    echo "GITHUB_WORKSPACE："
    echo "${GITHUB_WORKSPACE:-<未设置>}"
    echo
    echo "TOPDIR："
    echo "${TOPDIR:-<未设置>}"
    echo
    echo "脚本位置："
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
    echo
    echo "目录内容："
    ls -la
    echo

    exit 1
}


cd "$OPENWRT_ROOT"


echo
echo "============================================================"
echo " iStoreOS KMOD APK 仓库自动修正"
echo "============================================================"
echo
echo "源码根目录："
echo "  $OPENWRT_ROOT"
echo


###############################################################################
# 2. 检查 iStoreOS 源码文件
###############################################################################

for file in \
    Makefile \
    rules.mk \
    include/version.mk \
    include/kernel.mk \
    include/kernel-defaults.mk \
    include/kernel-version.mk \
    include/target.mk \
    include/feeds.mk
do

    if [ ! -f "$file" ]; then

        echo
        echo "错误：缺少 iStoreOS 源码文件："
        echo "  $file"
        echo

        exit 1

    fi

done


###############################################################################
# 3. 检查 .config
###############################################################################

if [ ! -f ".config" ]; then

    echo
    echo "错误：源码根目录不存在 .config："
    echo "  $OPENWRT_ROOT/.config"
    echo

    exit 1

fi


###############################################################################
# 4. 执行 defconfig
###############################################################################

echo "正在执行 make defconfig..."

make defconfig >/dev/null

echo "make defconfig：完成"
echo


###############################################################################
# 5. 获取 VERSION_NUMBER / VERSION_REPO
#
# 优先使用 iStoreOS Make 系统。
###############################################################################

GET_VERSION_MK="$(mktemp)"

cat > "$GET_VERSION_MK" <<EOF
TOPDIR := $OPENWRT_ROOT

include \$(TOPDIR)/.config
include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/version.mk

.PHONY: __fix_version_print

__fix_version_print:
	@printf '%s\n' "VERSION_NUMBER=\$(VERSION_NUMBER)"
	@printf '%s\n' "VERSION_REPO=\$(VERSION_REPO)"
EOF


VERSION_VARS="$(
    make -s \
        --no-print-directory \
        -f "$GET_VERSION_MK" \
        __fix_version_print 2>/dev/null || true
)"


rm -f "$GET_VERSION_MK"


get_version_var() {

    local name="$1"

    printf '%s\n' "$VERSION_VARS" |
        sed -n "s/^${name}=//p" |
        head -n 1

}


VERSION_NUMBER="$(get_version_var "VERSION_NUMBER")"

VERSION_REPO="$(get_version_var "VERSION_REPO")"


###############################################################################
# 6. VERSION_NUMBER 备用读取
###############################################################################

if [ -z "$VERSION_NUMBER" ]; then

    VERSION_NUMBER="$(
        grep '^CONFIG_VERSION_NUMBER=' .config 2>/dev/null |
        cut -d= -f2- |
        tr -d '"' |
        head -n 1
    )"

fi


###############################################################################
# 7. VERSION_REPO 备用读取
###############################################################################

if [ -z "$VERSION_REPO" ]; then

    VERSION_REPO="$(
        grep '^CONFIG_VERSION_REPO=' .config 2>/dev/null |
        cut -d= -f2- |
        tr -d '"' |
        head -n 1
    )"

fi


###############################################################################
# 8. 检查 VERSION_NUMBER
###############################################################################

if [ -z "$VERSION_NUMBER" ]; then

    echo
    echo "错误：无法获取 VERSION_NUMBER。"
    echo
    echo "当前 .config："
    grep '^CONFIG_VERSION_NUMBER=' .config || true
    echo

    exit 1

fi


###############################################################################
# 9. 检查 VERSION_REPO
###############################################################################

if [ -z "$VERSION_REPO" ]; then

    echo
    echo "错误：无法获取 VERSION_REPO。"
    echo
    echo "当前 .config："
    grep '^CONFIG_VERSION_REPO=' .config || true
    echo

    exit 1

fi


echo "VERSION_NUMBER：$VERSION_NUMBER"

echo
echo "VERSION_REPO："
echo "  $VERSION_REPO"

echo


###############################################################################
# 10. 展开 VERSION_REPO 中的 %V
#
# iStoreOS 可能返回：
#
#   https://mirrors.cernet.edu.cn/openwrt/releases/%V
#
# 实际使用时需要变成：
#
#   https://mirrors.cernet.edu.cn/openwrt/releases/25.12.5
#
###############################################################################

VERSION_REPO="${VERSION_REPO//%V/$VERSION_NUMBER}"


echo "展开后的 VERSION_REPO："
echo "  $VERSION_REPO"
echo


###############################################################################
# 11. 支持 iStoreOS 24.10.x / 25.12.x
###############################################################################

case "$VERSION_NUMBER" in

    24.10.*)

        echo "检测到 iStoreOS 24.10.x"

        ;;

    25.12.*)

        echo "检测到 iStoreOS 25.12.x"

        ;;

    *)

        echo
        echo "错误：当前 iStoreOS 版本不在支持范围内："
        echo "  $VERSION_NUMBER"
        echo
        echo "当前支持："
        echo "  24.10.x"
        echo "  25.12.x"
        echo

        exit 1

        ;;

esac


echo


###############################################################################
# 12. 从 .config 获取 BOARD / SUBTARGET
###############################################################################

BOARD="$(
    grep '^CONFIG_TARGET_BOARD=' .config 2>/dev/null |
    cut -d= -f2- |
    tr -d '"' |
    head -n 1
)"


SUBTARGET="$(
    grep '^CONFIG_TARGET_SUBTARGET=' .config 2>/dev/null |
    cut -d= -f2- |
    tr -d '"' |
    head -n 1
)"


if [ -z "$BOARD" ]; then

    echo
    echo "错误：无法从 .config 获取："
    echo "  CONFIG_TARGET_BOARD"
    echo

    exit 1

fi


if [ -z "$SUBTARGET" ]; then

    echo
    echo "错误：无法从 .config 获取："
    echo "  CONFIG_TARGET_SUBTARGET"
    echo

    exit 1

fi


echo "BOARD：$BOARD"
echo "SUBTARGET：$SUBTARGET"
echo


###############################################################################
# 13. 获取 ARCH_PACKAGES / LINUX_VERSION / LINUX_RELEASE
###############################################################################

GET_TARGET_MK="$(mktemp)"

cat > "$GET_TARGET_MK" <<EOF
TOPDIR := $OPENWRT_ROOT

include \$(TOPDIR)/.config
include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/kernel-version.mk
include \$(TOPDIR)/include/target.mk
include \$(TOPDIR)/include/kernel.mk

.PHONY: __fix_target_print

__fix_target_print:
	@printf '%s\n' "ARCH_PACKAGES=\$(ARCH_PACKAGES)"
	@printf '%s\n' "LINUX_VERSION=\$(LINUX_VERSION)"
	@printf '%s\n' "LINUX_RELEASE=\$(LINUX_RELEASE)"
EOF


TARGET_VARS="$(
    make -s \
        --no-print-directory \
        -f "$GET_TARGET_MK" \
        __fix_target_print 2>/dev/null || true
)"


rm -f "$GET_TARGET_MK"


get_target_var() {

    local name="$1"

    printf '%s\n' "$TARGET_VARS" |
        sed -n "s/^${name}=//p" |
        head -n 1

}


ARCH_PACKAGES="$(get_target_var "ARCH_PACKAGES")"

LINUX_VERSION="$(get_target_var "LINUX_VERSION")"

LINUX_RELEASE="$(get_target_var "LINUX_RELEASE")"


###############################################################################
# 14. ARCH_PACKAGES 备用读取
###############################################################################

if [ -z "$ARCH_PACKAGES" ]; then

    ARCH_PACKAGES="$(
        grep '^CONFIG_TARGET_ARCH_PACKAGES=' .config 2>/dev/null |
        cut -d= -f2- |
        tr -d '"' |
        head -n 1
    )"

fi


###############################################################################
# 15. LINUX_VERSION 备用读取
###############################################################################

if [ -z "$LINUX_VERSION" ]; then

    LINUX_VERSION="$(
        grep -E '^LINUX_VERSION[[:space:]]*[:?+]?=' \
            include/kernel-version.mk 2>/dev/null |
        tail -n 1 |
        sed -E 's/^[^=]*=[[:space:]]*//' |
        tr -d '[:space:]'
    )"

fi


###############################################################################
# 16. LINUX_RELEASE 备用读取
###############################################################################

if [ -z "$LINUX_RELEASE" ]; then

    LINUX_RELEASE="$(
        grep -E '^LINUX_RELEASE[[:space:]]*[:?+]?=' \
            include/kernel-version.mk 2>/dev/null |
        tail -n 1 |
        sed -E 's/^[^=]*=[[:space:]]*//' |
        tr -d '[:space:]'
    )"

fi


###############################################################################
# 17. 检查目标信息
###############################################################################

if [ -z "$ARCH_PACKAGES" ]; then

    echo
    echo "错误：无法获取 ARCH_PACKAGES。"
    echo

    exit 1

fi


if [ -z "$LINUX_VERSION" ]; then

    echo
    echo "错误：无法获取 LINUX_VERSION。"
    echo

    exit 1

fi


if [ -z "$LINUX_RELEASE" ]; then

    echo
    echo "错误：无法获取 LINUX_RELEASE。"
    echo

    exit 1

fi


echo "ARCH_PACKAGES：$ARCH_PACKAGES"
echo
echo "LINUX_VERSION：$LINUX_VERSION"
echo "LINUX_RELEASE：$LINUX_RELEASE"
echo


###############################################################################
# 18. 构造 KMOD 根目录
###############################################################################

KMOD_ROOT="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"


echo "KMOD 根目录："
echo "  $KMOD_ROOT"
echo


###############################################################################
# 19. 临时文件
###############################################################################

TMP_KMOD_INDEX="$(mktemp)"


cleanup() {

    rm -f "$TMP_KMOD_INDEX"

}


trap cleanup EXIT


###############################################################################
# 20. 获取 KMOD 目录列表
###############################################################################

echo "正在查询 KMOD 仓库..."


if ! curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 60 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"
then

    echo
    echo "错误：无法访问 KMOD 仓库："
    echo
    echo "  $KMOD_ROOT/"
    echo

    exit 1

fi


###############################################################################
# 21. 自动匹配 VERMAGIC
#
# 目标：
#
#   <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/
#
# 例如：
#
#   6.12.94-1-xxxxxxxxxxxxxxxx/
###############################################################################

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"


MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -E "^${PREFIX}[^/]+$" |
    sort -u || true
)"


MATCH_COUNT=0


if [ -n "$MATCHES" ]; then

    MATCH_COUNT="$(
        printf '%s\n' "$MATCHES" |
        grep -c . || true
    )"

fi


echo "匹配结果：$MATCH_COUNT 个"
echo


###############################################################################
# 22. 没有找到
###############################################################################

if [ "$MATCH_COUNT" -eq 0 ]; then

    echo
    echo "错误：没有找到对应的 KMOD 仓库。"
    echo
    echo "要求："
    echo "  ${PREFIX}<VERMAGIC>/"
    echo
    echo "查询："
    echo "  $KMOD_ROOT/"
    echo

    exit 1

fi


###############################################################################
# 23. 找到多个
###############################################################################

if [ "$MATCH_COUNT" -gt 1 ]; then

    echo
    echo "错误：找到多个匹配的 KMOD 目录："
    echo

    printf '%s\n' "$MATCHES" |
        sed 's/^/  /'

    echo
    echo "为了避免选择错误 VERMAGIC，脚本停止。"
    echo

    exit 1

fi


###############################################################################
# 24. 获取 VERMAGIC
###############################################################################

KMOD_DIR="$(printf '%s\n' "$MATCHES" | head -n 1)"

VERMAGIC="${KMOD_DIR#${PREFIX}}"


if [ -z "$VERMAGIC" ]; then

    echo
    echo "错误：无法获取 VERMAGIC。"
    echo

    exit 1

fi


###############################################################################
# 25. 构造最终 KMOD URL
###############################################################################

KMOD_REPO="${KMOD_ROOT}/${KMOD_DIR}"

KMOD_APK_URL="${KMOD_REPO}/packages.adb"


echo
echo "============================================================"
echo " 官方 KMOD 自动识别结果"
echo "============================================================"
echo

echo "版本："
echo "  $VERSION_NUMBER"

echo

echo "目标："
echo "  $BOARD/$SUBTARGET"

echo

echo "架构："
echo "  $ARCH_PACKAGES"

echo

echo "Linux："
echo "  $LINUX_VERSION"

echo

echo "Release："
echo "  $LINUX_RELEASE"

echo

echo "VERMAGIC："
echo "  $VERMAGIC"

echo

echo "KMOD 仓库："
echo "  $KMOD_REPO"

echo

echo "packages.adb："
echo "  $KMOD_APK_URL"

echo


###############################################################################
# 26. 验证 packages.adb
###############################################################################

echo "正在验证 packages.adb..."


if ! curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 60 \
    -o /dev/null \
    "$KMOD_APK_URL"
then

    echo
    echo "错误：packages.adb 无法访问："
    echo
    echo "  $KMOD_APK_URL"
    echo

    exit 1

fi


echo "packages.adb：验证成功"
echo


###############################################################################
# 27. 写入 .vermagic
###############################################################################

VERMAGIC_FILE="$OPENWRT_ROOT/.vermagic"

OLD_VERMAGIC=""


if [ -f "$VERMAGIC_FILE" ]; then

    OLD_VERMAGIC="$(
        tr -d '\r\n' < "$VERMAGIC_FILE"
    )"

fi


if [ "$OLD_VERMAGIC" = "$VERMAGIC" ]; then

    echo ".vermagic 已经正确："
    echo "  $OLD_VERMAGIC"

else

    echo "更新 .vermagic："
    echo "  $VERMAGIC_FILE"

    if [ -n "$OLD_VERMAGIC" ]; then

        echo "原值："
        echo "  $OLD_VERMAGIC"

    else

        echo "原值：<不存在>"

    fi

    echo "新值："
    echo "  $VERMAGIC"

    printf '%s\n' "$VERMAGIC" > "$VERMAGIC_FILE"

fi


###############################################################################
# 28. 验证 .vermagic
###############################################################################

FINAL_VERMAGIC="$(
    tr -d '\r\n' < "$VERMAGIC_FILE"
)"


if [ "$FINAL_VERMAGIC" != "$VERMAGIC" ]; then

    echo
    echo "错误：.vermagic 写入验证失败。"
    echo

    exit 1

fi


###############################################################################
# 29. 最终 Feed URL
###############################################################################

FINAL_FEED_URL="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods/${LINUX_VERSION}-${LINUX_RELEASE}-${FINAL_VERMAGIC}/packages.adb"


echo
echo "============================================================"
echo " 最终结果"
echo "============================================================"
echo

echo "源码："
echo "  $OPENWRT_ROOT"

echo

echo ".vermagic："
echo "  $FINAL_VERMAGIC"

echo

echo "KMOD APK："
echo "  $FINAL_FEED_URL"

echo


###############################################################################
# 30. URL 一致性验证
###############################################################################

if [ "$FINAL_FEED_URL" != "$KMOD_APK_URL" ]; then

    echo
    echo "错误：最终 Feed URL 与验证 URL 不一致。"
    echo

    echo "最终："
    echo "  $FINAL_FEED_URL"

    echo

    echo "验证："
    echo "  $KMOD_APK_URL"

    exit 1

fi


echo "最终 URL：验证成功"
echo


###############################################################################
# 31. 验证 iStoreOS KMOD 机制
###############################################################################

if grep -q '$(TOPDIR)/.vermagic' include/kernel-defaults.mk; then

    echo "kernel-defaults.mk：.vermagic 机制正常"

else

    echo "警告：未检测到 TOPDIR/.vermagic 机制"

fi


if grep -q 'kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)' include/feeds.mk; then

    echo "feeds.mk：KMOD 路径机制正常"

else

    echo "警告：未检测到 KMOD 路径模板"

fi


###############################################################################
# 32. 完成
###############################################################################

echo
echo "============================================================"
echo " iStoreOS KMOD APK 仓库修正完成"
echo "============================================================"
echo

echo "已生成："
echo "  $VERMAGIC_FILE"

echo

echo "最终 KMOD："
echo "  $FINAL_FEED_URL"

echo

echo "后续可以继续："
echo
echo "  make download -j\$(nproc)"
echo "  make -j\$(nproc)"
echo
