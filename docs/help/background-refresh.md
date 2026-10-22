---
ids: [POD-002]
---
# Refreshing in the background

Some features can refresh their content while Mediahro is closed, for example checking a podcast feed for new episodes. Nothing is scheduled unless you turn the feature on, and you can turn it off at any time.

## How it works on Android

- Mediahro asks Android to wake it up about every so often. Android decides when: the interval is a hint, never a promise, and the shortest it can be is 15 minutes.
- Each job can ask for an unmetered connection (Wi-Fi), any connection, or no connection, and can wait until the device is charging. Android runs it only when those conditions hold.
- When Android runs a job it starts Mediahro without opening a screen, does the refresh, and lets go. If the refresh fails, Android tries again later.
- The refresh uses only the network addresses on the privacy dashboard's list. No analytics or tracking is added.

## After a restart

Mediahro does not ask Android to start it when the device boots. After a restart, scheduled refreshes resume the next time you open the app. Managed devices (the enterprise build) can start the app at boot for kiosks and signage, see [Managed devices](managed-android.md).

## Other platforms

On iOS the system decides when to wake the app for a refresh. On macOS and Windows, scheduled refreshes run only while the app is open.
