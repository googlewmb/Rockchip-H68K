#!/bin/bash
#
# DIY2 - H68K + iStoreOS 24.10
#

set -e

[ -d "$TOPDIR" ] || TOPDIR="$(pwd)"
cd "$TOPDIR"

echo "DIY2 - H68K + iStoreOS 24.10"


###############################################################################
# 1. PassWall
###############################################################################

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/passwall-packages package/passwall-luci

git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci

./scripts/feeds install -p packages golang || true
./scripts/feeds install -f microsocks || true
./scripts/feeds install -a


###############################################################################
# 2. Feed 优先级
###############################################################################

REMOVE_OFFICIAL_DEPS=""

OFFICIAL_FEEDS="packages luci routing telephony store third"
THIRD_PARTY_FEEDS="nas nas_luci jjm2473_apps kenzo small"

package_entry_exists() {
    local e="package/feeds/$1/$2"
    [ -e "$e" ] || [ -L "$e" ]
}

remove_package_entry() {
    local e="package/feeds/$1/$2"
    [ -e "$e" ] || [ -L "$e" ] && {
        echo "删除: $1/$2"
        rm -f "$e"
    }
}

package_makefile() {
    local f="package/feeds/$1/$2/Makefile"
    [ -f "$f" ] && readlink -f "$f" 2>/dev/null || true
}

get_package_version() {
    local v=""
    [ -f "$1" ] || { echo unknown; return; }
    v=$(sed -nE 's/^[[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*(.*)$/\1/p' "$1" | head -1)
    [ -n "$v" ] || v=$(sed -nE 's/^[[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*(.*)$/release-\1/p' "$1" | head -1)
    echo "${v:-unknown}"
}

for pkg in $REMOVE_OFFICIAL_DEPS; do
    for f in $OFFICIAL_FEEDS; do
        remove_package_entry "$f" "$pkg"
    done
done


###############################################################################
# 3. H68K DTS + DTSI
###############################################################################

echo
echo "===== H68K DTS ====="

DTS_SOURCE="$GITHUB_WORKSPACE/test-istore/diy/H68K-DTS Linux6.1-6.6.dts"
DTSI="target/linux/rockchip/dts/rk3568/rk3568-hinlink.dtsi"

if [ -f "$DTS_SOURCE" ]; then

    mkdir -p target/linux/rockchip/dts/rk3568
    mkdir -p target/linux/rockchip/files/arch/arm64/boot/dts/rockchip

    cp -f "$DTS_SOURCE" target/linux/rockchip/dts/rk3568/rk3568-opc-h68k.dts
    cp -f "$DTS_SOURCE" target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-opc-h68k.dts
    cp -f "$DTS_SOURCE" target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-hinlink-opc-h68k.dts

    echo "✓ H68K DTS"

else
    echo "WARNING: H68K DTS 不存在: $DTS_SOURCE"
fi

[ -f "$DTSI" ] || {
    echo "❌ DTSI 不存在: $DTSI"
    exit 1
}

cp -f "$DTSI" "$DTSI.bak"

# 删除 DTSI 中由 H68K DTS 接管的板级节点
python3 - "$DTSI" <<'PY'
import sys,re

p=sys.argv[1]
s=open(p,encoding="utf-8").read()

def rmblock(s,pat,name):
    m=re.search(pat,s,re.M)
    if not m:
        return s
    a=m.start()
    b=s.find("{",m.start())
    if b<0: raise RuntimeError(name)
    d=0
    for i in range(b,len(s)):
        if s[i]=="{": d+=1
        elif s[i]=="}":
            d-=1
            if d==0:
                e=i+1
                while e<len(s) and s[e] in " \t": e+=1
                if e<len(s) and s[e]==";": e+=1
                if e<len(s) and s[e]=="\n": e+=1
                print("  ✓ 删除",name)
                return s[:a]+s[e:]
    raise RuntimeError("括号错误: "+name)

nodes=[
(r"^[ \t]*aliases[ \t]*\{","aliases"),
(r"^[ \t]*chosen[ \t]*\{","chosen"),
(r"^[ \t]*dc_12v[ \t]*:[^{\n]*\{","dc_12v"),
(r"^[ \t]*vcc5v0_sys[ \t]*:[^{\n]*\{","vcc5v0_sys"),
(r"^[ \t]*vcc3v3_sys[ \t]*:[^{\n]*\{","vcc3v3_sys"),
(r"^[ \t]*vcc5v0_otg[ \t]*:[^{\n]*\{","vcc5v0_otg"),
(r"^[ \t]*vcc3v3_pcie[ \t]*:[^{\n]*\{","vcc3v3_pcie"),
(r"^[ \t]*gpio-keys[ \t]*\{","gpio-keys"),
(r"^[ \t]*leds[ \t]*\{","leds"),
(r"^[ \t]*hdmi-con[ \t]*\{","hdmi-con"),
]

for x,n in nodes:
    s=rmblock(s,x,n)

s=s.replace(
    "vpcie3v3-supply = <&vcc3v3_pcie>;",
    ""
)

s=s.replace(
    "phy-supply = <&vcc5v0_otg>;",
    "phy-supply = <&vcc5v0_usb_otg>;"
)

open(p,"w",encoding="utf-8").write(s)
PY

# H68K 已经定义完整 HDMI endpoint 时，移除公共 DTSI 的重复 fragment
if [ -f "$DTS_SOURCE" ] &&
   grep -Eq '^[[:space:]]*hdmi_in_vp0[[:space:]]*:' "$DTS_SOURCE" &&
   grep -Eq '^[[:space:]]*hdmi_out_con[[:space:]]*:' "$DTS_SOURCE" &&
   grep -Eq '^[[:space:]]*vp0_out_hdmi[[:space:]]*:' "$DTS_SOURCE"; then

    python3 - "$DTSI" <<'PY'
import sys,re

p=sys.argv[1]
s=open(p,encoding="utf-8").read()

def rm(s,node):
    m=re.search(r"(?m)^[ \t]*&"+re.escape(node)+r"[ \t]*\{",s)
    if not m: return s
    a=m.start(); b=s.find("{",m.start()); d=0
    for i in range(b,len(s)):
        if s[i]=="{": d+=1
        elif s[i]=="}":
            d-=1
            if d==0:
                e=i+1
                while e<len(s) and s[e] in " \t": e+=1
                if e<len(s) and s[e]==";": e+=1
                if e<len(s) and s[e]=="\n": e+=1
                print("  ✓ 删除 HDMI:",node)
                return s[:a]+s[e:]
    raise RuntimeError("HDMI 括号错误: "+node)

for n in ("hdmi_in","hdmi_out","vp0"):
    s=rm(s,n)

open(p,"w",encoding="utf-8").write(s)
PY
fi

# DTSI 最终检查
BAD=0

for x in dc_12v vcc5v0_sys vcc3v3_sys vcc5v0_otg vcc3v3_pcie; do
    if grep -Eq "^[[:space:]]*$x[[:space:]]*:" "$DTSI"; then
        echo "❌ DTSI 残留: $x"
        BAD=1
    fi
done

grep -q "&vcc5v0_otg" "$DTSI" && {
    echo "❌ DTSI 仍引用 vcc5v0_otg"
    BAD=1
}

grep -q "vpcie3v3-supply = <&vcc3v3_pcie>;" "$DTSI" && {
    echo "❌ DTSI 仍引用旧 PCIe 电源"
    BAD=1
}

[ "$BAD" -eq 0 ] || {
    echo "❌ H68K DTSI 修复失败，备份: $DTSI.bak"
    exit 1
}

echo "✓ H68K DTSI 修复完成"


###############################################################################
# 4.5 扫描 package/myapp
###############################################################################

MYAPP_PACKAGES=""

if [ -d package/myapp ]; then
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            '$('*|*'/'*) continue ;;
        esac
        MYAPP_PACKAGES="$MYAPP_PACKAGES
$pkg"
        echo "✓ $pkg"
    done < <(
        find package/myapp -type f -name Makefile -print0 2>/dev/null |
        xargs -0 -r sed -nE \
        's/^[[:space:]]*define[[:space:]]+Package\/([A-Za-z0-9_.+@:-]+)[[:space:]]*$/\1/p' |
        sort -u || true
    )
fi


###############################################################################
# 5. 当前 .config
###############################################################################

CONFIG_PACKAGES=""

[ -f .config ] && CONFIG_PACKAGES="$(
    sed -nE \
    's/^CONFIG_PACKAGE_([A-Za-z0-9_.+@:-]+)=(y|m)$/\1/p' \
    .config | sort -u
)"

echo "启用 Package 数量: $(printf '%s\n' "$CONFIG_PACKAGES" | sed '/^$/d' | wc -l)"


###############################################################################
# 6. package/myapp 优先
###############################################################################

for pkg in $MYAPP_PACKAGES; do

    [ -n "$pkg" ] || continue

    MF=""

    while IFS= read -r -d '' f; do
        if grep -q \
            "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*$" \
            "$f" 2>/dev/null; then
            MF="$f"
            break
        fi
    done < <(
        find package/myapp -type f -name Makefile -print0 2>/dev/null || true
    )

    echo
    echo "[$pkg]"

    [ -n "$MF" ] && echo "myapp: $(get_package_version "$MF")"

    for feed in $THIRD_PARTY_FEEDS $OFFICIAL_FEEDS; do
        if package_entry_exists "$feed" "$pkg"; then
            echo "删除重复来源: $feed/$pkg"
            remove_package_entry "$feed" "$pkg"
        fi
    done

done


###############################################################################
# 7. 第三方 Feed 优先
###############################################################################

for pkg in $CONFIG_PACKAGES; do

    case "
$MYAPP_PACKAGES
" in
        *"
$pkg
"*) continue ;;
    esac

    SRC=""

    for feed in $THIRD_PARTY_FEEDS; do
        if package_entry_exists "$feed" "$pkg"; then
            SRC="$feed"
            break
        fi
    done

    [ -n "$SRC" ] || continue

    echo
    echo "第三方优先: $pkg -> $SRC"

    for feed in $OFFICIAL_FEEDS; do
        package_entry_exists "$feed" "$pkg" &&
            remove_package_entry "$feed" "$pkg"
    done

done


###############################################################################
# 8. SmartDNS Rust
###############################################################################

for f in \
    package/myapp/smartdns/package/openwrt/Makefile \
    package/myapp/smartdns/Makefile
do
    [ -f "$f" ] && sed -i \
        's@include ../../lang/rust/rust-package.mk@include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk@g' \
        "$f"
done


###############################################################################
# 9. LuCI 中文
###############################################################################

if [ -f .config ]; then

    for pkg in $(
        grep '^CONFIG_PACKAGE_luci-app-.*=y' .config |
        sed 's/^CONFIG_PACKAGE_//;s/=y//' | sort -u
    ); do

        trans="luci-i18n-${pkg#luci-app-}"

        grep -q "^CONFIG_PACKAGE_${trans}-zh-cn=y" .config 2>/dev/null &&
            continue

        grep -rnq "Package.*${trans}-zh-cn" package feeds 2>/dev/null &&
            echo "CONFIG_PACKAGE_${trans}-zh-cn=y" >> .config

    done

fi


###############################################################################
# 10. conntrack
###############################################################################

sed -i \
    '/^[[:space:]]*net\.netfilter\.nf_conntrack_max[[:space:]]*=/d' \
    package/base-files/files/etc/sysctl.conf

echo 'net.netfilter.nf_conntrack_max=655550' \
    >> package/base-files/files/etc/sysctl.conf


###############################################################################
# 11. 首次启动开启 Wi-Fi
###############################################################################

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/zz-enable-wifi <<'EOF'
#!/bin/sh
. /lib/functions.sh

[ -s /etc/config/wireless ] || wifi config

if [ -s /etc/config/wireless ]; then
    config_load wireless

    enable_wifi() {
        uci -q set "wireless.$1.disabled=0"
    }

    config_foreach enable_wifi wifi-device
    config_foreach enable_wifi wifi-iface
    uci -q commit wireless
fi

exit 0
EOF

chmod +x files/etc/uci-defaults/zz-enable-wifi


###############################################################################
# 12.5 依赖检查
###############################################################################

if [ -f .config ]; then

    MISSING=0

    for pkg in $CONFIG_PACKAGES; do

        mf=""

        while IFS= read -r -d '' f; do
            if grep -q \
                "^[[:space:]]*define[[:space:]]\+Package/${pkg}[[:space:]]*$" \
                "$f" 2>/dev/null; then
                mf="$f"
                break
            fi
        done < <(
            find package feeds -maxdepth 5 \
                -type f -name Makefile -print0 2>/dev/null || true
        )

        [ -n "$mf" ] || continue

        deps="$(
            awk -v target="Package/$pkg" '
                $0 ~ "define " target {p=1;next}
                p && /^endef/ {p=0}
                p && /^[[:space:]]*DEPENDS[[:space:]]*:?=/ {
                    sub(/^[^=]*=[[:space:]]*/,""); print
                }
            ' "$mf" |
            sed -E \
                's/\+@?[A-Za-z0-9_:-]+//g;
                 s/\+//g;
                 s/@[A-Za-z0-9_:-]+//g' |
            tr ' ' '\n' |
            grep -vE '^$|^!|^%' |
            sort -u || true
        )"

        for dep in $deps; do

            case "$dep" in
                libc|librt|libpthread|kernel|kmod-*|luci-base|luci-compat)
                    continue
                    ;;
            esac

            if ! grep -Eq \
                "^CONFIG_PACKAGE_${dep}=(y|m)$" \
                .config 2>/dev/null; then

                if ! grep -rnq \
                    "^[[:space:]]*define[[:space:]]\+Package/${dep}[[:space:]]*$" \
                    package/ feeds/ 2>/dev/null; then

                    echo "❌ $pkg 缺少依赖: $dep"
                    MISSING=1

                else

                    echo "⚠️ $pkg 依赖未显式启用: $dep"

                fi

            fi

        done

    done

    [ "$MISSING" -eq 0 ] || \
        echo "⚠️ 发现缺失依赖，请检查。"

fi


###############################################################################
# 13. 最终检查
###############################################################################

echo
echo "========================================"
echo "DIY2 OK"
echo "========================================"

echo "✓ H68K DTS"
echo "✓ Hinlink DTSI"
echo "✓ PassWall"
echo "✓ 第三方 Feed 优先"
echo "✓ SmartDNS"
echo "✓ LuCI 中文"
echo "✓ conntrack"
echo "✓ Wi-Fi 自动开启"
echo "✓ 依赖检查"
