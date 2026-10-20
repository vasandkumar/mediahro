#!/bin/sh
# Starts vsftpd in the foreground with <config>. Its log is a regular file
# streamed to the container's output; on exit the status and the config are
# printed so `docker compose logs <service>` explains a stopped listener.
conf="$1"
touch /var/log/vsftpd.log
tail -F /var/log/vsftpd.log &
/usr/sbin/vsftpd "$conf" 2>&1
rc=$?
echo "vsftpd: exited with status $rc using $conf" >&2
sed 's/^/vsftpd: config: /' "$conf" >&2
exit "$rc"
