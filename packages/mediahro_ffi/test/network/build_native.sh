#!/usr/bin/env bash
# Linux CI only: native libraries for the FFI network contract tests until
# lane B4's mediahro-deps archives exist. libsmb2/libnfs are built from the
# same pinned sources ffigen read (SHA-256 checked); libarchive,
# libebur128, chromaprint and uchardet come from Ubuntu (their APIs match
# the bound subset). Test-only: nothing here is shipped.
# Usage: build_native.sh <prefix>   (then LD_LIBRARY_PATH=<prefix>/lib)
set -euo pipefail
prefix="$1"
sudo apt-get -qq update
sudo apt-get -qq install -y build-essential cmake pkg-config \
  libarchive-dev libebur128-dev libchromaprint-dev libuchardet-dev > /dev/null
src="$(mktemp -d)"
fetch() {
  curl -sSLf "$2" -o "$src/$1.tgz"
  echo "$3  $src/$1.tgz" | sha256sum -c -
  mkdir -p "$src/$1" && tar -xzf "$src/$1.tgz" -C "$src/$1" --strip-components=1
}
fetch smb2 https://github.com/sahlberg/libsmb2/archive/refs/tags/libsmb2-6.2.tar.gz \
  8e1f9efc6b2e0f6546f0fe121ac0ddf4fc2f0908ae5a6bd1f185be7c9e0bcbb3
fetch nfs https://github.com/sahlberg/libnfs/archive/refs/tags/libnfs-6.0.2.tar.gz \
  4e5459cc3e0242447879004e9ad28286d4d27daa42cbdcde423248fad911e747
# Patches carried until upstream has them (same files as mediahro-deps).
here="$(cd "$(dirname "$0")" && pwd)"
patch -p1 -d "$src/smb2" < "$here/patches/libsmb2-6.2-guest-session.patch"
for lib in smb2 nfs; do
  cmake -S "$src/$lib" -B "$src/$lib/build" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_UTILS=OFF \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib > /dev/null
  cmake --build "$src/$lib/build" -j"$(nproc)" > /dev/null
  cmake --install "$src/$lib/build" > /dev/null
done
ls -l "$prefix"/lib/libsmb2.so* "$prefix"/lib/libnfs.so*
