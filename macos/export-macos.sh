#!/usr/bin/env bash
set -euo pipefail

# Export macOS du sketch Processing DIMYX sans modifier les sources du projet.
# À exécuter sur macOS avec Processing installé et processing-java disponible.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROCESSING_JAVA="${PROCESSING_JAVA:-processing-java}"
ARCH="${1:-both}"
OUT_ROOT="${ROOT}/build/macos"
SKETCH_DIR="${OUT_ROOT}/sketch"

case "$ARCH" in
  intel) VARIANTS=("intel:macos-x86_64") ;;
  arm64) VARIANTS=("arm64:macos-aarch64") ;;
  both) VARIANTS=("intel:macos-x86_64" "arm64:macos-aarch64") ;;
  *) echo "Usage: $0 [intel|arm64|both]" >&2; exit 2 ;;
esac

command -v "$PROCESSING_JAVA" >/dev/null || {
  echo "processing-java introuvable. Définissez PROCESSING_JAVA si nécessaire." >&2
  exit 1
}

rm -rf "$SKETCH_DIR"
mkdir -p "$SKETCH_DIR"
cp "$ROOT/DIMYX_3_3.pde" "$SKETCH_DIR/"

for entry in "${VARIANTS[@]}"; do
  NAME="${entry%%:*}"
  TARGET="${entry#*:}"
  EXPORT_DIR="${OUT_ROOT}/export-${NAME}"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"

  "$PROCESSING_JAVA" \
    --sketch="$SKETCH_DIR" \
    --output="$EXPORT_DIR" \
    --variant="$TARGET" \
    --export

  APP_PATH="$(find "$EXPORT_DIR" -maxdepth 2 -name '*.app' -print -quit)"
  if [[ -z "$APP_PATH" ]]; then
    echo "Aucun paquet .app n’a été produit dans $EXPORT_DIR" >&2
    exit 1
  fi

  # Le sketch charge ces fichiers par leur nom à l’exécution. Les placer dans
  # Contents/Java conserve ces chemins sans modifier le code Processing.
  JAVA_DIR="$APP_PATH/Contents/Java"
  for file in channelConfig.json scenes.json esp32Boards.json; do
    if [[ -f "$ROOT/$file" ]]; then cp "$ROOT/$file" "$JAVA_DIR/$file"; fi
  done

  echo "Application macOS exportée : $APP_PATH"
  echo "Architecture : $NAME"
done
