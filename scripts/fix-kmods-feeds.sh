#!/bin/bash
#
# iStoreOS / OpenWrt KMOD APK 仓库自动修正
#
# 逻辑：
# 1. 自动识别 iStoreOS 源码目录
# 2. 检查 .config
# 3. 执行 make defconfig
# 4. 自动读取 VERSION_NUMBER
# 5. 自动读取 VERSION_REPO
# 6. 自动将 VERSION_REPO 中的 %V 替换成 VERSION_NUMBER
# 7. 自动读取 TARGET / SUBTARGET
# 8. 自动读取内核版本及 LINUX_RELEASE
# 9. 自动定位匹配的 KMOD APK 仓库
# 10. 写入 .vermagic
#

set -e

echo "============================================================"
echo " iStoreOS / OpenWrt KMOD APK 仓库自动修正"
echo "============================================================"

# ============================================================
# 1. 自动寻找源码根目录
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../.config" ]; then
    OPENWRT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -f "$SCRIPT_DIR/../../.config" ]; then
    OPENWRT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [ -f "./.config" ]; then
    OPENWRT_ROOT="$(pwd)"
else
    echo "错误：找不到 iStoreOS/OpenWrt .config"
    exit 1
fi

cd "$OPENWRT_ROOT"

echo "源码根目录："
echo "  $OPENWRT_ROOT"
echo

# ============================================================
# 2. 检查 .config
# ============================================================

if [ ! -f ".config" ]; then
    echo "错误：源码根目录不存在 .config"
    exit 1
fi

# ============================================================
# 3. 执行 defconfig
# ============================================================

echo "正在执行 make defconfig..."

make defconfig

echo "make defconfig：完成"
echo

# ============================================================
# 4. 自动读取 iStoreOS 版本信息
# ============================================================

VERSION_NUMBER=""

if [ -f "include/version.mk" ]; then
    VERSION_NUMBER="$(
        make -s -f - __fix_version_print 2>/dev/null <<EOF
TOPDIR := $OPENWRT_ROOT
include \$(TOPDIR)/.config
include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/version.mk

.PHONY: __fix_version_print

__fix_version_print:
	@printf '%s\n' "VERSION_NUMBER=\$(VERSION_NUMBER)"
EOF
    )"
fi

VERSION_NUMBER="$(
    printf '%s\n' "$VERSION_NUMBER" |
    sed -n 's/^VERSION_NUMBER=//p' |
    tail -n 1
)"

# 如果 Make 方式没有取得，则从 .config 读取
if [ -z "$VERSION_NUMBER" ]; then
    VERSION_NUMBER="$(
        sed -n 's/^CONFIG_VERSION_NUMBER="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' .config |
        tail -n 1
    )"
fi

if [ -z "$VERSION_NUMBER" ]; then
    echo "错误：无法自动识别 VERSION_NUMBER"
    exit 1
fi

echo "VERSION_NUMBER："
echo "$VERSION_NUMBER"
echo

# ============================================================
# 5. 自动读取 VERSION_REPO
#
# 重点：
# iStoreOS 可能返回：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/%V
#
# 这里绝对不能写死 OpenWrt 官方地址。
# ============================================================

VERSION_REPO=""

if [ -f "include/version.mk" ]; then
    VERSION_REPO="$(
        make -s -f - __fix_repo_print 2>/dev/null <<EOF
TOPDIR := $OPENWRT_ROOT
include \$(TOPDIR)/.config
include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/version.mk

.PHONY: __fix_repo_print

__fix_repo_print:
	@printf '%s\n' "VERSION_REPO=\$(VERSION_REPO)"
EOF
    )"
fi

VERSION_REPO="$(
    printf '%s\n' "$VERSION_REPO" |
    sed -n 's/^VERSION_REPO=//p' |
    tail -n 1
)"

# ============================================================
# 6. 如果 Make 没有读取到，则从 .config 尝试读取
# ============================================================

if [ -z "$VERSION_REPO" ]; then
    VERSION_REPO="$(
        sed -n 's/^CONFIG_VERSION_REPO="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' .config |
        tail -n 1
    )"
fi

if [ -z "$VERSION_REPO" ]; then
    echo "错误：无法自动识别 VERSION_REPO"
    exit 1
fi

echo "VERSION_REPO（原始）："
echo "$VERSION_REPO"
echo

# ============================================================
# 7. 自动展开 %V
#
# 例如：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/%V
#
# 自动变成：
#
# https://mirrors.cernet.edu.cn/openwrt/releases/25.12.5
#
# 不限制域名。
# 不写死 mirrors.cernet.edu.cn。
# ============================================================

VERSION_REPO="${VERSION_REPO//%V/$VERSION_NUMBER}"

# 同时处理可能存在的 %v
VERSION_REPO="${VERSION_REPO//%v/$VERSION_NUMBER}"

# 去掉末尾 /
VERSION_REPO="${VERSION_REPO%/}"

echo "VERSION_REPO（展开后）："
echo "$VERSION_REPO"
echo

# ============================================================
# 8. 自动读取 TARGET / SUBTARGET
# ============================================================

BOARD="$(
    sed -n 's/^CONFIG_TARGET_BOARD="\([^"]*\)"/\1/p' .config |
    tail -n 1
)"

SUBTARGET="$(
    sed -n 's/^CONFIG_TARGET_SUBTARGET="\([^"]*\)"/\1/p' .config |
    tail -n 1
)"

if [ -z "$BOARD" ] || [ -z "$SUBTARGET" ]; then
    echo "错误：无法识别 TARGET / SUBTARGET"
    echo "BOARD=$BOARD"
    echo "SUBTARGET=$SUBTARGET"
    exit 1
fi

echo "TARGET："
echo "  $BOARD"
echo

echo "SUBTARGET："
echo "  $SUBTARGET"
echo

# ============================================================
# 9. 自动读取内核版本
# ============================================================

KERNEL_INFO="$(
    make -s -f - __fix_kernel_print 2>/dev/null <<EOF
TOPDIR := $OPENWRT_ROOT

include \$(TOPDIR)/.config
include \$(TOPDIR)/rules.mk
include \$(TOPDIR)/include/kernel-version.mk
include \$(TOPDIR)/include/target.mk
include \$(TOPDIR)/include/kernel.mk

.PHONY: __fix_kernel_print

__fix_kernel_print:
	@printf '%s\n' "ARCH_PACKAGES=\$(ARCH_PACKAGES)"
	@printf '%s\n' "LINUX_VERSION=\$(LINUX_VERSION)"
	@printf '%s\n' "LINUX_RELEASE=\$(LINUX_RELEASE)"
EOF
)"

ARCH_PACKAGES="$(
    printf '%s\n' "$KERNEL_INFO" |
    sed -n 's/^ARCH_PACKAGES=//p' |
    tail -n 1
)"

LINUX_VERSION="$(
    printf '%s\n' "$KERNEL_INFO" |
    sed -n 's/^LINUX_VERSION=//p' |
    tail -n 1
)"

LINUX_RELEASE="$(
    printf '%s\n' "$KERNEL_INFO" |
    sed -n 's/^LINUX_RELEASE=//p' |
    tail -n 1
)"

# ============================================================
# 10. 如果 Make 没有取得，使用源码文件兜底
# ============================================================

if [ -z "$LINUX_VERSION" ] && [ -f "include/kernel-version.mk" ]; then
    LINUX_VERSION="$(
        awk -F':?=' '
            /^[[:space:]]*LINUX_VERSION[[:space:]]*:?=/ {
                value=$2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
            }
        ' include/kernel-version.mk |
        tail -n 1
    )"
fi

if [ -z "$LINUX_RELEASE" ] && [ -f "include/kernel-version.mk" ]; then
    LINUX_RELEASE="$(
        awk -F':?=' '
            /^[[:space:]]*LINUX_RELEASE[[:space:]]*:?=/ {
                value=$2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
            }
        ' include/kernel-version.mk |
        tail -n 1
    )"
fi

if [ -z "$ARCH_PACKAGES" ]; then
    ARCH_PACKAGES="$(
        sed -n 's/^CONFIG_ARCH_PACKAGES="\([^"]*\)"/\1/p' .config |
        tail -n 1
    )"
fi

if [ -z "$LINUX_VERSION" ]; then
    echo "错误：无法识别 LINUX_VERSION"
    exit 1
fi

if [ -z "$LINUX_RELEASE" ]; then
    echo "错误：无法识别 LINUX_RELEASE"
    exit 1
fi

echo "ARCH_PACKAGES："
echo "  $ARCH_PACKAGES"
echo

echo "LINUX_VERSION："
echo "  $LINUX_VERSION"
echo

echo "LINUX_RELEASE："
echo "  $LINUX_RELEASE"
echo

# ============================================================
# 11. 自动生成 KMOD 根目录
# ============================================================

KMOD_ROOT="${VERSION_REPO}/targets/${BOARD}/${SUBTARGET}/kmods"

echo "KMOD 根目录："
echo "  $KMOD_ROOT"
echo

# ============================================================
# 12. 下载 KMOD 目录索引
# ============================================================

TMP_KMOD_INDEX="$(mktemp)"

trap 'rm -f "$TMP_KMOD_INDEX"' EXIT

echo "正在检测 KMOD 仓库..."

if ! curl -fL --retry 3 --connect-timeout 10 \
    "$KMOD_ROOT/" \
    -o "$TMP_KMOD_INDEX"; then

    echo
    echo "错误：无法访问 KMOD 仓库："
    echo "$KMOD_ROOT"
    exit 1
fi

# ============================================================
# 13. 根据当前内核版本寻找匹配 KMOD
# ============================================================

PREFIX="${LINUX_VERSION}-${LINUX_RELEASE}-"

MATCHES="$(
    grep -oE 'href="[^"]+/"' "$TMP_KMOD_INDEX" 2>/dev/null |
    sed -E 's/^href="([^"]+)\/"$/\1/' |
    grep -E "^${PREFIX}[^/]+$" |
    sort -u || true
)"

MATCH_COUNT="$(
    printf '%s\n' "$MATCHES" |
    sed '/^[[:space:]]*$/d' |
    wc -l
)"

echo "匹配前缀："
echo "  $PREFIX"
echo

echo "匹配结果："

if [ -n "$MATCHES" ]; then
    printf '%s\n' "$MATCHES"
else
    echo "  无"
fi

echo

# ============================================================
# 14. 必须只有一个匹配结果
# ============================================================

if [ "$MATCH_COUNT" -eq 0 ]; then
    echo "错误：没有找到与当前内核匹配的 KMOD 仓库"
    exit 1
fi

if [ "$MATCH_COUNT" -gt 1 ]; then
    echo "错误：找到多个 KMOD 仓库："
    printf '%s\n' "$MATCHES"
    exit 1
fi

KMOD_DIR="$(printf '%s\n' "$MATCHES" | head -n 1)"

# ============================================================
# 15. 取得 VERMAGIC
# ============================================================

VERMAGIC="${KMOD_DIR#${PREFIX}}"

if [ -z "$VERMAGIC" ]; then
    echo "错误：无法提取 VERMAGIC"
    exit 1
fi

KMOD_REPO="${KMOD_ROOT}/${KMOD_DIR}"

echo "识别结果："
echo "  KMOD目录：$KMOD_DIR"
echo "  VERMAGIC：$VERMAGIC"
echo "  KMOD仓库：$KMOD_REPO"
echo

# ============================================================
# 16. 检查 packages.adb
# ============================================================

echo "检查 packages.adb..."

if curl -fIL --retry 3 --connect-timeout 10 \
    "${KMOD_REPO}/packages.adb" >/dev/null 2>&1; then

    echo "packages.adb：正常"

else

    echo "错误：KMOD 仓库不存在 packages.adb："
    echo "${KMOD_REPO}/packages.adb"
    exit 1

fi

echo

# ============================================================
# 17. 写入 .vermagic
# ============================================================

VERMAGIC_FILE="$OPENWRT_ROOT/.vermagic"

printf '%s\n' "$VERMAGIC" > "$VERMAGIC_FILE"

echo "已写入："
echo "  $VERMAGIC_FILE"
echo

echo "============================================================"
echo " KMOD APK 仓库自动识别完成"
echo "============================================================"

echo
echo "最终使用："
echo "  VERSION_NUMBER = $VERSION_NUMBER"
echo "  VERSION_REPO   = $VERSION_REPO"
echo "  TARGET         = $BOARD"
echo "  SUBTARGET      = $SUBTARGET"
echo "  KERNEL         = $LINUX_VERSION"
echo "  RELEASE        = $LINUX_RELEASE"
echo "  VERMAGIC       = $VERMAGIC"
echo "  KMOD_REPO      = $KMOD_REPO"
echo
