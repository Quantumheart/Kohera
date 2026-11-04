#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$SCRIPT_DIR/io.github.quantumheart.kohera.json"
REPO_DIR="$SCRIPT_DIR/repo"
BUILD_DIR="$SCRIPT_DIR/.flatpak-builder-build"
APP_ID="io.github.quantumheart.kohera"
OUT="$SCRIPT_DIR/$APP_ID.flatpak"

cd "$PROJECT_DIR"

if ! command -v flatpak-builder &>/dev/null; then
  echo "Error: flatpak-builder not found. Install it with: sudo dnf install flatpak-builder"
  exit 1
fi

echo "Building Flutter release..."
flutter build linux --release

echo "Building Flatpak into repo..."
flatpak-builder --force-clean --repo="$REPO_DIR" \
  "$BUILD_DIR" \
  "$MANIFEST"

echo "Creating bundle..."
flatpak build-bundle \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  "$REPO_DIR" \
  "$OUT" \
  "$APP_ID"

echo "Done. Bundle at: $OUT"
echo "Install with: flatpak install $OUT"
