# Mediahro privacy policy

_Effective: on the 1.0 release date. Draft prepared from docs/07 §6.1; reviewed by counsel before publication._

**Short version:** Mediahro has no accounts and no telemetry by default. Nothing leaves your device unless you turn on a feature whose purpose is online.

## What stays on your device
Your library index, playback positions, playlists, ratings, tags, settings, thumbnails and the vault. We operate no cloud storage for your media.

## Optional transmissions (all off by default)
| Feature | What is sent | Where |
|---|---|---|
| Crash reports | Device model, OS version, app version, stack trace. Paths, file names and IP addresses are scrubbed on device and on the server. You can view each report before it is sent. | Self-hosted Sentry/GlitchTip (EU) |
| Usage analytics | Anonymous events from the published event list; no identifiers; country derived from IP and the IP discarded | Self-hosted Aptabase (EU) |
| Configuration updates | A request for a static, signed JSON file | `api.mediahro.com` |

## Third-party services you may enable
Each sits behind its own toggle in the privacy dashboard and is governed by that service's policy: LRCLIB, MusicBrainz / Cover Art Archive, ListenBrainz, IntroDB. Services that need a key the publisher would have to hold (subtitle databases, film and series databases, Last.fm and Libre.fm, Trakt, AcoustID, cloud drives) are not part of Mediahro (ADR-048). Servers you add yourself (Jellyfin, Emby, Plex, Subsonic-compatible, Immich, Nextcloud, Audiobookshelf, network shares) receive only what is needed to browse and play from them.

## Retention
Crash reports 90 days; analytics aggregates 12 months.

## Your choices
Turn any toggle off at any time in Settings → Privacy. To ask for deletion of crash data, email `privacy@mediahro.com`.

We do not sell or share personal information. Mediahro is a general-audience app (13+) and is not directed at children. EU representative and DSA trader information: to be added before EU availability.
