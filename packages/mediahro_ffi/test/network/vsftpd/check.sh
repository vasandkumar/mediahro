#!/bin/sh
# Build-time smoke test: vsftpd must start with <config> and listen on
# <port>. Otherwise the image build fails with an strace of the start-up,
# which shows the failing call (vsftpd itself often exits silently).
conf="$1"; port="$2"
/usr/sbin/vsftpd "$conf" &
pid=$!
i=0
while [ $i -lt 20 ]; do
  if nc -z 127.0.0.1 "$port"; then
    kill "$pid"; wait "$pid" 2>/dev/null
    echo "vsftpd: $conf listens on $port"
    exit 0
  fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.5; i=$((i + 1))
done
kill "$pid" 2>/dev/null
echo "vsftpd: $conf did not listen on $port; start-up trace:" >&2
strace -f -s 200 -e trace=file,process,network,write /usr/sbin/vsftpd "$conf" 2>&1 | tail -80 >&2
exit 1
