#!/bin/sh
# Starts vsftpd in the foreground with <config>. Its log is a regular file
# streamed to the container's output; on exit the status and the config are
# printed so `docker compose logs <service>` explains a stopped listener.
conf="$1"
touch /var/log/vsftpd.log
# The health check connects from inside the container (127.0.0.1) every few
# seconds; leave it out so the log tail shows the test sessions.
tail -F /var/log/vsftpd.log | awk '!/Client "127\.0\.0\.1"/ { print; fflush() }' &
/usr/sbin/vsftpd "$conf" 2>&1
rc=$?
echo "vsftpd: exited with status $rc using $conf" >&2
sed 's/^/vsftpd: config: /' "$conf" >&2
exit "$rc"
