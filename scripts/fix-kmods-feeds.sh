#!/bin/bash
#
# fix-kmods-feeds.sh
#
# iStoreOS / OpenWrt 24.10.x / 25.12.x
# KMOD APK 仓库自动修正
#
# 功能：
#   1. 自动识别当前云编译源码根目录
#   2. 使用当前 .config + OpenWrt/iStoreOS Make 系统获取真实变量
#   3. 自动获取：
#        VERSION_NUMBER
#        VERSION_REPO
#        BOARD
#        SUBTARGET
#        ARCH_PACKAGES
#        LINUX_VERSION
#        LINUX_RELEASE
#   4. 自动查询官方 OpenWrt KMOD APK 仓库
#   5. 自动匹配：
#        <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/
#   6. 自动验证 packages.adb
#   7. 写入：
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
# 1. 查找 OpenWrt / iStoreOS 源码根目录
#
# 云编译环境下：
#
#   如果当前工作目录已经是源码根目录，优先直接使用。
#
# 同时兼容：
#   TOPDIR
#   GITHUB_WORKSPACE
#   脚本自身位置
###############################################################################

find_openwrt_root() {

    local dir

    # -------------------------------------------------------------------------
    # 1.1 当前工作目录
    #
    # GitHub Actions / DIY 脚本通常已经 cd 到源码根目录。
    # 这是最优先的判断。
    # -------------------------------------------------------------------------

    dir="$(pwd)"

    if [ -f "$dir/Makefile" ] &&
       [ -d "$dir/include" ] &&
       [ -f "$dir/include/kernel.mk" ]; then

        printf '%s\n' "$dir"
        return 0
    fi

    # -------------------------------------------------------------------------
    # 1.2 TOPDIR
    # -------------------------------------------------------------------------

    if [ -n "${TOPDIR:-}" ] &&
       [ -f "$TOPDIR/Makefile" ] &&
       [ -d "$TOPDIR/include" ] &&
       [ -f "$TOPDIR/include/kernel.mk" ]; then

        printf '%s\n' "$(cd "$TOPDIR" && pwd)"
        return 0
    fi

    # -------------------------------------------------------------------------
    # 1.3 GitHub Actions 工作目录
    #
    # 不假定具体目录结构，只检查真正的 OpenWrt 源码特征。
    # -------------------------------------------------------------------------

    if [ -n "${GITHUB_WORKSPACE:-}" ]; then

        for dir in \
            "$GITHUB_WORKSPACE" \
            "$GITHUB_WORKSPACE/openwrt" \
            "$GITHUB_WORKSPACE/istore/openwrt" \
            "$GITHUB_WORKSPACE/istore/istore/openwrt"
        do
            if [ -f "$dir/Makefile" ] &&
               [ -d "$dir/include" ] &&
               [ -f "$dir/include/kernel.mk" ]; then

                printf '%s\n' "$(cd "$dir" && pwd)"
                return 0
            fi
        done
    fi

    # -------------------------------------------------------------------------
    # 1.4 从脚本自身目录向上查找
    # -------------------------------------------------------------------------

    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    while [ "$dir" != "/" ]; do

        if [ -f "$dir/Makefile" ] &&
           [ -d "$dir/include" ] &&
           [ -f "$dir/include/kernel.mk" ]; then

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
    echo "错误：无法定位 OpenWrt / iStoreOS 源码根目录"
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
echo " iStoreOS / OpenWrt KMOD APK 仓库自动修正"
echo "============================================================"
echo
echo "源码根目录："
echo "  $OPENWRT_ROOT"
echo

###############################################################################
# 2. 检查官方源码文件
###############################################################################

for file in \
    Makefile \
    include/kernel-defaults.mk \
    include/kernel.mk \
    include/kernel-version.mk \
    include/version.mk \
    include/feeds.mk
do
    if [ ! -f "$file" ]; then
        echo "错误：缺少源码文件：$file"
        exit 1
    fi
done


###############################################################################
# 3. 检查 .config
###############################################################################

if [ ! -f .config ]; then

    echo "错误：源码根目录不存在 .config："
    echo "  $OPENWRT_ROOT/.config"
    exit 1

fi


###############################################################################
# 4. 执行 defconfig
#
# 让当前 .config 对应的 OpenWrt/iStoreOS Make 系统完成变量计算。
###############################################################################

echo "正在执行 make defconfig..."

make defconfig >/dev/null

echo "make defconfig：完成"
echo


###############################################################################
# 5. 使用 Make 本身读取变量
#
# 旧版本：
#
#   make -s "val.${name}"
#
# 不依赖 OpenWrt 是否提供 val.xxx target。
#
# 新方式：
#
#   临时 Makefile
#       ↓
#   include 当前 OpenWrt/iStoreOS Makefile
#       ↓
#   由 GNU Make 自己展开变量
#       ↓
#   输出最终值
#
# 这样：
#
#   LINUX_VERSION
#   VERSION_REPO
#   BOARD
#   SUBTARGET
#
# 等变量都由当前源码自身计算，而不是脚本猜测。
###############################################################################

GET_VAR_MK="$(mktemp)"

cleanup() {
    rm -f "$GET_VAR_MK"
}

trap cleanup EXIT


cat > "$GET_VAR_MK" <<'EOF'
TOPDIR := $(CURDIR)

include $(TOPDIR)/Makefile

.PHONY: __fix_kmods_print

__fix_kmods_print:
	@printf '%s\n' "VERSION_NUMBER=$(VERSION_NUMBER)"
	@printf '%s\n' "VERSION_REPO=$(VERSION_REPO)"
	@printf '%s\n' "BOARD=$(BOARD)"
	@printf '%s\n' "SUBTARGET=$(SUBTARGET)"
	@printf '%s\n' "ARCH_PACKAGES=$(ARCH_PACKAGES)"
	@printf '%s\n' "LINUX_VERSION=$(LINUX_VERSION)"
	@printf '%s\n' "LINUX_RELEASE=$(LINUX_RELEASE)"
EOF


MAKE_VARS="$(
    make -s \
        --no-print-directory \
        -f "$GET_VAR_MK" \
        __fix_kmods_print
)"


get_make_var() {

    local name="$1"

    printf '%s\n' "$MAKE_VARS" |
        sed -n "s/^${name}=//p" |
        head -n 1
}


###############################################################################
# 6. 获取版本信息
###############################################################################

VERSION_NUMBER="$(get_make_var VERSION_NUMBER)"
VERSION_REPO="$(get_make_var VERSION_REPO)"

if [ -z "$VERSION_NUMBER" ]; then
    echo "错误：无法获取 VERSION_NUMBER。"
    exit 1
fi

if [ -z "$VERSION_REPO" ]; then
    echo "错误：无法获取 VERSION_REPO。"
    exit 1
fi


echo "VERSION_NUMBER：$VERSION_NUMBER"

echo "VERSION_REPO："
echo "  $VERSION_REPO"

echo


###############################################################################
# 7. 支持 24.10.x / 25.12.x
###############################################################################

case "$VERSION_NUMBER" in

    24.10.*)

        echo "检测到 iStoreOS/OpenWrt 24.10.x"

        ;;

    25.12.*)

        echo "检测到 iStoreOS/OpenWrt 25.12.x"

        ;;

    *)

        echo
        echo "错误：不支持当前版本：$VERSION_NUMBER"
        echo
        echo "当前脚本支持："
        echo "  24.10.x"
        echo "  25.12.x"

        exit 1

        ;;

esac

echo


###############################################################################
# 8. 获取目标信息
###############################################################################

BOARD="$(get_make_var BOARD)"
SUBTARGET="$(get_make_var SUBTARGET)"
ARCH_PACKAGES="$(get_make_var ARCH_PACKAGES)"


if [ -z "$BOARD" ]; then
    echo "错误：无法获取 BOARD。"
    exit 1
fi

if [ -z "$SUBTARGET" ]; then
    echo "错误：无法获取 SUBTARGET。"
    exit 1
fi

if [ -z "$ARCH_PACKAGES" ]; then
    echo "错误：无法获取 ARCH_PACKAGES。"
    exit 1
fi


echo "BOARD：$BOARD"
echo "SUBTARGET：$SUBTARGET"
echo "ARCH_PACKAGES：$ARCH_PACKAGES"

echo


###############################################################################
# 9. 获取 Linux 信息
###############################################################################

LINUX_VERSION="$(get_make_var LINUX_VERSION)"
LINUX_RELEASE="$(get_make_var LINUX_RELEASE)"


if [ -z "$LINUX_VERSION" ]; then
    echo "错误：无法获取 LINUX_VERSION。"
    exit 1
fi

if [ -z "$LINUX_RELEASE" ]; then
    echo "错误：无法获取 LINUX_RELEASE。"
    exit 1
fi


echo "LINUX_VERSION：$LINUX_VERSION"
echo "LINUX_RELEASE：$LINUX_RELEASE"

echo


###############################################################################
# 10. 检查 VERSION_REPO
#
# iStoreOS 官方 feeds.mk 使用 VERSION_REPO 生成 KMOD Feed。
#
# 本脚本只自动寻找官方 OpenWrt releases 中已经存在的 KMOD。
# 不擅自修改 CONFIG_VERSION_REPO。
###############################################################################

case "$VERSION_REPO" in

    https://downloads.openwrt.org/releases/*)

        ;;

    *)

        echo
        echo "错误：当前 VERSION_REPO 不是官方 OpenWrt releases："
        echo
        echo "  $VERSION_REPO"
        echo
        echo "iStoreOS 官方 FeedSourcesAppendAPK 使用 VERSION_REPO"
        echo "直接生成 KMOD 仓库地址。"
        echo
        echo "因此本脚本不会擅自修改 CONFIG_VERSION_REPO。"

        exit 1

        ;;

esac


###############################################################################
# 11. 构造官方 KMOD 根目录
###############################################################################

KMOD_ROOT="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"


echo "官方 KMOD 根目录："
echo "  $KMOD_ROOT"

echo


###############################################################################
# 12. 获取官方 KMOD 目录
###############################################################################

TMP_KMOD_INDEX="$(mktemp)"

cleanup_kmod() {
    rm -f "$TMP_KMOD_INDEX"
}

trap cleanup_kmod EXIT


echo "正在查询官方 KMOD 仓库..."


if ! curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 60 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"
then

    echo
    echo "错误：无法访问官方 KMOD 仓库："
    echo "  $KMOD_ROOT/"
    echo
    echo "请检查："
    echo "  - 网络"
    echo "  - VERSION_REPO"
    echo "  - BOARD"
    echo "  - SUBTARGET"
    echo "  - 当前 Linux 版本是否存在官方 KMOD"

    exit 1

fi


###############################################################################
# 13. 自动匹配：
#
#   <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/
#
# 完全动态。
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


###############################################################################
# 14. 没有匹配
###############################################################################

if [ "$MATCH_COUNT" -eq 0 ]; then

    echo
    echo "错误：没有找到对应的官方 KMOD 仓库。"
    echo
    echo "要求匹配："
    echo "  ${PREFIX}<VERMAGIC>/"
    echo
    echo "查询目录："
    echo "  $KMOD_ROOT/"
    echo

    exit 1

fi


###############################################################################
# 15. 多个匹配
#
# 绝不猜。
###############################################################################

if [ "$MATCH_COUNT" -gt 1 ]; then

    echo
    echo "错误：找到多个匹配的 KMOD 目录："
    echo

    printf '%s\n' "$MATCHES" |
        sed 's/^/  /'

    echo
    echo "脚本不会自行选择，以避免生成错误的 KMOD 仓库。"

    exit 1

fi


###############################################################################
# 16. 提取唯一 KMOD 目录
###############################################################################

KMOD_DIR="$(printf '%s\n' "$MATCHES" | head -n 1)"

VERMAGIC="${KMOD_DIR#${PREFIX}}"


if [ -z "$VERMAGIC" ]; then

    echo "错误：无法提取 VERMAGIC。"
    exit 1

fi


###############################################################################
# 17. 构造 packages.adb
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

echo "KMOD："
echo "  $KMOD_REPO"

echo

echo "packages.adb："
echo "  $KMOD_APK_URL"

echo


###############################################################################
# 18. 验证 packages.adb
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
    echo "错误：官方 packages.adb 无法访问："
    echo "  $KMOD_APK_URL"

    exit 1

fi


echo "packages.adb：验证成功"

echo


###############################################################################
# 19. 写入源码根目录 .vermagic
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

    echo "更新："
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
# 20. 写入验证
###############################################################################

FINAL_VERMAGIC="$(
    tr -d '\r\n' < "$VERMAGIC_FILE"
)"


if [ "$FINAL_VERMAGIC" != "$VERMAGIC" ]; then

    echo
    echo "错误：.vermagic 写入验证失败。"
    exit 1

fi


###############################################################################
# 21. 最终 FeedSourcesAppendAPK 地址
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
# 22. 地址一致性验证
###############################################################################

if [ "$FINAL_FEED_URL" != "$KMOD_APK_URL" ]; then

    echo "错误：最终 Feed URL 与官方验证 URL 不一致。"
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
# 23. 验证官方源码机制
###############################################################################

if grep -q '$(TOPDIR)/.vermagic' include/kernel-defaults.mk; then

    echo "kernel-defaults.mk：官方 .vermagic 机制正常"

else

    echo "警告：未检测到 TOPDIR/.vermagic 官方机制"

fi


if grep -q 'kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)' include/feeds.mk; then

    echo "feeds.mk：官方 KMOD 路径机制正常"

else

    echo "警告：未检测到官方 KMOD 路径模板"

fi


###############################################################################
# 24. 完成
###############################################################################

echo
echo "============================================================"
echo " KMOD APK 仓库修正完成"
echo "============================================================"
echo

echo "现在可以继续正常编译："
echo
echo "  make download -j\$(nproc)"
echo "  make -j\$(nproc)"
echo

echo "无需修改官方："
echo
echo "  include/feeds.mk"
echo "  include/kernel.mk"
echo "  include/kernel-defaults.mk"
echo "  include/kernel-version.mk"
echo
