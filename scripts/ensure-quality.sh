#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.luarocks/bin:$HOME/.local/bin:$PATH"

ensure_lua() {
  if command -v lua >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    local sudo_cmd=""
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd="sudo"
    fi
    echo "[ensure-quality] Installing lua5.4 via apt-get" >&2
    if ! $sudo_cmd apt-get update -y >/dev/null; then
      echo "[ensure-quality] Failed to update package lists; retry later or install Lua manually." >&2
      exit 1
    fi
    if ! $sudo_cmd apt-get install -y lua5.4 >/dev/null; then
      echo "[ensure-quality] Failed to install lua5.4; install it manually and re-run." >&2
      exit 1
    fi
  else
    echo "[ensure-quality] Missing lua5.4 and no package manager available; install Lua manually." >&2
    exit 1
  fi
}

ensure_luarocks() {
  if command -v luarocks >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    local sudo_cmd=""
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd="sudo"
    fi
    echo "[ensure-quality] Installing luarocks" >&2
    if ! $sudo_cmd apt-get update -y >/dev/null; then
      echo "[ensure-quality] Failed to update package lists; retry later or install Luarocks manually." >&2
      exit 1
    fi
    if ! $sudo_cmd apt-get install -y luarocks >/dev/null; then
      echo "[ensure-quality] Failed to install Luarocks; install it manually and re-run." >&2
      exit 1
    fi
  else
    echo "[ensure-quality] Missing luarocks and no package manager available; install Luarocks manually." >&2
    exit 1
  fi
}

ensure_luacheck() {
  if command -v luacheck >/dev/null 2>&1; then
    return
  fi

  echo "[ensure-quality] Installing luacheck via luarocks" >&2
  if ! luarocks install luacheck --local >/dev/null; then
    echo "[ensure-quality] Failed to install luacheck; check your network connection or install it manually." >&2
    exit 1
  fi
}

ensure_stylua() {
  if command -v stylua >/dev/null 2>&1; then
    return
  fi

  local version
  version=${STYLUA_VERSION:-0.20.0}
  local archive="stylua-linux-x86_64.zip"
  local url="https://github.com/JohnnyMorganz/StyLua/releases/download/v${version}/${archive}"
  local bin_dir="$HOME/.local/bin"

  mkdir -p "$bin_dir"

  echo "[ensure-quality] Installing stylua ${version} from ${url}" >&2
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      local sudo_cmd=""
      if command -v sudo >/dev/null 2>&1; then
        sudo_cmd="sudo"
      fi
      if ! $sudo_cmd apt-get update -y >/dev/null; then
        echo "[ensure-quality] Failed to update package lists; install curl manually." >&2
        exit 1
      fi
      if ! $sudo_cmd apt-get install -y curl >/dev/null; then
        echo "[ensure-quality] Failed to install curl; install it manually." >&2
        exit 1
      fi
    else
      echo "[ensure-quality] curl is required to download stylua; install it manually." >&2
      exit 1
    fi
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      local sudo_cmd=""
      if command -v sudo >/dev/null 2>&1; then
        sudo_cmd="sudo"
      fi
      if ! $sudo_cmd apt-get update -y >/dev/null; then
        echo "[ensure-quality] Failed to update package lists; install unzip manually." >&2
        exit 1
      fi
      if ! $sudo_cmd apt-get install -y unzip >/dev/null; then
        echo "[ensure-quality] Failed to install unzip; install it manually." >&2
        exit 1
      fi
    else
      echo "[ensure-quality] unzip is required to install stylua; install it manually." >&2
      exit 1
    fi
  fi

  local tmp
  tmp=$(mktemp -d)
  if ! curl -sSL "$url" -o "$tmp/${archive}"; then
    echo "[ensure-quality] Failed to download stylua ${version}; check your network connection." >&2
    exit 1
  fi
  if ! unzip -oq "$tmp/${archive}" -d "$tmp"; then
    echo "[ensure-quality] Failed to extract the stylua archive." >&2
    exit 1
  fi
  mv -f "$tmp/stylua" "$bin_dir/stylua"
  chmod +x "$bin_dir/stylua"
  rm -rf "$tmp"
}

run_stylua_check() {
  echo "[ensure-quality] Running stylua --check" >&2
  stylua --config-path "$PROJECT_ROOT/stylua.toml" --check "$PROJECT_ROOT"
}

run_stylua_fix() {
  echo "[ensure-quality] Running stylua (format)" >&2
  stylua --config-path "$PROJECT_ROOT/stylua.toml" "$PROJECT_ROOT"
}

run_luacheck() {
  echo "[ensure-quality] Running luacheck" >&2
  luacheck "$PROJECT_ROOT"
}

RUN_CHECKS=1
RUN_FIX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-only)
      RUN_CHECKS=0
      ;;
    --fix)
      RUN_FIX=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

ensure_lua
ensure_luarocks
ensure_luacheck
ensure_stylua

if [[ $RUN_CHECKS -eq 1 ]]; then
  if [[ $RUN_FIX -eq 1 ]]; then
    run_stylua_fix
  else
    run_stylua_check
  fi
  run_luacheck
fi
