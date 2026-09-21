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
# 核心原则：
#   1. 不判断版本号
#   2. 不写死内核版本
#   3. 不写死 KMOD hash
#   4. 不使用 Runner 宿主机内核
#   5. 不修改 LINUX_VERMAGIC
#   6. 自动识别 OPKG / APK
#   7. 根据当前源码实际构建变量查询远程 KMOD
#   8. 只能找到唯一匹配才继续
#   9. 修改失败不污染 feeds.mk
#
# 用法：
#   bash scripts/fix-kmods-feeds.sh
#
# 或：
#   bash scripts/fix-kmods-feeds.sh include/feeds.mk
#

set -e

FEEDS_MK="${1:-include/feeds.mk}"

echo
echo "============================================================"
echo " 自动 KMOD 仓库解析器"
echo " OpenWrt / iStoreOS"
echo "============================================================"
echo

# ============================================================
# 基础检查
# ============================================================

if [ ! -f "$FEEDS_MK" ]; then
    echo "ERROR: 找不到 feeds.mk：$FEEDS_MK"
    exit 1
fi

echo "feeds.mk：$FEEDS_MK"

# ============================================================
# 防止重复修改
# ============================================================

if grep -q 'KMOD_AUTO_RESOLVER_BEGIN' "$FEEDS_MK"; then
    echo
    echo "检测到 KMOD 自动解析逻辑已经存在。"
    echo "跳过修改。"
    exit 0
fi

# ============================================================
# 使用 Python 做结构化修改
# ============================================================

python3 - "$FEEDS_MK" <<'PY'
from pathlib import Path
import re
import shutil
import sys

feeds = Path(sys.argv[1])

text = feeds.read_text()

# ============================================================
# 检测 OPKG / APK
# ============================================================

has_opkg = bool(
    re.search(
        r'(?m)^define\s+FeedSourcesAppendOPKG\s*$',
        text
    )
)

has_apk = bool(
    re.search(
        r'(?m)^define\s+FeedSourcesAppendAPK\s*$',
        text
    )
)

print()
print("检测 feeds.mk 结构：")
print(f"  OPKG：{'存在' if has_opkg else '不存在'}")
print(f"  APK ：{'存在' if has_apk else '不存在'}")

if not has_opkg and not has_apk:
    print()
    print("ERROR: feeds.mk 中既没有 FeedSourcesAppendOPKG")
    print("       也没有 FeedSourcesAppendAPK。")
    print("       为避免错误修改，停止。")
    sys.exit(1)

# ============================================================
# 找到官方 KMOD 路径
#
# 同时兼容：
#
#   OPKG:
#   .../kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)
#
#   APK:
#   .../kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)/packages.adb
#
# ============================================================

kmod_pattern = re.compile(
    r'(?m)^(?P<indent>\s*)'
    r'(?P<line>.*kmods/'
    r'\$\(LINUX_VERSION\)-'
    r'\$\(LINUX_RELEASE\)-'
    r'\$\(LINUX_VERMAGIC\)'
    r'(?:/packages\.adb)?'
    r'.*)$'
)

matches = list(kmod_pattern.finditer(text))

if not matches:
    print()
    print("ERROR: 没有找到官方 KMOD vermagic 拼接逻辑。")
    print()
    print("可能原因：")
    print("  1. 当前 feeds.mk 已经被修改过；")
    print("  2. 当前源码使用了新的 feeds 机制；")
    print("  3. 当前源码结构与预期不同。")
    print()
    print("为避免生成错误 KMOD 地址，停止。")
    sys.exit(1)

print()
print("检测到 KMOD 定义：")

for m in matches:
    line = m.group("line")

    if "packages.adb" in line:
        print("  APK")
    else:
        print("  OPKG")

# ============================================================
# 判断 KMOD 定义所属 FeedSources
# ============================================================

def enclosing_define(pos):
    before = text[:pos]

    opkg = [
        m for m in re.finditer(
            r'(?m)^define\s+FeedSourcesAppendOPKG\s*$',
            before
        )
    ]

    apk = [
        m for m in re.finditer(
            r'(?m)^define\s+FeedSourcesAppendAPK\s*$',
            before
        )
    ]

    last_opkg = opkg[-1].start() if opkg else -1
    last_apk = apk[-1].start() if apk else -1

    if last_opkg > last_apk:
        return "OPKG"

    if last_apk > last_opkg:
        return "APK"

    return None


kmod_types = []

for m in matches:
    kind = enclosing_define(m.start())
    kmod_types.append(kind)

if any(x is None for x in kmod_types):
    print()
    print("ERROR: 找到了 KMOD 路径，但无法判断所属 FeedSources。")
    print("       为避免错误修改，停止。")
    sys.exit(1)

# ============================================================
# 防止已有非标准修改
# ============================================================

if "KMOD_REPO_BASE:=" in text:
    print()
    print("ERROR: feeds.mk 已存在 KMOD_REPO_BASE。")
    print("       但没有检测到标准自动解析标记。")
    print("       为避免重复/破坏修改，停止。")
    sys.exit(1)

# ============================================================
# 备份
# ============================================================

backup = feeds.with_suffix(feeds.suffix + ".kmods.bak")

if not backup.exists():
    shutil.copy2(feeds, backup)
    print()
    print(f"已备份：{backup}")

# ============================================================
# 自动 KMOD 解析器
#
# 重要：
#
# VERSION_REPO 在 include/version.mk 中已经是实际 URL。
#
# 正确：
#
#   KMOD_REPO_BASE := $(VERSION_REPO)
#
# 错误：
#
#   subst %V ...
#
# 因为 %V 是 VERSION_SED_SCRIPT 的占位符，
# 不是 VERSION_REPO 的占位符。
#
# ============================================================

resolver = r'''
# ==========================================================
# KMOD_AUTO_RESOLVER_BEGIN
#
# 自动解析远程 KMODS 目录。
#
# 不使用：
#   uname -r
#   Runner 宿主机内核
#   固定 Kernel Version
#   固定 KMOD hash
#
# 使用当前 Make 构建环境：
#   VERSION_REPO
#   BOARD
#   SUBTARGET
#   LINUX_VERSION
#   LINUX_RELEASE
#   LINUX_VERMAGIC
#
# ==========================================================

KMOD_REPO_BASE:=$(patsubst %/,%,$(VERSION_REPO))
KMOD_REPO_TARGET:=$(BOARD)/$(SUBTARGET)
KMOD_REPO_CACHE:=$(TMP_DIR)/.kmods-repository-cache

define ResolveKmodsRepository
KMOD_REPO='$(KMOD_REPO_BASE)'; \
KMOD_TARGET='$(KMOD_REPO_TARGET)'; \
KMOD_KERNEL='$(LINUX_VERSION)'; \
KMOD_RELEASE='$(LINUX_RELEASE)'; \
KMOD_VERMAGIC='$(LINUX_VERMAGIC)'; \
KMOD_CACHE='$(KMOD_REPO_CACHE)'; \
\
if [ -s "$${KMOD_CACHE}" ] && \
   [ "$$(sed -n '1p' "$${KMOD_CACHE}")" = "$${KMOD_REPO}" ] && \
   [ "$$(sed -n '2p' "$${KMOD_CACHE}")" = "$${KMOD_TARGET}" ] && \
   [ "$$(sed -n '3p' "$${KMOD_CACHE}")" = "$${KMOD_KERNEL}" ] && \
   [ "$$(sed -n '4p' "$${KMOD_CACHE}")" = "$${KMOD_RELEASE}" ] && \
   [ "$$(sed -n '5p' "$${KMOD_CACHE}")" = "$${KMOD_VERMAGIC}" ]; then \
    KMOD_PATH="$$(sed -n '6p' "$${KMOD_CACHE}")"; \
    echo "KMOD: 使用缓存 $${KMOD_PATH}" >&2; \
else \
    KMOD_INDEX="$${KMOD_REPO}/targets/$${KMOD_TARGET}/kmods/"; \
    echo "KMOD: 查询 $${KMOD_INDEX}" >&2; \
    \
    if command -v curl >/dev/null 2>&1; then \
        KMOD_HTML="$$(curl -fsSL \
            --retry 2 \
            --connect-timeout 10 \
            --max-time 30 \
            "$${KMOD_INDEX}")" || { \
            echo "ERROR: 无法访问 KMOD 仓库：" >&2; \
            echo "  $${KMOD_INDEX}" >&2; \
            exit 1; \
        }; \
    elif command -v wget >/dev/null 2>&1; then \
        KMOD_HTML="$$(wget \
            -qO- \
            --tries=2 \
            --timeout=10 \
            "$${KMOD_INDEX}")" || { \
            echo "ERROR: 无法访问 KMOD 仓库：" >&2; \
            echo "  $${KMOD_INDEX}" >&2; \
            exit 1; \
        }; \
    else \
        echo "ERROR: 当前环境没有 curl 或 wget。" >&2; \
        exit 1; \
    fi; \
    \
    KMOD_MATCHES="$$(printf '%s\n' "$${KMOD_HTML}" | \
        sed -nE 's#.*href="([^"]+/)".*#\1#p' | \
        sed 's#/$##' | \
        grep -E "^$${KMOD_KERNEL}-$${KMOD_RELEASE}-[0-9a-fA-F]{32}$$" | \
        sort -u || true)"; \
    \
    KMOD_COUNT="$$(printf '%s\n' "$${KMOD_MATCHES}" | \
        sed '/^$$/d' | \
        wc -l | \
        tr -d ' ')"; \
    \
    if [ "$${KMOD_COUNT}" -eq 0 ]; then \
        echo "ERROR: 找不到匹配的 KMODS。" >&2; \
        echo "  REPO       : $${KMOD_REPO}" >&2; \
        echo "  TARGET     : $${KMOD_TARGET}" >&2; \
        echo "  KERNEL     : $${KMOD_KERNEL}" >&2; \
        echo "  RELEASE    : $${KMOD_RELEASE}" >&2; \
        echo "  VERMAGIC   : $${KMOD_VERMAGIC}" >&2; \
        echo "  KMOD INDEX : $${KMOD_INDEX}" >&2; \
        exit 1; \
    fi; \
    \
    if [ "$${KMOD_COUNT}" -ne 1 ]; then \
        echo "ERROR: 找到多个匹配的 KMODS。" >&2; \
        echo "拒绝随机选择。" >&2; \
        printf '  %s\n' "$${KMOD_MATCHES}" >&2; \
        exit 1; \
    fi; \
    \
    KMOD_PATH="$${KMOD_MATCHES}"; \
    \
    echo "KMOD: 使用 $${KMOD_PATH}" >&2; \
    \
    { \
        printf '%s\n' "$${KMOD_REPO}"; \
        printf '%s\n' "$${KMOD_TARGET}"; \
        printf '%s\n' "$${KMOD_KERNEL}"; \
        printf '%s\n' "$${KMOD_RELEASE}"; \
        printf '%s\n' "$${KMOD_VERMAGIC}"; \
        printf '%s\n' "$${KMOD_PATH}"; \
    } > "$${KMOD_CACHE}"; \
fi
endef

# KMOD_AUTO_RESOLVER_END

'''

# ============================================================
# 插入 resolver
# ============================================================

first_define = re.search(
    r'(?m)^define\s+FeedSourcesAppend(?:OPKG|APK)\s*$',
    text
)

if not first_define:
    print("ERROR: 找不到 FeedSourcesAppend 定义。")
    sys.exit(1)

text = (
    text[:first_define.start()]
    + resolver
    + "\n"
    + text[first_define.start():]
)

# ============================================================
# 替换官方 KMOD 行
# ============================================================

replacement_count = 0

def replace_kmod(match):
    global replacement_count

    line = match.group("line")
    indent = match.group("indent")

    replacement_count += 1

    # --------------------------------------------------------
    # APK
    # --------------------------------------------------------
    if "packages.adb" in line:
        return (
            indent
            + "$(call ResolveKmodsRepository); \\\n"
            + indent
            + "\techo '%U/targets/%S/kmods/'"
            + "\"$$KMOD_PATH\""
            + "'/packages.adb';"
        )

    # --------------------------------------------------------
    # OPKG
    # --------------------------------------------------------
    return (
        indent
        + "$(call ResolveKmodsRepository); \\\n"
        + indent
        + "\techo 'src/gz %d_kmods %U/targets/%S/kmods/'"
        + "\"$$KMOD_PATH\""
        + "';"
    )

text = kmod_pattern.sub(replace_kmod, text)

if replacement_count != len(matches):
    print()
    print("ERROR: KMOD 替换数量异常。")
    print(f"  原始数量：{len(matches)}")
    print(f"  替换数量：{replacement_count}")
    print("为避免生成不完整 feeds.mk，停止。")
    sys.exit(1)

# ============================================================
# 最终结构检查
# ============================================================

if "KMOD_AUTO_RESOLVER_BEGIN" not in text:
    print("ERROR: 自动解析逻辑没有成功插入。")
    sys.exit(1)

if "KMOD_REPO_BASE:=" not in text:
    print("ERROR: KMOD_REPO_BASE 不存在。")
    sys.exit(1)

if "$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)" in text:
    print()
    print("ERROR: 仍然存在旧的 KMOD vermagic 拼接逻辑。")
    print("停止，不写入修改。")
    sys.exit(1)

# ============================================================
# 写入
# ============================================================

feeds.write_text(text)

print()
print("============================================================")
print(" KMOD 自动解析逻辑注入完成")
print("============================================================")
print()
print(f"  OPKG：{'处理' if has_opkg else '跳过'}")
print(f"  APK ：{'处理' if has_apk else '跳过'}")
print(f"  KMOD 行：{replacement_count}")
print()
PY

# ============================================================
# 最终检查
# ============================================================

echo
echo "============================================================"
echo " 最终检查"
echo "============================================================"

if ! grep -q 'KMOD_AUTO_RESOLVER_BEGIN' "$FEEDS_MK"; then
    echo "ERROR: KMOD 自动解析器不存在。"
    exit 1
fi

if ! grep -q 'KMOD_REPO_BASE:=' "$FEEDS_MK"; then
    echo "ERROR: KMOD_REPO_BASE 不存在。"
    exit 1
fi

if grep -q \
    'kmods/$(LINUX_VERSION)-$(LINUX_RELEASE)-$(LINUX_VERMAGIC)' \
    "$FEEDS_MK"; then

    echo "ERROR: 旧的 LINUX_VERMAGIC KMOD 路径仍然存在。"
    exit 1
fi

echo "检查通过。"
echo

echo "============================================================"
echo " KMOD 解析器"
echo "============================================================"

grep -n \
    -A10 \
    -B3 \
    'KMOD_REPO_BASE' \
    "$FEEDS_MK"

echo
echo "============================================================"
echo " KMOD_PATH 输出"
echo "============================================================"

grep -n \
    'KMOD_PATH' \
    "$FEEDS_MK"

echo
echo "============================================================"
echo " 完成"
echo "============================================================"
