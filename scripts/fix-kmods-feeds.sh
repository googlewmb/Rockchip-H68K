#!/bin/bash
#
# fix-kmods-feeds.sh
#
# iStoreOS / OpenWrt 25.12
# KMOD APK 官方仓库自动适配
#
# 设计原则：
#   1. 不修改 include/feeds.mk
#   2. 不创建 ResolveKmodsRepository
#   3. 不创建虚假的 KMOD_REPO_* 变量
#   4. 不写死 LINUX_VERSION
#   5. 不写死 LINUX_VERMAGIC
#   6. 自动适配 BOARD / SUBTARGET
#   7. 自动保证 APK + PER_FEED_REPO
#   8. 自动保证 VERSION_REPO 指向 OpenWrt 官方 release
#   9. 最终由 iStoreOS 官方 FeedSourcesAppendAPK 生成 KMOD URL
#

set -e

echo "============================================================"
echo "fix-kmods-feeds.sh"
echo "iStoreOS / OpenWrt 25.12 KMOD APK 自动适配"
echo "============================================================"

# ============================================================
# 1. 定位 OpenWrt 源码目录
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/.config" ] && \
   [ -f "${SCRIPT_DIR}/include/feeds.mk" ]; then

    OPENWRT_DIR="${SCRIPT_DIR}"

elif [ -d "${SCRIPT_DIR}/openwrt" ] && \
     [ -f "${SCRIPT_DIR}/openwrt/.config" ]; then

    OPENWRT_DIR="${SCRIPT_DIR}/openwrt"

elif [ -d "${SCRIPT_DIR}/../openwrt" ] && \
     [ -f "${SCRIPT_DIR}/../openwrt/.config" ]; then

    OPENWRT_DIR="$(cd "${SCRIPT_DIR}/../openwrt" && pwd)"

else
    echo "错误：无法定位 OpenWrt / iStoreOS 源码目录。"
    exit 1
fi

cd "${OPENWRT_DIR}"

CONFIG_FILE="${OPENWRT_DIR}/.config"
FEEDS_MK="${OPENWRT_DIR}/include/feeds.mk"
VERSION_MK="${OPENWRT_DIR}/include/version.mk"
KERNEL_MK="${OPENWRT_DIR}/include/kernel.mk"

echo
echo "源码目录："
echo "  ${OPENWRT_DIR}"

# ============================================================
# 2. 基础文件检查
# ============================================================

for file in \
    "${CONFIG_FILE}" \
    "${FEEDS_MK}" \
    "${VERSION_MK}" \
    "${KERNEL_MK}"
do
    if [ ! -f "${file}" ]; then
        echo "错误：缺少文件：${file}"
        exit 1
    fi
done

# ============================================================
# 3. 读取 .config
# ============================================================

get_config() {
    local name="$1"

    sed -n \
        "s/^${name}=//p" \
        "${CONFIG_FILE}" \
        | head -n1 \
        | sed 's/^"//; s/"$//'
}

BOARD="$(get_config CONFIG_TARGET_BOARD)"
SUBTARGET="$(get_config CONFIG_TARGET_SUBTARGET)"
VERSION_NUMBER="$(get_config CONFIG_VERSION_NUMBER)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"
PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"
USE_APK="$(get_config CONFIG_USE_APK)"

# ============================================================
# 4. 从 version.mk 获取默认版本
# ============================================================

VERSION_MK_NUMBER="$(
    sed -n \
        's/^VERSION_NUMBER:=$(call qstrip,$(CONFIG_VERSION_NUMBER)).*/\1/p' \
        "${VERSION_MK}" \
        2>/dev/null || true
)"

# iStoreOS 25.12 分支官方默认版本
if [ -z "${VERSION_NUMBER}" ]; then
    VERSION_NUMBER="25.12.5"
fi

# ============================================================
# 5. 显示当前状态
# ============================================================

echo
echo "当前配置："
echo "  BOARD            = ${BOARD}"
echo "  SUBTARGET        = ${SUBTARGET}"
echo "  VERSION_NUMBER   = ${VERSION_NUMBER}"
echo "  VERSION_REPO     = ${VERSION_REPO}"
echo "  PER_FEED_REPO    = ${PER_FEED_REPO}"
echo "  USE_APK          = ${USE_APK}"

# ============================================================
# 6. 自动判断是否需要处理
#
# 只有 Rockchip ARMv8 才需要本修正。
# 其它目标完全不碰。
# ============================================================

if [ "${BOARD}" != "rockchip" ] || \
   [ "${SUBTARGET}" != "armv8" ]; then

    echo
    echo "当前目标不是 rockchip/armv8。"
    echo "不修改任何配置。"
    exit 0
fi

echo
echo "检测到目标：rockchip/armv8"

# ============================================================
# 7. 确认 iStoreOS 25.12 / OpenWrt 25.12
# ============================================================

case "${VERSION_NUMBER}" in
    25.12|25.12.*)
        ;;
    *)
        echo
        echo "错误：当前 VERSION_NUMBER 不是 25.12 系列："
        echo "  ${VERSION_NUMBER}"
        echo
        echo "为了避免把其它版本错误指向 OpenWrt 25.12.5，"
        echo "本脚本停止。"
        exit 1
        ;;
esac

# ============================================================
# 8. 自动确定官方 OpenWrt release
#
# 25.12.x：
#
#   VERSION_NUMBER=25.12.5
#
# 对应：
#
#   https://downloads.openwrt.org/releases/25.12.5
# ============================================================

OPENWRT_RELEASE="${VERSION_NUMBER}"

OFFICIAL_REPO="https://downloads.openwrt.org/releases/${OPENWRT_RELEASE}"

echo
echo "官方 OpenWrt Release："
echo "  ${OFFICIAL_REPO}"

# ============================================================
# 9. 检查 include/feeds.mk
#
# 必须使用官方 FeedSourcesAppendAPK。
# ============================================================

if ! grep -q 'define FeedSourcesAppendAPK' "${FEEDS_MK}"; then
    echo
    echo "错误：include/feeds.mk 不包含 FeedSourcesAppendAPK。"
    exit 1
fi

if ! grep -q 'LINUX_VERMAGIC' "${FEEDS_MK}"; then
    echo
    echo "错误：include/feeds.mk 没有使用 LINUX_VERMAGIC。"
    exit 1
fi

if ! grep -q \
    '%U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb' \
    "${FEEDS_MK}"
then
    echo
    echo "错误：当前 FeedSourcesAppendAPK 不是预期的官方 KMOD 生成逻辑。"
    echo
    echo "本脚本拒绝自行重写 feeds.mk。"
    exit 1
fi

# ============================================================
# 10. 明确拒绝旧错误逻辑
# ============================================================

if grep -q \
    'ResolveKmodsRepository\|KMOD_REPO_BASE\|KMOD_REPO_TARGET\|KMOD_INDEX' \
    "${FEEDS_MK}"
then

    echo
    echo "错误：检测到之前错误脚本留下的 KMOD 自定义逻辑。"
    echo
    echo "请恢复官方 include/feeds.mk 后再运行。"
    exit 1
fi

# ============================================================
# 11. 修改 .config
#
# KMOD APK 仓库只有在：
#
#   CONFIG_PER_FEED_REPO=y
#
# 时才会由官方 FeedSourcesAppendAPK 输出。
#
# 因此自动保证它开启。
# ============================================================

set_config() {
    local name="$1"
    local value="$2"
    local tmp

    tmp="${CONFIG_FILE}.tmp"

    if grep -q "^${name}=" "${CONFIG_FILE}"; then

        sed \
            "s|^${name}=.*|${name}=${value}|" \
            "${CONFIG_FILE}" > "${tmp}"

    else

        cat "${CONFIG_FILE}" > "${tmp}"
        printf '%s\n' "${name}=${value}" >> "${tmp}"

    fi

    mv "${tmp}" "${CONFIG_FILE}"
}

# ============================================================
# 12. 强制 APK
# ============================================================

if [ "${USE_APK}" != "y" ]; then
    echo
    echo "设置：CONFIG_USE_APK=y"
    set_config "CONFIG_USE_APK" "y"
fi

# ============================================================
# 13. 强制 Separate feed repositories
# ============================================================

if [ "${PER_FEED_REPO}" != "y" ]; then
    echo
    echo "设置：CONFIG_PER_FEED_REPO=y"
    set_config "CONFIG_PER_FEED_REPO" "y"
fi

# ============================================================
# 14. 自动设置官方 OpenWrt Release 仓库
#
# 只处理 CONFIG_VERSION_REPO。
#
# 不修改其它 feeds。
# ============================================================

CURRENT_REPO="$(get_config CONFIG_VERSION_REPO)"

if [ "${CURRENT_REPO}" != "${OFFICIAL_REPO}" ]; then

    echo
    echo "修正 CONFIG_VERSION_REPO："
    echo "  原值：${CURRENT_REPO}"
    echo "  新值：${OFFICIAL_REPO}"

    set_config \
        "CONFIG_VERSION_REPO" \
        "\"${OFFICIAL_REPO}\""

fi

# ============================================================
# 15. 重新读取配置
# ============================================================

PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"
USE_APK="$(get_config CONFIG_USE_APK)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"

# ============================================================
# 16. 最终配置验证
# ============================================================

echo
echo "============================================================"
echo "最终配置"
echo "============================================================"

echo "  BOARD          = ${BOARD}"
echo "  SUBTARGET      = ${SUBTARGET}"
echo "  VERSION_NUMBER = ${VERSION_NUMBER}"
echo "  VERSION_REPO   = ${VERSION_REPO}"
echo "  PER_FEED_REPO  = ${PER_FEED_REPO}"
echo "  USE_APK        = ${USE_APK}"

if [ "${PER_FEED_REPO}" != "y" ]; then
    echo
    echo "错误：CONFIG_PER_FEED_REPO 未成功设置为 y。"
    exit 1
fi

if [ "${USE_APK}" != "y" ]; then
    echo
    echo "错误：CONFIG_USE_APK 未成功设置为 y。"
    exit 1
fi

if [ "${VERSION_REPO}" != "${OFFICIAL_REPO}" ]; then
    echo
    echo "错误：CONFIG_VERSION_REPO 不正确。"
    exit 1
fi

# ============================================================
# 17. 解析目标路径
# ============================================================

TARGET_PATH="${BOARD}/${SUBTARGET}"

echo
echo "目标路径："
echo "  ${TARGET_PATH}"

# ============================================================
# 18. 输出最终 KMOD 模板
#
# 注意：
# 这里故意不填写 LINUX_VERSION / VERMAGIC。
# 它们必须由真正的 kernel build 提供。
# ============================================================

echo
echo "官方 KMOD URL 模板："
echo
echo "${OFFICIAL_REPO}/targets/${TARGET_PATH}/kmods/\${LINUX_VERSION}-\${LINUX_RELEASE}-\${LINUX_VERMAGIC}/packages.adb"

# ============================================================
# 19. 检查官方 feeds.mk 实际逻辑
# ============================================================

echo
echo "检查 FeedSourcesAppendAPK："

grep -A15 \
    '^define FeedSourcesAppendAPK' \
    "${FEEDS_MK}" \
    | grep -F \
    '%U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb' \
    >/dev/null

echo "  OK"

# ============================================================
# 20. 清除可能导致旧配置继续生效的临时 package metadata
#
# 不删除下载缓存。
# 不删除 dl/。
# 不删除 build_dir。
# 不删除 staging_dir。
# 不删除 ccache。
# ============================================================

rm -f \
    "${OPENWRT_DIR}/tmp/.packageauxvars" \
    "${OPENWRT_DIR}/tmp/.packageinfo" \
    "${OPENWRT_DIR}/tmp/.targetinfo"

# ============================================================
# 21. 重新生成配置依赖
#
# 不执行 make clean。
# 不执行 make dirclean。
# 不删除编译缓存。
# ============================================================

echo
echo "重新检查配置..."

make defconfig >/dev/null

# ============================================================
# 22. 再次验证 .config
# ============================================================

PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"
USE_APK="$(get_config CONFIG_USE_APK)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"

if [ "${PER_FEED_REPO}" != "y" ]; then
    echo "错误：make defconfig 后 CONFIG_PER_FEED_REPO 不为 y。"
    exit 1
fi

if [ "${USE_APK}" != "y" ]; then
    echo "错误：make defconfig 后 CONFIG_USE_APK 不为 y。"
    exit 1
fi

if [ "${VERSION_REPO}" != "${OFFICIAL_REPO}" ]; then
    echo "错误：make defconfig 后 CONFIG_VERSION_REPO 不正确。"
    echo "当前：${VERSION_REPO}"
    exit 1
fi

# ============================================================
# 23. 最终输出
# ============================================================

echo
echo "============================================================"
echo "KMOD 自动适配完成"
echo "============================================================"

echo
echo "当前目标："
echo "  ${BOARD}/${SUBTARGET}"

echo
echo "APK："
echo "  CONFIG_USE_APK=y"

echo
echo "Separate feed："
echo "  CONFIG_PER_FEED_REPO=y"

echo
echo "官方仓库："
echo "  ${OFFICIAL_REPO}"

echo
echo "KMOD 由 iStoreOS 官方 feeds.mk 自动生成："
echo
echo "  ${OFFICIAL_REPO}/targets/${BOARD}/${SUBTARGET}/kmods/"
echo '  $(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb'

echo
echo "============================================================"
echo "注意："
echo "不会在脚本中写死 6.12.94。"
echo "不会在脚本中写死 5fab3a97d147fbf8146094eeebd78fd9。"
echo "实际 KMOD 版本和 vermagic 由内核构建结果决定。"
echo "============================================================"
