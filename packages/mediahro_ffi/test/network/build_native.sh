#!/usr/bin/env bash
# Linux CI only: native libraries for the FFI network contract tests until
# lane B4's mediahro-deps archives exist. libsmb2/libnfs are built from the
# releases mediahro-deps ships (deps-pins.json, a copy of its versions.json
# entries; SHA-256 checked) with its patches and configure flags, so the
# protocol tests cover the shipped code. libarchive, libebur128, chromaprint
# and uchardet come from Ubuntu (their APIs match the bound subset).
# Test-only: nothing here is shipped.
# Usage: build_native.sh <prefix>   (then LD_LIBRARY_PATH=<prefix>/lib)
set -euo pipefail
prefix="$1"
here="$(cd "$(dirname "$0")" && pwd)"
sudo apt-get -qq update
sudo apt-get -qq install -y build-essential cmake pkg-config python3 \
  libarchive-dev libebur128-dev libchromaprint-dev libuchardet-dev > /dev/null
src="$(mktemp -d)"

# <name> -> "<url> <sha256>" from deps-pins.json ({tag}/{version} expanded).
pin() {
  python3 - "$here/deps-pins.json" "$1" <<'EOF'
import json, sys
e = next(l for l in json.load(open(sys.argv[1]))["libraries"] if l["name"] == sys.argv[2])
url = e["source"].replace("{tag}", e.get("tag", "")).replace("{version}", e["version"])
print(url, e["sha256"])
EOF
}

# fetch <name>: download, verify, extract, apply patches/<name>/*.patch in order.
fetch() {
  local url sha
  read -r url sha < <(pin "$1")
  curl -sSLf "$url" -o "$src/$1.tgz"
  echo "$sha  $src/$1.tgz" | sha256sum -c -
  mkdir -p "$src/$1" && tar -xzf "$src/$1.tgz" -C "$src/$1" --strip-components=1
  for p in "$here/patches/$1"/*.patch; do
    [ -e "$p" ] || continue
    echo "patch $1: $(basename "$p")"
    patch -p1 -d "$src/$1" < "$p"
  done
}

# build <name> <cmake flags...>: the flags mediahro-deps android/build.sh uses.
build() {
  local lib="$1"
  shift
  cmake -S "$src/$lib" -B "$src/$lib/build" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib "$@" > /dev/null
  cmake --build "$src/$lib/build" -j"$(nproc)" > /dev/null
  cmake --install "$src/$lib/build" > /dev/null
}

fetch libsmb2
fetch libnfs
build libsmb2 -DENABLE_EXAMPLES=OFF -DENABLE_LIBKRB5=OFF -DENABLE_GSSAPI=OFF
build libnfs -DENABLE_TESTS=OFF -DENABLE_DOCUMENTATION=OFF -DENABLE_UTILS=OFF \
  -DENABLE_EXAMPLES=OFF -DENABLE_MULTITHREADING=OFF
ls -l "$prefix"/lib/libsmb2.so* "$prefix"/lib/libnfs.so*
