#!/bin/zsh
# One-line install: curl -fsSL https://raw.githubusercontent.com/dalex160/Viji/main/install.sh | zsh
# Builds from source on your Mac, so there is no Gatekeeper warning.
set -euo pipefail

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Viji needs Apple's Command Line Tools to build. Installing them now…"
    xcode-select --install || true
    echo "Run this installer again once the Command Line Tools are installed."
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Viji…"
curl -fsSL https://github.com/dalex160/Viji/archive/refs/heads/main.tar.gz | tar -xz -C "$tmp"
echo "Building…"
zsh "$tmp/Viji-main/build.sh"
echo
echo "Done. Viji is in ~/Applications and in your menu bar (eye icon)."
echo "Grant it Accessibility access when macOS asks, then Cmd-drag the eye next to the battery icon."
