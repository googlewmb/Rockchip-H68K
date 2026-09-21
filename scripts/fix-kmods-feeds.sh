#!/bin/bash
#
# fix-kmods-feeds.sh
#
# iStoreOS / OpenWrt 25.12
# Rockchip ARMv8 KMOD APK 官方仓库自动适配
#
# ============================================================
# 设计原则
# ============================================================
#
# 1. 不修改 include/feeds.mk
# 2. 不创建 ResolveKmodsRepository
# 3. 不创建任何虚假的 KMOD_REPO_* 变量
# 4. 不写死 LINUX_VERSION
# 5. 不写死 LINUX_RELEASE
# 6. 不写死 LINUX_VERMAGIC
# 7. 自动识别 BOARD / SUBTARGET
# 8. 自动保证 CONFIG_USE_APK=y
# 9. 自动保证 CONFIG_PER_FEED_REPO=y
# 10. 不强制修改 CONFIG_VERSION_REPO
# 11. 使用 iStoreOS 官方 FeedSourcesAppendAPK
# 12. 使用实际 kernel vermagic 计算 KMOD URL
# 13. kernel 尚未准备完成时绝不猜测 vermagic
# 14. 不执行 make clean
# 15. 不执行 make dirclean
# 16. 不删除 dl/
# 17. 不删除 build_dir/
# 18. 不删除 staging_dir/
# 19. 不删除 ccache
# 20. 尽可能保持现有构建缓存
#
# ============================================================

set -e

export LC_ALL=C

echo
echo "============================================================"
echo " fix-kmods-feeds.sh"
echo " iStoreOS / OpenWrt 25.12"
echo " Rockchip ARMv8 KMOD APK 自动适配"
echo "============================================================"
echo


# ============================================================
# 1. 定位 OpenWrt / iStoreOS 源码目录
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/.config" ] && \
   [ -f "${SCRIPT_DIR}/include/feeds.mk" ]; then

    OPENWRT_DIR="${SCRIPT_DIR}"

elif [ -d "${SCRIPT_DIR}/openwrt" ] && \
     [ -f "${SCRIPT_DIR}/openwrt/.config" ] && \
     [ -f "${SCRIPT_DIR}/openwrt/include/feeds.mk" ]; then

    OPENWRT_DIR="${SCRIPT_DIR}/openwrt"

elif [ -d "${SCRIPT_DIR}/../openwrt" ] && \
     [ -f "${SCRIPT_DIR}/../openwrt/.config" ] && \
     [ -f "${SCRIPT_DIR}/../openwrt/include/feeds.mk" ]; then

    OPENWRT_DIR="$(cd "${SCRIPT_DIR}/../openwrt" && pwd)"

else
    echo "错误：无法定位 OpenWrt / iStoreOS 源码目录。"
    echo
    echo "脚本目录：${SCRIPT_DIR}"
    exit 1
fi

OPENWRT_DIR="$(cd "${OPENWRT_DIR}" && pwd)"

cd "${OPENWRT_DIR}"

echo "源码目录："
echo "  ${OPENWRT_DIR}"
echo


# ============================================================
# 2. 基础文件检查
# ============================================================

CONFIG_FILE="${OPENWRT_DIR}/.config"
FEEDS_MK="${OPENWRT_DIR}/include/feeds.mk"
VERSION_MK="${OPENWRT_DIR}/include/version.mk"
KERNEL_MK="${OPENWRT_DIR}/include/kernel.mk"
TOP_MAKEFILE="${OPENWRT_DIR}/Makefile"

for file in \
    "${CONFIG_FILE}" \
    "${FEEDS_MK}" \
    "${VERSION_MK}" \
    "${KERNEL_MK}" \
    "${TOP_MAKEFILE}"
do
    if [ ! -f "${file}" ]; then
        echo
        echo "错误：缺少必要文件："
        echo "  ${file}"
        exit 1
    fi
done


# ============================================================
# 3. .config 读取函数
# ============================================================

get_config() {
    local name="$1"

    sed -n \
        "s/^${name}=//p" \
        "${CONFIG_FILE}" \
        | head -n1 \
        | sed \
            -e 's/^"//' \
            -e 's/"$//'
}


# ============================================================
# 4. .config 写入函数
# ============================================================

set_config() {
    local name="$1"
    local value="$2"
    local tmp

    tmp="${CONFIG_FILE}.kmod.tmp"

    if grep -q "^${name}=" "${CONFIG_FILE}"; then

        sed \
            "s|^${name}=.*|${name}=${value}|" \
            "${CONFIG_FILE}" \
            > "${tmp}"

    else

        cat "${CONFIG_FILE}" > "${tmp}"
        printf '%s\n' "${name}=${value}" >> "${tmp}"

    fi

    mv "${tmp}" "${CONFIG_FILE}"
}


# ============================================================
# 5. 读取当前配置
# ============================================================

BOARD="$(get_config CONFIG_TARGET_BOARD)"
SUBTARGET="$(get_config CONFIG_TARGET_SUBTARGET)"

VERSION_NUMBER="$(get_config CONFIG_VERSION_NUMBER)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"

PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"
USE_APK="$(get_config CONFIG_USE_APK)"

TARGET_PATH="${BOARD}/${SUBTARGET}"


# ============================================================
# 6. 显示当前配置
# ============================================================

echo "当前配置："
echo "  CONFIG_TARGET_BOARD     = ${BOARD}"
echo "  CONFIG_TARGET_SUBTARGET = ${SUBTARGET}"
echo "  CONFIG_VERSION_NUMBER   = ${VERSION_NUMBER}"
echo "  CONFIG_VERSION_REPO     = ${VERSION_REPO}"
echo "  CONFIG_PER_FEED_REPO    = ${PER_FEED_REPO}"
echo "  CONFIG_USE_APK          = ${USE_APK}"
echo


# ============================================================
# 7. 只处理 Rockchip ARMv8
# ============================================================

if [ "${BOARD}" != "rockchip" ] || \
   [ "${SUBTARGET}" != "armv8" ]; then

    echo "当前目标不是 rockchip/armv8。"
    echo
    echo "本脚本不修改其它目标。"
    echo

    exit 0
fi

echo "检测到目标："
echo "  ${TARGET_PATH}"
echo


# ============================================================
# 8. 检查版本
#
# 不把版本强行改成 25.12.5。
# 只确认当前是 25.12 系列。
# ============================================================

case "${VERSION_NUMBER}" in
    25.12|25.12.*)
        ;;
    "")
        echo "错误：CONFIG_VERSION_NUMBER 未设置。"
        echo
        echo "请先完成 .config / defconfig。"
        exit 1
        ;;
    *)
        echo "错误：当前版本不是 25.12 系列："
        echo "  ${VERSION_NUMBER}"
        echo
        echo "本脚本不会把其它版本强制指向 25.12 KMOD 仓库。"
        exit 1
        ;;
esac


# ============================================================
# 9. 检查官方 FeedSourcesAppendAPK
# ============================================================

if ! grep -q \
    '^define FeedSourcesAppendAPK' \
    "${FEEDS_MK}"
then
    echo
    echo "错误："
    echo "include/feeds.mk 中不存在官方 FeedSourcesAppendAPK。"
    echo
    echo "本脚本拒绝自行创建 KMOD 仓库逻辑。"
    exit 1
fi


# ============================================================
# 10. 检查官方 KMOD 模板
#
# 必须存在：
#
# %U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb
# ============================================================

KMOD_TEMPLATE='%U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb'

if ! grep -Fq \
    "${KMOD_TEMPLATE}" \
    "${FEEDS_MK}"
then

    echo
    echo "错误："
    echo "当前 include/feeds.mk 没有找到预期的官方 KMOD APK 模板。"
    echo
    echo "预期模板："
    echo "  ${KMOD_TEMPLATE}"
    echo
    echo "本脚本不会自行修改 feeds.mk。"
    exit 1
fi


# ============================================================
# 11. 检查是否存在以前错误脚本留下的逻辑
# ============================================================

if grep -Eq \
    'ResolveKmodsRepository|KMOD_REPO_BASE|KMOD_REPO_TARGET|KMOD_INDEX' \
    "${FEEDS_MK}"
then

    echo
    echo "错误："
    echo "检测到非官方 KMOD 自定义逻辑："
    echo
    grep -En \
        'ResolveKmodsRepository|KMOD_REPO_BASE|KMOD_REPO_TARGET|KMOD_INDEX' \
        "${FEEDS_MK}" \
        || true
    echo
    echo "请恢复官方 include/feeds.mk 后再运行。"
    exit 1
fi


# ============================================================
# 12. 检查 FeedSourcesAppendAPK 的实际上下文
# ============================================================

echo "检查官方 FeedSourcesAppendAPK："

if grep -A30 \
    '^define FeedSourcesAppendAPK' \
    "${FEEDS_MK}" \
    | grep -Fq \
        '%U/targets/%S/kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb'
then
    echo "  FeedSourcesAppendAPK：OK"
else
    echo "  错误：KMOD 模板检查失败。"
    exit 1
fi

echo


# ============================================================
# 13. 自动确保 APK
# ============================================================

if [ "${USE_APK}" != "y" ]; then

    echo "设置：CONFIG_USE_APK=y"

    set_config \
        "CONFIG_USE_APK" \
        "y"

else

    echo "CONFIG_USE_APK=y：OK"

fi


# ============================================================
# 14. 自动确保 Separate feed repositories
# ============================================================

if [ "${PER_FEED_REPO}" != "y" ]; then

    echo "设置：CONFIG_PER_FEED_REPO=y"

    set_config \
        "CONFIG_PER_FEED_REPO" \
        "y"

else

    echo "CONFIG_PER_FEED_REPO=y：OK"

fi


# ============================================================
# 15. 重新读取配置
# ============================================================

USE_APK="$(get_config CONFIG_USE_APK)"
PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"


# ============================================================
# 16. CONFIG_VERSION_REPO
#
# 这里非常重要：
#
# 不再强制改成：
# https://downloads.openwrt.org/releases/...
#
# iStoreOS 是下游发行版。
# CONFIG_VERSION_REPO 应由 iStoreOS 自己的版本配置决定。
#
# 本脚本只检查它是否存在。
# ============================================================

if [ -z "${VERSION_REPO}" ]; then

    echo
    echo "警告：CONFIG_VERSION_REPO 当前为空。"
    echo
    echo "脚本不会自行伪造 VERSION_REPO。"
    echo "请检查 iStoreOS 的版本配置。"
    echo

else

    echo "CONFIG_VERSION_REPO："
    echo "  ${VERSION_REPO}"

fi

echo


# ============================================================
# 17. 重新生成配置
#
# 不 clean。
# 不 dirclean。
# 不删除编译缓存。
# ============================================================

echo "执行：make defconfig"
echo

make defconfig


# ============================================================
# 18. defconfig 后重新读取
# ============================================================

BOARD="$(get_config CONFIG_TARGET_BOARD)"
SUBTARGET="$(get_config CONFIG_TARGET_SUBTARGET)"

VERSION_NUMBER="$(get_config CONFIG_VERSION_NUMBER)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"

USE_APK="$(get_config CONFIG_USE_APK)"
PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"

TARGET_PATH="${BOARD}/${SUBTARGET}"


# ============================================================
# 19. defconfig 后最终配置检查
# ============================================================

echo
echo "============================================================"
echo "defconfig 后最终配置"
echo "============================================================"

echo "  BOARD          = ${BOARD}"
echo "  SUBTARGET      = ${SUBTARGET}"
echo "  VERSION_NUMBER = ${VERSION_NUMBER}"
echo "  VERSION_REPO   = ${VERSION_REPO}"
echo "  USE_APK        = ${USE_APK}"
echo "  PER_FEED_REPO  = ${PER_FEED_REPO}"
echo


if [ "${BOARD}" != "rockchip" ]; then
    echo "错误：make defconfig 后 TARGET_BOARD 发生变化。"
    exit 1
fi

if [ "${SUBTARGET}" != "armv8" ]; then
    echo "错误：make defconfig 后 TARGET_SUBTARGET 发生变化。"
    exit 1
fi

if [ "${USE_APK}" != "y" ]; then
    echo "错误：make defconfig 后 CONFIG_USE_APK != y"
    exit 1
fi

if [ "${PER_FEED_REPO}" != "y" ]; then
    echo "错误：make defconfig 后 CONFIG_PER_FEED_REPO != y"
    exit 1
fi


# ============================================================
# 20. 再次确认 feeds.mk 没有被修改
# ============================================================

if ! grep -Fq \
    "${KMOD_TEMPLATE}" \
    "${FEEDS_MK}"
then

    echo
    echo "错误："
    echo "最终 feeds.mk 中没有官方 KMOD 模板。"
    exit 1
fi


# ============================================================
# 21. 获取实际 LINUX_VERSION
#
# 优先从 Make 的实际变量获取。
# 如果无法获取，再从 kernel 目录辅助读取。
#
# 绝不写死版本。
# ============================================================

LINUX_VERSION=""

LINUX_VERSION="$(
    make -s -f Makefile \
        -pn 2>/dev/null \
        | sed -n \
            's/^LINUX_VERSION[[:space:]]*[:?+]*=[[:space:]]*//p' \
        | tail -n1 \
        | sed \
            's/[[:space:]]*$//' \
        || true
)"

# 备用：从 kernel.mk 中寻找最终赋值
if [ -z "${LINUX_VERSION}" ]; then

    LINUX_VERSION="$(
        grep -E \
            '^[[:space:]]*LINUX_VERSION[[:space:]]*[:?+]?=' \
            "${KERNEL_MK}" \
            | tail -n1 \
            | sed \
                -E \
                's/^[^=]*=[[:space:]]*//' \
            | sed \
                's/[[:space:]]*$//' \
            || true
    )"

fi


# ============================================================
# 22. 获取实际 LINUX_RELEASE
# ============================================================

LINUX_RELEASE=""

LINUX_RELEASE="$(
    make -s -f Makefile \
        -pn 2>/dev/null \
        | sed -n \
            's/^LINUX_RELEASE[[:space:]]*[:?+]*=[[:space:]]*//p' \
        | tail -n1 \
        | sed \
            's/[[:space:]]*$//' \
        || true
)"

if [ -z "${LINUX_RELEASE}" ]; then

    LINUX_RELEASE="$(
        grep -E \
            '^[[:space:]]*LINUX_RELEASE[[:space:]]*[:?+]?=' \
            "${KERNEL_MK}" \
            | tail -n1 \
            | sed \
                -E \
                's/^[^=]*=[[:space:]]*//' \
            | sed \
                's/[[:space:]]*$//' \
            || true
    )"

fi


# ============================================================
# 23. 查找实际 Linux 构建目录
# ============================================================

LINUX_DIR=""

LINUX_DIR="$(
    make -s -f Makefile \
        -pn 2>/dev/null \
        | sed -n \
            's/^LINUX_DIR[[:space:]]*[:?+]*=[[:space:]]*//p' \
        | tail -n1 \
        | sed \
            's/[[:space:]]*$//' \
        || true
)"


# ============================================================
# 24. 如果 Make 输出的是相对路径，则转换成绝对路径
# ============================================================

if [ -n "${LINUX_DIR}" ] && \
   [ "${LINUX_DIR#/}" = "${LINUX_DIR}" ]; then

    LINUX_DIR="${OPENWRT_DIR}/${LINUX_DIR}"

fi


# ============================================================
# 25. 获取真实 LINUX_VERMAGIC
#
# 这里绝不猜。
#
# OpenWrt/iStoreOS 的 vermagic 可能只有在 kernel_prepare
# 或内核构建准备完成后才真正存在。
#
# 优先：
#
#   $(LINUX_DIR)/.vermagic
#
# 其次尝试 Make 实际变量。
# ============================================================

LINUX_VERMAGIC=""

if [ -n "${LINUX_DIR}" ] && \
   [ -f "${LINUX_DIR}/.vermagic" ]; then

    LINUX_VERMAGIC="$(
        cat "${LINUX_DIR}/.vermagic" \
        | head -n1 \
        | tr -d '[:space:]'
    )"

fi


# ============================================================
# 26. Make 变量备用获取
# ============================================================

if [ -z "${LINUX_VERMAGIC}" ]; then

    LINUX_VERMAGIC="$(
        make -s -f Makefile \
            -pn 2>/dev/null \
            | sed -n \
                's/^LINUX_VERMAGIC[[:space:]]*[:?+]*=[[:space:]]*//p' \
            | tail -n1 \
            | sed \
                's/[[:space:]]*$//' \
            || true
    )"

fi


# ============================================================
# 27. 清理变量中可能出现的引号
# ============================================================

LINUX_VERSION="${LINUX_VERSION%\"}"
LINUX_VERSION="${LINUX_VERSION#\"}"

LINUX_RELEASE="${LINUX_RELEASE%\"}"
LINUX_RELEASE="${LINUX_RELEASE#\"}"

LINUX_VERMAGIC="${LINUX_VERMAGIC%\"}"
LINUX_VERMAGIC="${LINUX_VERMAGIC#\"}"


# ============================================================
# 28. 显示实际解析结果
# ============================================================

echo
echo "============================================================"
echo "实际 Kernel 参数"
echo "============================================================"

echo "  LINUX_VERSION   = ${LINUX_VERSION:-<尚未解析>}"
echo "  LINUX_RELEASE   = ${LINUX_RELEASE:-<尚未解析>}"
echo "  LINUX_VERMAGIC  = ${LINUX_VERMAGIC:-<尚未生成>}"
echo "  LINUX_DIR       = ${LINUX_DIR:-<未知>}"
echo


# ============================================================
# 29. 基础变量验证
# ============================================================

if [ -z "${LINUX_VERSION}" ]; then

    echo "警告：当前无法取得 LINUX_VERSION。"
    echo
    echo "这通常表示 kernel 尚未进入 prepare 阶段。"
    echo "脚本不会猜测版本。"

fi

if [ -z "${LINUX_RELEASE}" ]; then

    echo "警告：当前无法取得 LINUX_RELEASE。"
    echo
    echo "脚本不会猜测 release。"

fi

if [ -z "${LINUX_VERMAGIC}" ]; then

    echo "警告：当前尚未生成 LINUX_VERMAGIC。"
    echo
    echo "这是正常的：如果 kernel 尚未 prepare，"
    echo "此时无法可靠知道最终 KMOD vermagic。"
    echo
    echo "不会写死 6.12.94。"
    echo "不会写死任何 vermagic。"

fi


# ============================================================
# 30. 构造 KMOD URL
#
# 只有所有真实变量都存在时才构造完整 URL。
# ============================================================

KMOD_URL=""

if [ -n "${VERSION_REPO}" ] && \
   [ -n "${LINUX_VERSION}" ] && \
   [ -n "${LINUX_RELEASE}" ] && \
   [ -n "${LINUX_VERMAGIC}" ]; then

    KMOD_URL="${VERSION_REPO}/targets/${TARGET_PATH}/kmods/${LINUX_VERSION}-${LINUX_RELEASE}-${LINUX_VERMAGIC}/packages.adb"

fi


# ============================================================
# 31. 输出完整 KMOD URL
# ============================================================

echo
echo "============================================================"
echo "KMOD APK 仓库"
echo "============================================================"

if [ -n "${KMOD_URL}" ]; then

    echo
    echo "完整 URL："
    echo
    echo "  ${KMOD_URL}"
    echo

else

    echo
    echo "当前无法生成完整 KMOD URL。"
    echo
    echo "官方模板仍然正确："
    echo
    echo "  %U/targets/%S/kmods/"
    echo "  \$(LINUX_VERSION)-\$(LINUX_RELEASE)-\$(LINUX_VERMAGIC)/packages.adb"
    echo
    echo "等待 kernel_prepare 后即可得到完整地址。"

fi


# ============================================================
# 32. 如果 URL 已经完整，则验证远端仓库
# ============================================================

check_remote_url() {

    local url="$1"

    if command -v curl >/dev/null 2>&1; then

        if curl \
            -fsS \
            --connect-timeout 10 \
            --max-time 30 \
            -o /dev/null \
            "${url}"
        then
            return 0
        fi

    elif command -v wget >/dev/null 2>&1; then

        if wget \
            -q \
            --spider \
            --timeout=30 \
            "${url}"
        then
            return 0
        fi

    else

        echo
        echo "警告：系统没有 curl 或 wget。"
        echo "无法执行远端 URL 检查。"
        return 2

    fi

    return 1
}


# ============================================================
# 33. 远端 URL 验证
# ============================================================

if [ -n "${KMOD_URL}" ]; then

    echo
    echo "检查 KMOD APK 仓库是否存在..."

    URL_CHECK_RESULT=0

    check_remote_url "${KMOD_URL}" || \
        URL_CHECK_RESULT=$?

    case "${URL_CHECK_RESULT}" in

        0)
            echo
            echo "远端 KMOD 仓库：OK"
            ;;

        1)
            echo
            echo "警告：远端 KMOD 仓库当前无法访问或不存在。"
            echo
            echo "当前 URL："
            echo "  ${KMOD_URL}"
            echo
            echo "注意："
            echo "这不代表 FeedSourcesAppendAPK 错误。"
            echo "可能原因包括："
            echo "  1. 当前 VERSION_REPO 是 iStoreOS 自己的仓库"
            echo "  2. 当前 kernel 版本尚未发布对应 KMOD 仓库"
            echo "  3. 当前 vermagic 与官方仓库不匹配"
            echo "  4. 网络暂时无法访问仓库"
            echo
            ;;

        2)
            echo
            echo "跳过远端 URL 检查。"
            ;;

    esac

fi


# ============================================================
# 34. 检查最终配置文件中是否存在错误 KMOD 自定义项
# ============================================================

if grep -REq \
    'ResolveKmodsRepository|KMOD_REPO_BASE|KMOD_REPO_TARGET|KMOD_INDEX' \
    "${OPENWRT_DIR}/include" \
    "${OPENWRT_DIR}/target" \
    2>/dev/null
then

    echo
    echo "错误：源码中仍然存在旧 KMOD 自定义逻辑。"
    echo
    echo "匹配位置："

    grep -REn \
        'ResolveKmodsRepository|KMOD_REPO_BASE|KMOD_REPO_TARGET|KMOD_INDEX' \
        "${OPENWRT_DIR}/include" \
        "${OPENWRT_DIR}/target" \
        2>/dev/null \
        || true

    echo
    echo "请删除旧逻辑后再编译。"
    exit 1

fi


# ============================================================
# 35. 清理可能残留的 package metadata
#
# 只清理临时 metadata。
# 不清理任何编译缓存。
# ============================================================

echo
echo "清理旧 package metadata..."

rm -f \
    "${OPENWRT_DIR}/tmp/.packageauxvars" \
    "${OPENWRT_DIR}/tmp/.packageinfo" \
    "${OPENWRT_DIR}/tmp/.targetinfo"


# ============================================================
# 36. 最终重新读取配置
# ============================================================

BOARD="$(get_config CONFIG_TARGET_BOARD)"
SUBTARGET="$(get_config CONFIG_TARGET_SUBTARGET)"

VERSION_NUMBER="$(get_config CONFIG_VERSION_NUMBER)"
VERSION_REPO="$(get_config CONFIG_VERSION_REPO)"

USE_APK="$(get_config CONFIG_USE_APK)"
PER_FEED_REPO="$(get_config CONFIG_PER_FEED_REPO)"


# ============================================================
# 37. 最终硬性验证
# ============================================================

if [ "${BOARD}" != "rockchip" ]; then
    echo
    echo "错误：最终 BOARD != rockchip"
    exit 1
fi

if [ "${SUBTARGET}" != "armv8" ]; then
    echo
    echo "错误：最终 SUBTARGET != armv8"
    exit 1
fi

if [ "${USE_APK}" != "y" ]; then
    echo
    echo "错误：最终 CONFIG_USE_APK != y"
    exit 1
fi

if [ "${PER_FEED_REPO}" != "y" ]; then
    echo
    echo "错误：最终 CONFIG_PER_FEED_REPO != y"
    exit 1
fi

if ! grep -Fq \
    "${KMOD_TEMPLATE}" \
    "${FEEDS_MK}"
then
    echo
    echo "错误：最终 feeds.mk 缺少官方 KMOD 模板。"
    exit 1
fi


# ============================================================
# 38. 最终结果
# ============================================================

echo
echo "============================================================"
echo " KMOD APK 自动适配完成"
echo "============================================================"
echo

echo "目标："
echo "  ${BOARD}/${SUBTARGET}"
echo

echo "APK："
echo "  CONFIG_USE_APK=y"
echo

echo "Separate feed："
echo "  CONFIG_PER_FEED_REPO=y"
echo

echo "VERSION_REPO："
echo "  ${VERSION_REPO}"
echo

echo "官方 FeedSourcesAppendAPK："
echo "  已确认"
echo

echo "官方 KMOD 模板："
echo "  ${KMOD_TEMPLATE}"
echo

if [ -n "${KMOD_URL}" ]; then

    echo "当前完整 KMOD URL："
    echo "  ${KMOD_URL}"
    echo

else

    echo "当前完整 KMOD URL："
    echo "  尚未生成"
    echo
    echo "原因：kernel vermagic 尚未产生。"
    echo "kernel_prepare / kernel 编译后将由官方 Make 变量自动生成。"
    echo

fi

echo "============================================================"
echo "重要说明"
echo "============================================================"
echo
echo "本脚本不会："
echo "  - 修改 include/feeds.mk"
echo "  - 创建 ResolveKmodsRepository"
echo "  - 创建 KMOD_REPO_*"
echo "  - 写死 6.12.94"
echo "  - 写死 LINUX_VERMAGIC"
echo "  - 强制覆盖 iStoreOS 的 VERSION_REPO"
echo "  - make clean"
echo "  - make dirclean"
echo "  - 删除 dl/"
echo "  - 删除 build_dir/"
echo "  - 删除 staging_dir/"
echo "  - 删除 ccache"
echo
echo "最终 KMOD 地址由 iStoreOS 官方 FeedSourcesAppendAPK 生成。"
echo "============================================================"
echo
