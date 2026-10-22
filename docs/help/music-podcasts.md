---
ids: [POD-002]
---
# Podcasts

Mediahro plays podcasts from the feeds you give it. There is no directory to browse and nothing is recommended: you bring the addresses.

## Subscribing

- **Podcasts** tab → **Add podcast**, then paste the feed address (the RSS or Atom link a podcast's website gives you). Addresses starting `feed:`, `itpc:` or `pcast:` work too.
- **⋮ → Import OPML** adds every podcast listed in an OPML file exported from another podcast app. Podcasts you already follow are skipped, and Mediahro tells you what could not be added.
- **⋮ → Export OPML** saves your subscriptions as an OPML file to move to another app.

Mediahro only contacts the feed address you gave it, the hosts that feed points to for episodes and artwork, and nothing else. Nothing is sent about you. The feed's own host is listed in **Settings → Privacy → Your feeds and stations** for as long as you are subscribed; removing it there unsubscribes too.

## Episodes

Open a podcast to see its episodes, newest first. Each shows its date and length, a bar for how far you listened, and whether it is played or downloaded.

- Tap an episode to play it. It resumes where you left off; a played episode starts from the beginning.
- An episode counts as played when it ends or has less than 20 seconds left. When it ends, the next unplayed episode starts, unless a sleep timer set to stop at the end of the track is running.
- The **⋮** menu of an episode: play, **Download** (or **Remove download**), mark played or unplayed, and show notes.
- **Check for new episodes** (refresh button, pull down in the list, or **⋮** in the tab). Mediahro also checks when it opens and about every hour while it is open. A feed that hasn't changed costs one small request.

## Listening

The player has back 10 seconds and forward 30 seconds, speed (0.5× to 3×) and skip silence, a sleep timer, show notes, and **Mark as played**. Each show remembers its own speed and skip-silence choice; a show you haven't set one for starts at the speed you used last. The lock screen's next and previous buttons also skip forward 30 and back 10 seconds while an episode plays.

## Each show's settings (the tune button)

- **Oldest first**: for serials. The list and the "next episode" go the other way.
- **Keep newest episodes downloaded**: Mediahro downloads the newest 1, 3 or 5 unplayed episodes after a check, on an unmetered connection only.
- **Delete downloads once played.**
- **Mark all as played / unplayed**, and **Unsubscribe**, which also deletes the show's downloads.

Downloads use the same download manager as network files: they resume after an interruption and count against its size limit.

## Good to know

- Mediahro keeps the 400 newest episodes of a feed, plus any you've played, started or downloaded.
- On Android, Mediahro also checks for new episodes while the app is closed: once you follow a podcast it asks Android to check about every 3 hours, and only on an unmetered connection (Wi-Fi). Android decides the exact time, so a check can be later than that, and it stops when you no longer follow any podcast. Downloads you asked for ("Keep newest episodes downloaded") follow a check the same way. See [Refreshing in the background](background-refresh.md). On iOS the system decides when to wake the app; on macOS and Windows Mediahro checks only while it is open.
