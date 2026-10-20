#!/bin/sh
# MiniDLNA (host network) serves only the subnets of the interfaces it
# enabled, so a probe from 127.0.0.1 is refused. Probe the host's primary
# IPv4 address instead: the source address of the default route, else the
# first global address.
addr=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
if [ -z "$addr" ]; then
  addr=$(ip -4 addr show scope global 2>/dev/null | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -1)
fi
[ -n "$addr" ] || exit 1
exec wget -q -O /dev/null "http://$addr:8200/rootDesc.xml"
