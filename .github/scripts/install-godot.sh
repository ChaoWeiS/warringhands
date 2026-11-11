#!/usr/bin/env bash
# Installs the Godot editor (headless use) and its export templates on a CI runner.
set -euo pipefail

: "${GODOT_VERSION:?GODOT_VERSION must be set}"
base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
work="$(mktemp -d)"

wget -q -O "$work/godot.zip" "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
wget -q -O "$work/templates.tpz" "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"

unzip -q "$work/godot.zip" -d "$work"
sudo mv "$work/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot

tpl="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
mkdir -p "$tpl"
unzip -q "$work/templates.tpz" -d "$work"
mv "$work"/templates/* "$tpl/"

rm -rf "$work"
godot --version
