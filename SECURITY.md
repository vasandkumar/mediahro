# Security policy

## Reporting a vulnerability
Email **security@mediahro.com** (PGP key published at `mediahro.com/.well-known/security.txt`). Please include the affected version, platform, and a reproduction (a crafted file is fine; please do not send personal media).

- Acknowledgement within 2 business days.
- Fix target 30 days; 7 days for actively exploited issues.
- Coordinated disclosure; reporters are credited unless they prefer otherwise; CVEs are requested via GitHub.
- Security fixes ship as hotfixes on every platform on the same day.

## Scope
Hostile media files (containers, codecs, subtitles, images, archives, playlists), hostile network shares and servers, hostile URLs, local attacks against the vault, supply chain (dependencies and build), impersonating clones.

## Controls (summary of docs/13 §6)
Parsers run in isolates with size and time limits and are fuzzed nightly; native libraries are built hardened (FORTIFY, stack protector, CFI where available, PIE); TLS uses OS stacks; credentials live only in OS secure storage; the local control API binds to loopback unless explicitly exposed with a token; dependencies are pinned by hash; release builds are signed and published with checksums and an SBOM.
