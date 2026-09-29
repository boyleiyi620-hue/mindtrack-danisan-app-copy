#!/usr/bin/env bash
set -euo pipefail

# MindTrack web çıktısını hazırlar (psikolog + danışan).
#
# Supabase bağlantısı --dart-define ile verilir. Değerleri ortam değişkeni
# olarak da verebilirsiniz:
#   SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... ./scripts/build_web.sh
#
# Not: `service_role` / secret anahtarı ASLA buraya verilmez.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
WEB_DIR="$ROOT_DIR/web"
BUILD_DIR="$ROOT_DIR/build"

: "${SUPABASE_URL:?SUPABASE_URL tanımlı olmalı}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY tanımlı olmalı}"

DEFINES=(
  "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}"
)

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"

original_index="$(mktemp)"
original_manifest="$(mktemp)"
cp "$WEB_DIR/index.html" "$original_index"
cp "$WEB_DIR/manifest.json" "$original_manifest"
restore() {
  cp "$WEB_DIR/index.html" "$original_index"
  cp "$WEB_DIR/manifest.json" "$original_manifest"
  rm -f "$original_index" "$original_manifest"
}
trap restore EXIT

build_target() {
  local target="$1"
  local template="$2"
  local manifest="$3"
  local output="$4"

  cp "$WEB_DIR/$template" "$WEB_DIR/index.html"
  cp "$WEB_DIR/$manifest" "$WEB_DIR/manifest.json"
  rm -rf "$BUILD_DIR/web" "$BUILD_DIR/$output"
  "$FLUTTER_BIN" build web --release --no-wasm-dry-run -t "lib/$target" "${DEFINES[@]}"
  cp -a "$BUILD_DIR/web" "$BUILD_DIR/$output"
  # Önceki Flutter sürümünün service worker cache'ini kullanan tarayıcıları temizle.
  cp "$WEB_DIR/disable_flutter_service_worker.js" \
    "$BUILD_DIR/$output/flutter_service_worker.js"
}

build_target "main_psych.dart" "index_psychologist.html" "manifest_psychologist.json" "psych"
build_target "main.dart" "index_client.html" "manifest_client.json" "client"

echo "Web çıktıları hazırlandı:"
echo "  Psikolog: $BUILD_DIR/psych"
echo "  Danışan:  $BUILD_DIR/client"
