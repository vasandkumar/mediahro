#!/usr/bin/env bash
# NFS v3/v4 server on the Linux CI runner or WSL (kernel nfsd). Exports
# <data>/media as fsid=0, so NFSv4 sees it at "/" and NFSv3 at its path.
# Usage: sudo nfs_host.sh <data dir>
set -euo pipefail
data="$(cd "$1" && pwd)/media"
if ! command -v exportfs > /dev/null; then
  apt-get -qq update && apt-get -qq install -y nfs-kernel-server > /dev/null
fi
chmod -R a+rwX "$data"
# libnfs connects from unprivileged ports, hence `insecure`.
# A drop-in, so a machine's own /etc/exports is left alone (run_local.sh).
mkdir -p /etc/exports.d
echo "$data *(rw,sync,no_subtree_check,insecure,no_root_squash,fsid=0)"   > /etc/exports.d/mediahro-netenv.exports
exportfs -ra
systemctl restart nfs-kernel-server
showmount -e localhost
echo "NFS_EXPORT=$data" >> "${GITHUB_ENV:-/dev/null}"
