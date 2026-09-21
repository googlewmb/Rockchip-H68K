#!/bin/bash
#
# fix-kmods-feeds.sh
#
# 自动修正 OpenWrt / iStoreOS KMOD 仓库解析
#
# 适用：
#   - iStoreOS 24.10
#   - iStoreOS 25.12
#   - OpenWrt 24.10
#   - OpenWrt 25.12
#
# 修正：
#   1. 保留原有 feeds.mk 机制
#   2. 保留 OPKG / APK KMOD 仓库处理
#   3. 保留 VERSION_REPO / BOARD / SUBTARGET / LINUX_VERSION / LINUX_RELEASE
#   4. 修复 Make -> define -> call -> Shell 多重展开导致的变量丢失
#   5. 修复 KMOD_REPO / KMOD_TARGET / KMOD_CACHE 被 Make 吃掉
#   6. 修复 KMOD_INDEX=/targets//kmods/
#   7. 避免引发 base-files/.pkgdir/base-files/etc/config/* 相关 shell 语法错误
#

set -e

SCRIPT_NAME="fix-kmods-feeds.sh"

OPENWRT_DIR="${OPENWRT_DIR:-$(pwd)}"

FEEDS_MK="${OPENWRT_DIR}/include/feeds.mk"

if [ ! -f "${FEEDS_MK}" ]; then
    echo "错误：找不到 ${FEEDS_MK}"
    echo "请在 OpenWrt / iStoreOS 源码根目录运行此脚本。"
    exit 1
fi

echo "============================================================"
echo " ${SCRIPT_NAME}"
echo " 自动修正 OpenWrt / iStoreOS KMOD 仓库解析"
echo "============================================================"
echo

cd "${OPENWRT_DIR}"

###############################################################################
# 备份
###############################################################################

if [ ! -f "${FEEDS_MK}.kmods.bak" ]; then
    cp -a "${FEEDS_MK}" "${FEEDS_MK}.kmods.bak"
    echo "已备份：${FEEDS_MK}.kmods.bak"
else
    echo "备份已存在：${FEEDS_MK}.kmods.bak"
fi

###############################################################################
# 检测 feeds.mk 是否已经处理
###############################################################################

if grep -q "KMOD_REPO_BASE" "${FEEDS_MK}" &&
   grep -q "KMOD_REPO_TARGET" "${FEEDS_MK}" &&
   grep -q "ResolveKmodsRepository" "${FEEDS_MK}"; then

    echo "检测到 KMOD 修正逻辑已存在，先删除旧的 KMOD 修正块。"

    python3 - "${FEEDS_MK}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

patterns = [
    r'\n?# ============================================================\n# KMOD_REPO_FIX_BEGIN.*?# KMOD_REPO_FIX_END\n?',
    r'\n?# KMOD_REPO_FIX_BEGIN.*?# KMOD_REPO_FIX_END\n?',
]

for pattern in patterns:
    text = re.sub(
        pattern,
        '\n',
        text,
        flags=re.S
    )

path.write_text(text)
PY

fi

###############################################################################
# 插入最终 KMOD 修正逻辑
#
# 关键：
# 不再使用：
#
#   define ResolveKmodsRepository
#       ...
#   endef
#
# 再通过：
#
#   $(call ResolveKmodsRepository,...)
#
# 嵌套 recipe。
#
# 原因：
# Make 的多级展开会把 Shell 的 $KMOD_xxx 吃掉，
# 最终产生：
#
#   MOD_CACHE
#   MOD_REPO
#   MOD_TARGET
#   /targets//kmods/
#
# 并可能进一步导致后面的 base-files recipe 被破坏，
# 最终表现为：
#
#   base-files/.pkgdir/base-files/etc/config/*; do if [ -f "$conffile" ];
#
#   bash: -c: line 2: syntax error: unexpected end of file
#
# 本版本把 Shell 变量全部保留在单层 recipe 中，
# 不再经过 define/call 的二次展开。
###############################################################################

cat >> "${FEEDS_MK}" <<'EOF'

# ============================================================
# KMOD_REPO_FIX_BEGIN
# ============================================================
#
# OpenWrt / iStoreOS KMOD repository resolver
#
# 注意：
# 这里故意使用普通变量定义和单层 shell recipe，
# 不使用 define/call 嵌套 resolver。
#

KMOD_REPO_BASE ?= $(VERSION_REPO)
KMOD_REPO_TARGET ?= $(BOARD)/$(SUBTARGET)
KMOD_REPO_CACHE ?= $(DL_DIR)/kmods

#
# 兼容不同版本 OpenWrt / iStoreOS：
#
# VERSION_REPO
# BOARD
# SUBTARGET
# LINUX_VERSION
# LINUX_RELEASE
#
# 均由当前源码树已有的 Make 变量提供。
#

define KMOD_REPO_VERSION
$(LINUX_VERSION)-$(LINUX_RELEASE)
endef

#
# 这里不通过 call 生成 shell 代码。
# 所有 shell 变量使用 $$，确保第一次 Make 展开后，
# Shell 仍然能够得到真正的 $变量。
#

KMOD_REPO_FIX_SCRIPT := $(TMP_DIR)/kmod-repository-resolver.sh

define KMOD_REPO_FIX_SCRIPT_CONTENT
#!/bin/sh

set -eu

KMOD_REPO_BASE="$(KMOD_REPO_BASE)"
KMOD_REPO_TARGET="$(KMOD_REPO_TARGET)"
KMOD_REPO_CACHE="$(KMOD_REPO_CACHE)"

VERSION_REPO="$(VERSION_REPO)"
BOARD="$(BOARD)"
SUBTARGET="$(SUBTARGET)"
LINUX_VERSION="$(LINUX_VERSION)"
LINUX_RELEASE="$(LINUX_RELEASE)"

if [ -z "$${KMOD_REPO_BASE}" ]; then
	KMOD_REPO_BASE="$${VERSION_REPO}"
fi

if [ -z "$${KMOD_REPO_TARGET}" ]; then
	KMOD_REPO_TARGET="$${BOARD}/$${SUBTARGET}"
fi

if [ -z "$${KMOD_REPO_CACHE}" ]; then
	KMOD_REPO_CACHE="$${DL_DIR}/kmods"
fi

#
# 去掉 VERSION_REPO 末尾的 /
#
KMOD_REPO_BASE="$${KMOD_REPO_BASE%/}"

#
# KMOD 仓库目标目录。
#
# 不使用 LINUX_VERMAGIC。
#
# KMOD 仓库目录按照：
#
#   VERSION_REPO
#   BOARD
#   SUBTARGET
#   LINUX_VERSION
#   LINUX_RELEASE
#
# 进行定位。
#

KMOD_REPO="$${KMOD_REPO_BASE}"

if [ -n "$${KMOD_REPO_TARGET}" ]; then
	KMOD_REPO="$${KMOD_REPO}/$${KMOD_REPO_TARGET}"
fi

if [ -n "$${LINUX_VERSION}" ]; then
	KMOD_REPO="$${KMOD_REPO}/$${LINUX_VERSION}"
fi

if [ -n "$${LINUX_RELEASE}" ]; then
	KMOD_REPO="$${KMOD_REPO}/$${LINUX_RELEASE}"
fi

KMOD_REPO="$${KMOD_REPO%/}"

KMOD_INDEX="$${KMOD_REPO}/kmods/"

printf '%s\n' "$${KMOD_INDEX}"
endef

#
# 生成 resolver 脚本。
#
# 这里的 $${...} 是 Make -> Shell 的唯一一层保护。
# 不再额外套 define/call。
#

$(shell \
	mkdir -p "$(TMP_DIR)" 2>/dev/null || true; \
	printf '%s\n' '#!/bin/sh' > "$(KMOD_REPO_FIX_SCRIPT)" 2>/dev/null || true; \
)

#
# OPKG / APK KMOD 仓库处理。
#
# 仅负责根据实际 OpenWrt / iStoreOS 环境选择索引格式。
#

ifeq ($(filter y,$(CONFIG_USE_APK)),y)

KMOD_PACKAGE_FORMAT := apk
KMOD_PACKAGE_INDEX := Packages.adb

else

KMOD_PACKAGE_FORMAT := opkg
KMOD_PACKAGE_INDEX := Packages.gz

endif

#
# 根据实际仓库结构生成 KMOD URL。
#
# 这里严禁使用：
#
#   $(call ResolveKmodsRepository,...)
#
# 避免 Make 二次展开。
#

KMOD_REPO_BASE := $(VERSION_REPO)
KMOD_REPO_TARGET := $(BOARD)/$(SUBTARGET)
KMOD_REPO_CACHE := $(DL_DIR)/kmods

KMOD_REPO_BASE := $(patsubst %/,%,$(KMOD_REPO_BASE))

KMOD_REPO_TARGET := $(patsubst /%,%,$(KMOD_REPO_TARGET))

KMOD_REPO_VERSION := $(LINUX_VERSION)

KMOD_REPO_RELEASE := $(LINUX_RELEASE)

#
# 最终仓库：
#
# VERSION_REPO/
#   BOARD/SUBTARGET/
#     LINUX_VERSION/
#       LINUX_RELEASE/
#         kmods/
#

KMOD_REPO_TARGET_PATH := $(KMOD_REPO_BASE)/$(KMOD_REPO_TARGET)

ifneq ($(strip $(KMOD_REPO_VERSION)),)
KMOD_REPO_TARGET_PATH := $(KMOD_REPO_TARGET_PATH)/$(KMOD_REPO_VERSION)
endif

ifneq ($(strip $(KMOD_REPO_RELEASE)),)
KMOD_REPO_TARGET_PATH := $(KMOD_REPO_TARGET_PATH)/$(KMOD_REPO_RELEASE)
endif

KMOD_REPO_TARGET_PATH := $(patsubst %/,%,$(KMOD_REPO_TARGET_PATH))

KMOD_INDEX := $(KMOD_REPO_TARGET_PATH)/kmods/

#
# KMOD 缓存目录
#

KMOD_CACHE := $(KMOD_REPO_CACHE)/$(BOARD)/$(SUBTARGET)

ifneq ($(strip $(LINUX_VERSION)),)
KMOD_CACHE := $(KMOD_CACHE)/$(LINUX_VERSION)
endif

ifneq ($(strip $(LINUX_RELEASE)),)
KMOD_CACHE := $(KMOD_CACHE)/$(LINUX_RELEASE)
endif

#
# FeedSources
#
# 保持 feeds.mk 原有 FeedSources 机制，
# 仅将 KMOD 仓库追加到现有 feed。
#

ifndef FeedSources
FeedSources :=
endif

#
# 兼容不同版本中的变量形式。
#
# 如果系统已有 KMOD feed，则不重复追加。
#

ifneq ($(strip $(KMOD_INDEX)),)

ifneq ($(findstring $(KMOD_INDEX),$(FeedSources)),)
else
FeedSources += $(KMOD_INDEX)
endif

endif

#
# KMOD URL 输出。
#
# 使用 recipe 时，Shell 变量必须写成 $$变量，
# 防止 Make 在第一次展开时把变量吞掉。
#

define KMOD_REPOSITORY_INFO
	@echo "============================================================"
	@echo "KMOD repository information"
	@echo "VERSION_REPO : $(VERSION_REPO)"
	@echo "BOARD        : $(BOARD)"
	@echo "SUBTARGET    : $(SUBTARGET)"
	@echo "LINUX_VERSION: $(LINUX_VERSION)"
	@echo "LINUX_RELEASE : $(LINUX_RELEASE)"
	@echo "KMOD_REPO    : $(KMOD_REPO_TARGET_PATH)"
	@echo "KMOD_INDEX   : $(KMOD_INDEX)"
	@echo "KMOD_CACHE   : $(KMOD_CACHE)"
	@echo "FORMAT       : $(KMOD_PACKAGE_FORMAT)"
	@echo "INDEX        : $(KMOD_PACKAGE_INDEX)"
	@echo "============================================================"
endef

#
# replace_kmod
#
# 重要：
#
#   $$(KMOD_PATH)
#
# 经过 Make 展开后才会成为：
#
#   $(KMOD_PATH)
#
# 从而交给 Shell。
#
# 不允许写成：
#
#   $(KMOD_PATH)
#
# 否则 Make 会在错误的阶段直接展开。
#

define replace_kmod
	@KMOD_PATH="$$(printf '%s\n' "$(1)")"; \
	if [ -n "$$KMOD_PATH" ]; then \
		KMOD_PATH="$${KMOD_PATH%/}"; \
	fi; \
	echo "$$KMOD_PATH"
endef

#
# ResolveKmodsRepository
#
# 保留名称以兼容可能引用该变量的外部代码，
# 但不再使用 define/call 生成复杂 shell。
#
# 这里只提供最终已经完成 Make 展开的仓库路径。
#

ResolveKmodsRepository := $(KMOD_INDEX)

#
# OPKG
#

ifeq ($(KMOD_PACKAGE_FORMAT),opkg)

KMOD_INDEX_FILE := $(KMOD_INDEX)$(KMOD_PACKAGE_INDEX)

else

#
# APK
#

KMOD_INDEX_FILE := $(KMOD_INDEX)$(KMOD_PACKAGE_INDEX)

endif

#
# ============================================================
# KMOD_REPO_FIX_END
# ============================================================

EOF

###############################################################################
# 检查关键变量
###############################################################################

echo
echo "检查 KMOD 修正结果..."

REQUIRED_VARS="
KMOD_REPO_BASE
KMOD_REPO_TARGET
KMOD_REPO_CACHE
KMOD_INDEX
KMOD_INDEX_FILE
ResolveKmodsRepository
"

for var in ${REQUIRED_VARS}; do
    if ! grep -q "${var}" "${FEEDS_MK}"; then
        echo "错误：缺少 ${var}"
        exit 1
    fi
done

###############################################################################
# 检查危险写法
###############################################################################

echo "检查 Make 二次展开风险..."

if grep -nE 'KMOD_INDEX="/targets//kmods/|KMOD_INDEX=.*/targets//kmods/' "${FEEDS_MK}" >/dev/null 2>&1; then
    echo "错误：检测到 /targets//kmods/。"
    exit 1
fi

###############################################################################
# 检查 define/call 嵌套
###############################################################################

if grep -nE '\$\(call[[:space:]]+ResolveKmodsRepository' "${FEEDS_MK}" >/dev/null 2>&1; then
    echo "错误：仍然存在 ResolveKmodsRepository 的 call 嵌套。"
    exit 1
fi

###############################################################################
# Make 语法检查
###############################################################################

echo "执行 Make 语法检查..."

if make -s -f include/feeds.mk -n >/tmp/fix-kmods-feeds-make-check.log 2>&1; then
    echo "feeds.mk Make 语法检查通过。"
else
    echo
    echo "feeds.mk Make 语法检查失败："
    cat /tmp/fix-kmods-feeds-make-check.log
    echo
    exit 1
fi

###############################################################################
# 检查是否仍存在明显的空变量路径
###############################################################################

echo "检查生成结果..."

CHECK_OUTPUT="$(
    make -s -f include/feeds.mk -pn 2>/dev/null || true
)"

if printf '%s\n' "${CHECK_OUTPUT}" |
    grep -q '/targets//kmods/'; then

    echo "错误：Make 展开结果仍然包含 /targets//kmods/"
    exit 1
fi

###############################################################################
# 检查 feeds.mk 中危险的 Shell 变量吞噬情况
###############################################################################

if grep -nE 'KMOD_(REPO|TARGET|CACHE)=\$\(.*\)' "${FEEDS_MK}" >/dev/null 2>&1; then
    echo "警告：检测到 KMOD 变量存在 Make 变量展开形式，请人工检查。"
fi

###############################################################################
# 最终结果
###############################################################################

echo
echo "============================================================"
echo " KMOD feeds 修正完成"
echo "============================================================"
echo
echo "文件："
echo "  ${FEEDS_MK}"
echo
echo "备份："
echo "  ${FEEDS_MK}.kmods.bak"
echo
echo "关键修正："
echo "  - KMOD_REPO_BASE"
echo "  - KMOD_REPO_TARGET"
echo "  - KMOD_REPO_CACHE"
echo "  - KMOD_INDEX"
echo "  - KMOD_INDEX_FILE"
echo "  - ResolveKmodsRepository"
echo "  - OPKG / APK"
echo "  - VERSION_REPO"
echo "  - BOARD / SUBTARGET"
echo "  - LINUX_VERSION / LINUX_RELEASE"
echo
echo "已避免："
echo "  - Make 二次展开吞掉 Shell 变量"
echo "  - MOD_CACHE / MOD_REPO / MOD_TARGET"
echo "  - /targets//kmods/"
echo "  - define/call 嵌套 resolver"
echo "  - 后续 recipe 被破坏"
echo "  - base-files/.pkgdir/base-files/etc/config/*"
echo "    相关的连锁 shell 语法错误"
echo
echo "============================================================"
