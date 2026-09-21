#!/bin/bash
#
# fix-kmods-feeds.sh
#
# iStoreOS / OpenWrt KMOD APK 仓库自动修正
#
# 支持：
#   - iStoreOS 24.10.x
#   - iStoreOS 25.12.x
#   - Rockchip / ARMv8
#   - 其他使用官方 FeedSourcesAppendAPK 机制的目标
#
# 工作原理：
#   1. 自动定位 OpenWrt/iStoreOS 源码根目录
#   2. 自动读取 CONFIG_VERSION_NUMBER
#   3. 自动读取 VERSION_REPO
#   4. 自动读取 BOARD / SUBTARGET / ARCH_PACKAGES
#   5. 自动读取 LINUX_VERSION / LINUX_RELEASE
#   6. 查询对应官方 KMOD 仓库目录
#   7. 自动寻找唯一匹配：
#        <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>
#   8. 验证 packages.adb 是否真实存在
#   9. 写入源码根目录 .vermagic
#  10. 后续由 iStoreOS 官方 kernel-defaults.mk
#      自动复制到 LINUX_DIR/.vermagic
#  11. 最终由官方 FeedSourcesAppendAPK 自动生成：
#      %U/targets/%S/kmods/<LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/packages.adb
#
# 不修改：
#   - include/feeds.mk
#   - include/kernel.mk
#   - include/kernel-defaults.mk
#   - include/kernel-version.mk
#
# 不硬编码：
#   - 6.12.94
#   - 1
#   - 5fab3a97d147fbf8146094eeebd78fd9
#

set -e

export LC_ALL=C

SCRIPT_NAME="$(basename "$0")"

echo
echo "============================================================"
echo " iStoreOS / OpenWrt KMOD APK 仓库自动修正"
echo "============================================================"
echo

###############################################################################
# 1. 定位源码根目录
###############################################################################

if [ -n "${TOPDIR:-}" ] && [ -f "$TOPDIR/Makefile" ] && [ -d "$TOPDIR/include" ]; then
    OPENWRT_ROOT="$(cd "$TOPDIR" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ -f "$SCRIPT_DIR/Makefile" ] && [ -d "$SCRIPT_DIR/include" ]; then
        OPENWRT_ROOT="$SCRIPT_DIR"
    elif [ -f "$SCRIPT_DIR/../Makefile" ] && [ -d "$SCRIPT_DIR/../include" ]; then
        OPENWRT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    else
        echo "错误：无法定位 OpenWrt / iStoreOS 源码根目录。"
        echo "请将本脚本放在源码根目录或 scripts/ 目录中执行。"
        exit 1
    fi
fi

cd "$OPENWRT_ROOT"

echo "源码目录：$OPENWRT_ROOT"
echo

###############################################################################
# 2. 检查官方源码机制
###############################################################################

for file in \
    include/kernel-defaults.mk \
    include/kernel.mk \
    include/kernel-version.mk \
    include/version.mk \
    include/feeds.mk
do
    if [ ! -f "$file" ]; then
        echo "错误：缺少官方源码文件：$file"
        exit 1
    fi
done

###############################################################################
# 3. 检查 make
###############################################################################

if ! command -v make >/dev/null 2>&1; then
    echo "错误：系统没有 make。"
    exit 1
fi

###############################################################################
# 4. 读取 .config
###############################################################################

if [ ! -f .config ]; then
    echo "错误：源码根目录不存在 .config"
    echo "请先执行：make defconfig"
    exit 1
fi

###############################################################################
# 5. 获取配置变量
#
# 使用 iStoreOS/OpenWrt 官方 rules.mk 提供的：
#
#   make val.VARIABLE
#
# 不自行猜测 Makefile 变量。
###############################################################################

get_make_var() {
    local name="$1"
    local value

    value="$(
        make -s "val.${name}" 2>/dev/null |
        sed -n "s/^${name}='//p" |
        sed "s/'$//" |
        head -n 1
    )"

    printf '%s' "$value"
}

###############################################################################
# 6. 读取版本 / 仓库
###############################################################################

VERSION_NUMBER="$(get_make_var VERSION_NUMBER)"
VERSION_REPO="$(get_make_var VERSION_REPO)"

if [ -z "$VERSION_NUMBER" ]; then
    echo "错误：无法获取 VERSION_NUMBER。"
    echo "请先执行：make defconfig"
    exit 1
fi

if [ -z "$VERSION_REPO" ]; then
    echo "错误：无法获取 VERSION_REPO。"
    exit 1
fi

echo "iStoreOS/OpenWrt 版本：$VERSION_NUMBER"
echo "软件包仓库地址：$VERSION_REPO"
echo

###############################################################################
# 7. 检查版本
#
# 不写死具体小版本。
# 允许：
#   24.10.x
#   25.12.x
###############################################################################

case "$VERSION_NUMBER" in
    24.10.*|25.12.*)
        ;;
    *)
        echo "错误：当前版本为 $VERSION_NUMBER"
        echo "本脚本目前支持 iStoreOS/OpenWrt 24.10.x 和 25.12.x。"
        exit 1
        ;;
esac

###############################################################################
# 8. KMOD 仓库必须能够通过 VERSION_REPO 访问
#
# 官方 FeedSourcesAppendAPK 使用：
#
#   %U/targets/%S/kmods/...
#
# 因此如果用户把 CONFIG_VERSION_REPO 指向完全不同的第三方仓库，
# 单独修改 .vermagic 无法把 KMOD 仓库重定向到另一个域名。
#
# 为避免生成“看起来正确、实际无法使用”的地址，这里只接受：
#
#   https://downloads.openwrt.org/releases/<VERSION>
#
###############################################################################

case "$VERSION_REPO" in
    https://downloads.openwrt.org/releases/*)
        ;;
    *)
        echo "错误：当前 VERSION_REPO 不是官方 OpenWrt releases 仓库："
        echo "  $VERSION_REPO"
        echo
        echo "官方 FeedSourcesAppendAPK 会直接使用 VERSION_REPO 生成 KMOD 地址。"
        echo "因此不能只修改 .vermagic 就把 KMOD 指向另一个域名。"
        echo
        echo "如果你的 .config 显式设置了 CONFIG_VERSION_REPO，"
        echo "请先恢复为对应的官方 OpenWrt releases 地址。"
        exit 1
        ;;
esac

###############################################################################
# 9. 获取目标平台
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
# 10. 获取 Linux 版本
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
# 11. 显示目标 KMOD 根目录
###############################################################################

KMOD_ROOT="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"

echo "KMOD 仓库根目录："
echo "  $KMOD_ROOT"
echo

###############################################################################
# 12. 下载 KMOD 根目录索引
###############################################################################

TMP_KMOD_INDEX="$(mktemp)"

cleanup() {
    rm -f "$TMP_KMOD_INDEX"
}

trap cleanup EXIT

echo "正在读取官方 KMOD 仓库目录..."

if ! curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 60 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"
then
    echo
    echo "错误：无法读取官方 KMOD 仓库目录："
    echo "  $KMOD_ROOT/"
    echo
    echo "请检查："
    echo "  1. 网络连接"
    echo "  2. VERSION_REPO 是否正确"
    echo "  3. 当前 BOARD / SUBTARGET 是否存在官方 KMOD 仓库"
    exit 1
fi

###############################################################################
# 13. 自动寻找：
#
#   <LINUX_VERSION>-<LINUX_RELEASE>-<VERMAGIC>/
#
# 例如实际可能是：
#
#   6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9/
#
# 这里绝不写死任何具体版本或 hash。
###############################################################################

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"

MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -F "^${PREFIX}" |
    sort -u || true
)"

MATCH_COUNT=0

if [ -n "$MATCHES" ]; then
    MATCH_COUNT="$(printf '%s\n' "$MATCHES" | grep -c . || true)"
fi

echo "匹配到的 KMOD 目录数量：$MATCH_COUNT"

if [ "$MATCH_COUNT" -eq 0 ]; then
    echo
    echo "错误：没有找到匹配的 KMOD 目录。"
    echo
    echo "要求："
    echo "  ${PREFIX}<VERMAGIC>/"
    echo
    echo "当前官方目录："
    echo "  $KMOD_ROOT"
    echo
    echo "这通常表示："
    echo "  - 当前 Linux 版本尚未有官方 KMOD 仓库"
    echo "  - 当前目标没有对应的官方 KMOD"
    echo "  - VERSION_REPO 与源码版本不匹配"
    echo "  - Linux 版本来自自定义 Git 内核"
    exit 1
fi

###############################################################################
# 14. 必须唯一匹配
#
# 如果官方目录出现多个同版本/release、不同 vermagic：
#
#   不能猜。
#
# 必须让编译环境自己确认，否则容易生成错误的 KMOD 依赖。
###############################################################################

if [ "$MATCH_COUNT" -gt 1 ]; then
    echo
    echo "错误：找到多个匹配的 KMOD 目录，无法安全自动选择："
    echo
    printf '%s\n' "$MATCHES" | sed 's/^/  /'
    echo
    echo "脚本拒绝猜测，以避免生成错误的 KMOD 仓库地址。"
    exit 1
fi

KMOD_DIR="$(printf '%s\n' "$MATCHES" | head -n 1)"

###############################################################################
# 15. 提取 VERMAGIC
###############################################################################

VERMAGIC="${KMOD_DIR#${PREFIX}}"

if [ -z "$VERMAGIC" ]; then
    echo "错误：无法从 KMOD 目录提取 VERMAGIC。"
    exit 1
fi

###############################################################################
# 16. 构造最终 packages.adb 地址
###############################################################################

KMOD_REPO="${KMOD_ROOT}/${KMOD_DIR}"

KMOD_APK_URL="${KMOD_REPO}/packages.adb"

echo
echo "============================================================"
echo " 自动识别结果"
echo "============================================================"
echo
echo "版本："
echo "  $VERSION_NUMBER"
echo
echo "目标："
echo "  $BOARD/$SUBTARGET"
echo
echo "Linux："
echo "  $LINUX_VERSION"
echo
echo "Linux Release："
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
# 17. 验证 packages.adb
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
    echo "错误：packages.adb 不存在或无法访问："
    echo "  $KMOD_APK_URL"
    exit 1
fi

echo "packages.adb：验证成功"
echo

###############################################################################
# 18. 检查当前 .vermagic
###############################################################################

VERMAGIC_FILE="$OPENWRT_ROOT/.vermagic"

OLD_VERMAGIC=""

if [ -f "$VERMAGIC_FILE" ]; then
    OLD_VERMAGIC="$(tr -d '\r\n' < "$VERMAGIC_FILE")"
fi

if [ "$OLD_VERMAGIC" = "$VERMAGIC" ]; then
    echo "源码根目录 .vermagic 已经正确："
    echo "  $OLD_VERMAGIC"
else
    echo "更新源码根目录 .vermagic："

    if [ -n "$OLD_VERMAGIC" ]; then
        echo "  原值：$OLD_VERMAGIC"
    else
        echo "  原值：<不存在>"
    fi

    echo "  新值：$VERMAGIC"

    printf '%s\n' "$VERMAGIC" > "$VERMAGIC_FILE"
fi

###############################################################################
# 19. 最终验证
###############################################################################

FINAL_VERMAGIC="$(tr -d '\r\n' < "$VERMAGIC_FILE")"

if [ "$FINAL_VERMAGIC" != "$VERMAGIC" ]; then
    echo
    echo "错误：.vermagic 写入验证失败。"
    exit 1
fi

###############################################################################
# 20. 输出最终 FeedSourcesAPK 应生成的地址
###############################################################################

FINAL_FEED_URL="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods/${LINUX_VERSION}-${LINUX_RELEASE}-${FINAL_VERMAGIC}/packages.adb"

echo
echo "============================================================"
echo " 修正完成"
echo "============================================================"
echo
echo ".vermagic："
echo "  $FINAL_VERMAGIC"
echo
echo "官方 FeedSourcesAppendAPK 最终 KMOD 地址："
echo "  $FINAL_FEED_URL"
echo

###############################################################################
# 21. 检查最终地址是否与实际官方地址一致
###############################################################################

if [ "$FINAL_FEED_URL" != "$KMOD_APK_URL" ]; then
    echo "错误：最终生成地址与已验证地址不一致。"
    echo
    echo "最终生成："
    echo "  $FINAL_FEED_URL"
    echo
    echo "实际验证："
    echo "  $KMOD_APK_URL"
    exit 1
fi

echo "最终地址验证：成功"
echo

###############################################################################
# 22. 检查官方机制
###############################################################################

if ! grep -q '$(TOPDIR)/.vermagic' include/kernel-defaults.mk; then
    echo "警告：当前 kernel-defaults.mk 未发现 TOPDIR/.vermagic 复制机制。"
    echo "当前源码可能不是标准 iStoreOS/OpenWrt 机制。"
    echo
fi

if ! grep -q 'kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)' include/feeds.mk; then
    echo "警告：当前 feeds.mk 未发现官方 KMOD 路径模板。"
    echo "请检查当前源码是否被第三方修改。"
    echo
fi

###############################################################################
# 23. 完成
###############################################################################

echo "============================================================"
echo " 可以继续正常编译"
echo "============================================================"
echo
echo "建议："
echo "  make defconfig"
echo "  make download -j\$(nproc)"
echo "  make -j\$(nproc)"
echo
echo "不需要修改："
echo "  include/feeds.mk"
echo "  include/kernel.mk"
echo "  include/kernel-defaults.mk"
echo "  include/kernel-version.mk"
echo
