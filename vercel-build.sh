#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$ROOT_DIR/visitarian_flutter"

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_DIR="$ROOT_DIR/.vercel/flutter"
  if [ ! -d "$FLUTTER_DIR" ]; then
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
  fi
  export PATH="$PATH:$FLUTTER_DIR/bin"
fi

cd "$PROJECT_DIR"
flutter pub get
flutter build web --release --base-href / --dart-define-from-file=dart-defines.json
