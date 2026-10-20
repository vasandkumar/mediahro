#!/bin/sh
# Starts vsftpd in the foreground with <config>; on exit, prints the status
# and the config so CI logs explain a failed listener.
conf="$1"
/usr/sbin/vsftpd "$conf" 2>&1
rc=$?
echo "vsftpd: exited with status $rc using $conf" >&2
sed 's/^/vsftpd: config: /' "$conf" >&2
exit "$rc"
