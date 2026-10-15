#!/usr/bin/env bash
set -eu

# apply-configs.sh
# Usage: run from the repository root or this script's directory; it will modify all
# files under hinlink-all that end with .config or .config.full.config, setting
# the requested CONFIG_ entries to the values provided by the user.

TARGET_DIR="hinlink-all"
GLOBS=("${TARGET_DIR}/*.config" "${TARGET_DIR}/*.config.full.config")

# List of key=value pairs to enforce
KV=(
  "CONFIG_PACKAGE_luci-app-openclash=y"
  "CONFIG_PACKAGE_luci-app-autoreboot=y"
  "CONFIG_PACKAGE_luci-app-smartdns=y"
  "CONFIG_PACKAGE_luci-app-mini-diskmanager=y"
  "CONFIG_PACKAGE_luci-app-natmapt=y"
  "CONFIG_PACKAGE_luci-app-partexp=y"
  "CONFIG_PACKAGE_luci-app-samba4=y"
  "CONFIG_PACKAGE_luci-app-upnp=y"
  "CONFIG_PACKAGE_luci-app-wolultra=y"
  "CONFIG_PACKAGE_luci-app-attendedsysupgrade=n"
  "CONFIG_PACKAGE_luci-app-passwall=y"
  "CONFIG_PACKAGE_kmod-tcp-bbr=y"
  "CONFIG_CCACHE=y"
  "CONFIG_DEVEL=y"
)

# Function: set key to value in file (uncomment if commented, replace if exists, append if missing)
set_kv_in_file() {
  local file="$1"
  local key="$2"
  local value="$3"

  # Escape slashes for sed
  local sed_key
  sed_key=$(printf '%s' "$key" | sed 's/[\/&]/\\&/g')
  local sed_value
  sed_value=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')

  # 1) If line like "CONFIG_X=..." exists, replace it
  if grep -qE "^${key}=" "$file"; then
    sed -i "s/^${sed_key}=.*/${sed_key}=${sed_value}/" "$file"
    return
  fi

  # 2) If the linux kernel-style commented line exists: "# CONFIG_X is not set" -> replace
  if grep -qE "^# ${key} is not set" "$file"; then
    sed -i "s/^# ${sed_key} is not set/${sed_key}=${sed_value}/" "$file"
    return
  fi

  # 3) If a commented-out assignment exists: "# ${key}=..." -> uncomment and set
  if grep -qE "^# ${key}=" "$file"; then
    sed -i "s/^# ${sed_key}=.*/${sed_key}=${sed_value}/" "$file"
    return
  fi

  # 4) Otherwise append at end
  printf "%s=%s\n" "$key" "$value" >> "$file"
}

# Find files
FILES=()
for g in "${GLOBS[@]}"; do
  for f in $g; do
    if [ -f "$f" ]; then
      FILES+=("$f")
    fi
  done
done

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No config files found in ${TARGET_DIR}. Exiting." >&2
  exit 1
fi

# Apply changes
for f in "${FILES[@]}"; do
  echo "Processing: $f"
  for kv in "${KV[@]}"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    set_kv_in_file "$f" "$key" "$value"
  done
done

echo "Done. Files changed: ${#FILES[@]}"
