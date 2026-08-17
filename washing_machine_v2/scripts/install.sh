#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/install.log"
CACHE_DIR="${PROJECT_ROOT}/.cache"
PUB_CACHE="${PROJECT_ROOT}/.pub-cache"

mkdir -p "${CACHE_DIR}" "${PUB_CACHE}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "==> Project root: ${PROJECT_ROOT}"
echo "==> User: $(whoami)"

# Dépendances système minimales (Godot est lancé sur l'hôte).
sudo apt-get update
sudo apt-get install -y \
  curl \
  ca-certificates \
  unzip \
  git \
  jq \
  gpg \
  wget \
  build-essential \
  pkg-config

# Installer Dart uniquement s'il n'est pas déjà disponible.
if ! command -v dart >/dev/null 2>&1; then
  echo "==> Installing Dart SDK"

  echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
    | sudo tee /etc/apt/sources.list.d/dart_stable.list >/dev/null

  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
    | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg

  sudo apt-get update
  sudo apt-get install -y dart
else
  echo "==> Dart SDK already available"
fi

echo 'export PATH="/usr/lib/dart/bin:$PATH"' \
  | sudo tee /etc/profile.d/dart.sh >/dev/null

echo "==> Dart version"
dart --version

export PUB_CACHE
echo "==> PUB_CACHE: ${PUB_CACHE}"

# Charger .env si présent. GODOT_DART_ARTIFACT_URL peut y être défini.
if [ -f "${PROJECT_ROOT}/.env" ]; then
  set -a
  . "${PROJECT_ROOT}/.env"
  set +a
fi

PUB_CACHE="${PROJECT_ROOT}/.pub-cache"
export PUB_CACHE
: "${GODOT_DART_ARTIFACT_URL:=}"

ZIP_OUT="${CACHE_DIR}/godot-extension.zip"
GODOT_DART_STATUS="existing"

required_godot_dart_files_present() {
  [ -f "${PROJECT_ROOT}/libgodot_dart.so" ] &&
    [ -f "${PROJECT_ROOT}/libdart_dll.so" ] &&
    [ -f "${PROJECT_ROOT}/godot_dart.gdextension" ]
}

download_godot_dart_from_url() {
  echo "==> Downloading godot_dart artifact from explicit URL"
  curl -fL -o "${ZIP_OUT}" "${GODOT_DART_ARTIFACT_URL}"

  echo "==> Extracting godot_dart artifact without overwriting existing files"
  unzip -n "${ZIP_OUT}" -d "${PROJECT_ROOT}"
}

ensure_gdextension_file() {
  if [ -f "${PROJECT_ROOT}/godot_dart.gdextension" ]; then
    echo "==> Existing godot_dart.gdextension found, keeping current file"
    return
  fi

  echo "==> Creating godot_dart.gdextension"
  cat >"${PROJECT_ROOT}/godot_dart.gdextension" <<'EOF'
[configuration]
entry_symbol = "godot_dart_init"
compatibility_minimum = 4.2

[icons]
DartScript = "res://godot_dart/logo_dart.svg"
DartHotReload = "res://godot_dart/hot_reload.svg"

[libraries]
linux.debug.x86_64 = "res://libgodot_dart.so"
linux.release.x86_64 = "res://libgodot_dart.so"
windows.debug.x86_64 = "res://godot_dart.dll"
windows.release.x86_64 = "res://godot_dart.dll"
macos.debug = "res://libgodot_dart.dylib"
macos.release = "res://libgodot_dart.dylib"
EOF
}

if required_godot_dart_files_present; then
  echo "==> Existing godot_dart binaries found, keeping current version"
else
  GODOT_DART_STATUS="downloaded"

  if [ -z "${GODOT_DART_ARTIFACT_URL}" ]; then
    echo "ERROR: godot_dart binaries are missing and GODOT_DART_ARTIFACT_URL is not set."
    echo "       Existing binaries are kept when present; downloads require an explicit URL."
    exit 1
  fi

  download_godot_dart_from_url
fi

ensure_gdextension_file

if ! required_godot_dart_files_present; then
  echo "ERROR: godot_dart setup is incomplete after install."
  echo "       Required: libgodot_dart.so, libdart_dll.so, godot_dart.gdextension"
  exit 1
fi

if [ ! -d "${PROJECT_ROOT}/src" ]; then
  echo "ERROR: ${PROJECT_ROOT}/src not found."
  exit 1
fi

echo "==> dart pub get"
(
  cd "${PROJECT_ROOT}/src"
  dart pub get
)
DART_PUB_GET_STATUS="OK"

echo "==> build_runner"
(
  cd "${PROJECT_ROOT}/src"
  dart run build_runner build --delete-conflicting-outputs
)
BUILD_RUNNER_STATUS="OK"

echo "==> Install summary"
echo "Project root: ${PROJECT_ROOT}"
echo "Dart version: $(dart --version 2>&1)"
echo "PUB_CACHE: ${PUB_CACHE}"
echo "godot_dart binaries: ${GODOT_DART_STATUS}"
echo "dart pub get: ${DART_PUB_GET_STATUS}"
echo "build_runner: ${BUILD_RUNNER_STATUS}"
echo "✅ Done."
