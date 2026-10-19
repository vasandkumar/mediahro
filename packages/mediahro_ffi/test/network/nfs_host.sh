#!/usr/bin/env bash
# NFS v3/v4 server on the Linux CI runner (kernel nfsd). Exports
# <data>/media as fsid=0, so NFSv4 sees it at "/" and NFSv3 at its path.
# Usage: sudo nfs_host.sh <data dir>
set -euo pipefail
data="$(cd "$1" && pwd)/media"
apt-get -qq update && apt-get -qq install -y nfs-kernel-server > /dev/null
chmod -R a+rwX "$data"
# libnfs connects from unprivileged ports, hence `insecure`.
echo "$data *(rw,sync,no_subtree_check,insecure,no_root_squash,fsid=0)" > /etc/exports
exportfs -ra
systemctl restart nfs-kernel-server
showmount -e localhost
echo "NFS_EXPORT=$data" >> "${GITHUB_ENV:-/dev/null}"
