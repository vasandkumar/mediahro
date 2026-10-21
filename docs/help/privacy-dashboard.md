---
ids: [CORE-015, PRIV-001, PRIV-004]
---
# Privacy dashboard

Mediahro doesn't connect to the internet on its own unless you turn something on. The privacy dashboard lists every service the app can contact, each with its own switch. Open it from **Settings → Privacy**, or from the privacy line on the first screen.

## Off unless you turn them on

These three are off on every new install:

- **Mediahro crash reports:** anonymous reports when the app crashes, sent to Mediahro's own server.
- **Mediahro usage statistics:** anonymous counts of which features are used, sent to Mediahro's own server.
- **Check for updates:** only in versions downloaded from mediahro.com. App store versions are updated by the store, so the dashboard says so instead of showing a switch.

## Online services

Each service that can add information to your library has its own switch: subtitle downloads, film and series details, lyrics, album art and tags, song recognition, listening history, skip-intro markers and remote settings. Each row shows:

- what the service is used for,
- the internet addresses it uses,
- when Mediahro last contacted it, or "Never used".

When a switch is off, Mediahro never contacts that service.

## Your sources and servers

Network shares and media servers you add are always reachable, because you asked for them. They are listed at the end with the time each was last contacted. To stop the connections, remove the source in **Sources**.

## Your feeds and stations

When you subscribe to a podcast, add a radio station, or import a list of podcasts, Mediahro allows that one host (the site the feed or stream address is on) and lists it under **Your feeds and stations**, with the name of the podcast or station that added it. Nothing else is allowed because of it. A host two podcasts share stays until both are gone.

Tap the bin next to a host to remove it. Because the host exists only for what you added, this also unsubscribes from the podcasts and deletes the stations on it, and Mediahro asks first. Unsubscribing or deleting a station anywhere else removes its host too.

## Managed devices

On a device managed by your organisation, some switches may show a lock and "Managed by your organisation". Those are set by your organisation.
