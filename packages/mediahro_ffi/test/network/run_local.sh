#!/usr/bin/env bash
# Runs the network-env CI job locally on Linux or WSL2 Ubuntu 24.04, step for
# step: native libraries, seed, kernel NFS, `docker compose up --wait`, then
# both suites (each runs even if the other fails), server logs on failure.
#
#   sudo packages/mediahro_ffi/test/network/run_local.sh --setup   # once
#   sudo packages/mediahro_ffi/test/network/run_local.sh [--keep] [--ffi|--app]
#
# --setup  installs what the CI runner has: docker.io, docker-compose-v2,
#          nfs-kernel-server, clang (Flutter's native-asset hooks), rsync and
#          the build packages, plus a Linux Flutter matching .fvmrc
#          (FLUTTER_ROOT, default /opt/mediahro/flutter). Ubuntu 24.04.
# --keep   leave the servers and the NFS export up afterwards (re-runs are
#          then fast; `--down` tears them down).
# --ffi    only the FFI contract suite (NET-001 SMB, NET-002 NFS, FILE-004).
# --app    only the app source suite (NET-003/004/005).
#
# Needs root (docker, nfsd). Ports already taken on the machine (a WSL
# distro's own smbd on 445, sshd on 2222) move to free ones.
#
# The checkout (minus what .gitignore excludes) is copied to
# $MEDIAHRO_NETENV_DIR (default /var/tmp/mediahro-netenv): pub writes Linux
# paths into .dart_tool, which must not land in a Windows checkout, and nfsd
# cannot export a /mnt/<drive> path.
set -euo pipefail

keep=0
down=0
setup=0
suites="ffi app"
for a in "$@"; do
  case "$a" in
    --keep) keep=1 ;;
    --down) down=1 ;;
    --setup) setup=1 ;;
    --ffi) suites="ffi" ;;
    --app) suites="app" ;;
    -h | --help)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown option: $a" >&2
      exit 2
      ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "run_local.sh: needs root (docker, nfsd); use sudo" >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
work="${MEDIAHRO_NETENV_DIR:-/var/tmp/mediahro-netenv}"
src="$work/src"
net="$src/packages/mediahro_ffi/test/network"
logs="$work/logs"
export_file=/etc/exports.d/mediahro-netenv.exports

compose() { (cd "$net" && docker compose "$@"); }

teardown() {
  if [ -d "$net" ]; then compose down -v --remove-orphans > /dev/null 2>&1 || true; fi
  rm -f "$export_file"
  exportfs -ra 2> /dev/null || true
}

if [ "$setup" -eq 1 ]; then
  export DEBIAN_FRONTEND=noninteractive
  dpkg --configure -a
  apt-get -qq update
  # Docker Desktop's WSL integration can leave /usr/bin/docker as a
  # dangling symlink, which blocks the docker.io package.
  if [ -L /usr/bin/docker ] && [ ! -e /usr/bin/docker ]; then rm /usr/bin/docker; fi
  apt-get -qq install -y docker.io docker-compose-v2 nfs-kernel-server clang \
    build-essential cmake pkg-config python3 rsync curl git unzip xz-utils \
    libarchive-dev libebur128-dev libchromaprint-dev libuchardet-dev > /dev/null
  systemctl enable --now docker nfs-kernel-server > /dev/null
  flutter_version="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$repo/.fvmrc")"
  FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/mediahro/flutter}"
  if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
    mkdir -p "$(dirname "$FLUTTER_ROOT")"
    curl -sSLf "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz" |
      tar -xJ -C "$(dirname "$FLUTTER_ROOT")"
  fi
  docker version --format 'docker {{.Server.Version}}'
  docker compose version
  echo "network-env: setup done"
  exit 0
fi

if [ "$down" -eq 1 ]; then
  teardown
  echo "network-env: down"
  exit 0
fi

step() { printf '\n== %s\n' "$*"; }

step "copy $repo -> $src"
mkdir -p "$src" "$logs"
# .gitignore rules decide what is copied (git itself may not read a Windows
# worktree from WSL). --delete keeps excluded build state in $src (pub and
# deps caches, seeded data) and drops files removed from the checkout.
rsync -a --delete --exclude=/.git --filter=':- .gitignore' "$repo/" "$src/"

flutter_version="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$src/.fvmrc")"
export FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/mediahro/flutter}"
if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  step "Flutter $flutter_version -> $FLUTTER_ROOT"
  mkdir -p "$(dirname "$FLUTTER_ROOT")"
  curl -sSLf "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz" |
    tar -xJ -C "$(dirname "$FLUTTER_ROOT")"
fi
git config --global --add safe.directory "$FLUTTER_ROOT" 2> /dev/null || true
export PATH="$FLUTTER_ROOT/bin:$PATH"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
have="$(flutter --version 2> /dev/null | sed -n 's/^Flutter \([^ ]*\).*/\1/p')"
if [ "$have" != "$flutter_version" ]; then
  echo "Flutter $have at $FLUTTER_ROOT; .fvmrc wants $flutter_version" >&2
  exit 2
fi

step "tools/bootstrap"
(cd "$src" && tools/bootstrap > "$logs/bootstrap.log" 2>&1) ||
  { tail -30 "$logs/bootstrap.log"; exit 1; }

# Native libraries: rebuilt only when the pins, patches or script change.
native="$work/native"
stamp="$(cat "$net/deps-pins.json" "$net/build_native.sh" "$net"/patches/*/*.patch | sha256sum | cut -d' ' -f1)"
if [ "$(cat "$native/.stamp" 2> /dev/null)" != "$stamp" ]; then
  step "native libraries (build_native.sh)"
  rm -rf "$native"
  "$net/build_native.sh" "$native" > "$logs/native.log" 2>&1 ||
    { tail -30 "$logs/native.log"; exit 1; }
  echo "$stamp" > "$native/.stamp"
else
  step "native libraries: up to date"
fi

step "seed the shares"
(cd "$src/packages/mediahro_ffi" && dart run test/network/seed.dart test/network/data > "$logs/seed.log" 2>&1) ||
  { tail -30 "$logs/seed.log"; exit 1; }

step "NFS v3/v4 (kernel nfsd)"
env_file="$work/nfs.env"
: > "$env_file"
GITHUB_ENV="$env_file" "$net/nfs_host.sh" "$net/data" > "$logs/nfs.log" 2>&1 ||
  { tail -30 "$logs/nfs.log"; exit 1; }
nfs_export="$(sed -n 's/^NFS_EXPORT=//p' "$env_file")"
tail -2 "$logs/nfs.log"

# Defaults unless the machine already uses them (WSL distros often run
# their own smbd on 445 or sshd on 2222); the suites read SMB_PORT.
port_free() { ! ss -Hltn "sport = :$1" | grep -q .; }
pick_port() {
  local p
  for p in "$@"; do
    if port_free "$p"; then
      echo "$p"
      return
    fi
  done
  echo "run_local.sh: ports $* are all in use" >&2
  exit 1
}
compose down --remove-orphans > /dev/null 2>&1 || true
export SMB_PORT="${SMB_PORT:-$(pick_port 445 1445 10445)}"
export SFTP_PORT="${SFTP_PORT:-$(pick_port 2222 12222)}"
for p in 21 990 8080 8081; do
  port_free "$p" || { echo "run_local.sh: port $p is in use" >&2; exit 1; }
done
echo "SMB on $SMB_PORT, SFTP on $SFTP_PORT"

step "docker compose up --build --wait"
if ! compose up -d --build --wait --wait-timeout 600 > "$logs/compose-up.log" 2>&1; then
  tail -40 "$logs/compose-up.log"
  compose ps -a
  compose logs --no-color --tail 200 > "$logs/servers.log" 2>&1 || true
  echo "server logs: $logs/servers.log" >&2
  [ "$keep" -eq 1 ] || teardown
  exit 1
fi

failed=()
for s in $suites; do
  case "$s" in
    ffi)
      step "FFI contract tests (NET-001 SMB, NET-002 NFS, FILE-004)"
      (cd "$src/packages/mediahro_ffi" &&
        MEDIAHRO_NET_ENV=1 NFS_EXPORT="$nfs_export" LD_LIBRARY_PATH="$native/lib" \
          dart test test/network test/native_contract_test.dart 2>&1 | tee "$logs/ffi.log") ||
        failed+=(ffi)
      ;;
    app)
      step "App source tests (NET-003 WebDAV + Nextcloud, NET-004 FTP/FTPS, NET-005 DLNA)"
      (cd "$src/app" &&
        MEDIAHRO_NET_ENV=1 flutter test test/core/sources/network_env_test.dart 2>&1 | tee "$logs/app.log") ||
        failed+=(app)
      ;;
  esac
done

if [ "${#failed[@]}" -gt 0 ]; then
  compose logs --no-color --tail 300 > "$logs/servers.log" 2>&1 || true
  echo
  echo "network-env: FAILED (${failed[*]}); logs in $logs (servers.log, ffi.log, app.log)"
fi
if [ "$keep" -eq 1 ]; then
  echo "network-env: servers left up (--down to stop)"
else
  teardown
fi
[ "${#failed[@]}" -eq 0 ] && echo "network-env: all suites passed"
[ "${#failed[@]}" -eq 0 ]
