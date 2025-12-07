#!/usr/bin/env bash
set -euo pipefail

EXTRAS_DIR="/extras"
ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

log() {
    echo "[kait] $*"
}

# Install extra tools from config if present
install_extras() {
    if [[ ! -f "/config/extras.txt" ]]; then
        return 0
    fi

    log "Installing extra tools from /config/extras.txt"

    # Format: name|url|version|extract(optional)
    # Example: helm|https://get.helm.sh/helm-v{version}-linux-{arch}.tar.gz|3.16.3|linux-{arch}/helm
    while IFS='|' read -r name url version extract; do
        [[ -z "$name" || "$name" == \#* ]] && continue

        url="${url//\{version\}/$version}"
        url="${url//\{arch\}/$ARCH}"

        log "Installing $name v$version"

        if [[ -n "$extract" ]]; then
            extract="${extract//\{arch\}/$ARCH}"
            curl -fsSL "$url" | tar xzf - -C "$EXTRAS_DIR" --strip-components=1 "$extract"
        elif [[ "$url" == *.tar.gz || "$url" == *.tgz ]]; then
            curl -fsSL "$url" | tar xzf - -C "$EXTRAS_DIR"
        else
            curl -fsSL "$url" -o "$EXTRAS_DIR/$name"
        fi

        chmod +x "$EXTRAS_DIR/$name"
        log "Installed $name"
    done < /config/extras.txt
}

# Install extras if config exists and directory is writable
if [[ -w "$EXTRAS_DIR" ]]; then
    install_extras
fi

# Determine hooks file
HOOKS_FILE="/config/hooks.yaml"
if [[ -f /config/hooks.json ]]; then
    HOOKS_FILE="/config/hooks.json"
fi

# Start webhook server
log "Starting webhook server on port ${WEBHOOK__PORT}"
exec \
    /app/bin/webhook \
    -port "${WEBHOOK__PORT}" \
    -urlprefix "${WEBHOOK__URLPREFIX}" \
    -hooks "${HOOKS_FILE}" \
    -template \
    -verbose \
    "$@"
