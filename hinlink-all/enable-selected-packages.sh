#!/bin/sh
# enable-selected-packages.sh
# Run this from the repository root. It will ensure the selected CONFIG_ options
# are set to "y" in every file under hinlink-all whose filename contains ".config".
# The script removes any previous settings for the same symbols (both "=y", "=n" and
# commented "# CONFIG_... is not set") and appends a block with the desired settings.

set -euo pipefail

FILES_DIR="hinlink-all"

# The desired config block (last occurrence wins)
CONFIG_BLOCK='\
# --- enable-selected-packages (added by script) ---\
CONFIG_PACKAGE_luci-app-openclash=y\
CONFIG_PACKAGE_luci-app-autoreboot=y\
CONFIG_PACKAGE_luci-app-smartdns=y\
CONFIG_PACKAGE_luci-app-mini-diskmanager=y\
CONFIG_PACKAGE_luci-app-natmapt=y\
CONFIG_PACKAGE_luci-app-partexp=y\
CONFIG_PACKAGE_luci-app-samba4=y\
CONFIG_PACKAGE_luci-app-upnp=y\
CONFIG_PACKAGE_luci-app-wolultra=y\
CONFIG_PACKAGE_luci-app-attendedsysupgrade=y\
CONFIG_PACKAGE_luci-app-passwall=y\
CONFIG_PACKAGE_kmod-tcp-bbr=y\
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview=y\
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y\
CONFIG_CCACHE=y\
CONFIG_DEVEL=y\
# --- end ---\
'

# Keys to remove prior to appending (one per line, used by sed)
KEYS="\
CONFIG_PACKAGE_luci-app-openclash\
CONFIG_PACKAGE_luci-app-autoreboot\
CONFIG_PACKAGE_luci-app-smartdns\
CONFIG_PACKAGE_luci-app-mini-diskmanager\
CONFIG_PACKAGE_luci-app-natmapt\
CONFIG_PACKAGE_luci-app-partexp\
CONFIG_PACKAGE_luci-app-samba4\
CONFIG_PACKAGE_luci-app-upnp\
CONFIG_PACKAGE_luci-app-wolultra\
CONFIG_PACKAGE_luci-app-attendedsysupgrade\
CONFIG_PACKAGE_luci-app-passwall\
CONFIG_PACKAGE_kmod-tcp-bbr\
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview\
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray\
CONFIG_CCACHE\
CONFIG_DEVEL\
"

if [ ! -d "$FILES_DIR" ]; then
  echo "Directory $FILES_DIR not found; aborting" >&2
  exit 1
fi

# Build sed expression to delete any line that defines or comments-out the keys
SED_EXPR=""
for k in $KEYS; do
  # delete lines like: CONFIG_KEY=..., # CONFIG_KEY is not set, or comments containing the exact key
  SED_EXPR="$SED_EXPR; /(^CONFIG_${k#CONFIG_}=|^# CONFIG_${k#CONFIG_} is not set|^# ${k}=|^${k}=|^# ${k} is not set)/d"
done
# Remove leading semicolon
SED_EXPR="$(echo "$SED_EXPR" | sed 's/^;//')"

# Iterate matching files
changed=0
for f in "$FILES_DIR"/*config*; do
  [ -e "$f" ] || continue
  echo "Processing $f"
  # Use a temporary file
  tmp=$(mktemp)
  # Apply sed to remove old keys, preserve file if no change
  sed -E "$SED_EXPR" "$f" > "$tmp" || { rm -f "$tmp"; echo "sed failed on $f" >&2; exit 1; }
  # Append the block
  printf "%b\n" "$CONFIG_BLOCK" >> "$tmp"
  # Only overwrite if new content differs
  if ! cmp -s "$f" "$tmp"; then
    mv "$tmp" "$f"
    echo "Updated $f"
    changed=1
  else
    rm -f "$tmp"
    echo "No changes for $f"
  fi
done

if [ "$changed" -eq 1 ]; then
  echo "Remember to commit the changes: git add $FILES_DIR/*config* && git commit -m 'Enable selected packages in hinlink-all .config files'"
else
  echo "No files changed"
fi
