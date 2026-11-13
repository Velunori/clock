# Calendar accounts and event storage

Local calendars are editable and persistent. The panel shows a month grid with calendar-colored markers and the selected day's agenda, defaulting to today. All-day end dates are inclusive in the editor and exclusive in storage/provider APIs.

## Local data

Data is in `$XDG_DATA_HOME/velunori/clock`, falling back to `~/.local/share/velunori/clock`. `calendar.sqlite3` stores local events and cloud cache. Account files live under `accounts/`. Directories use 0700 and account/database files use 0600. Credentials are stored on disk, **not encrypted**. Do not share this directory or commit it.

Local calendars require Python 3 only. For cloud providers run:

```bash
bash ~/dev/Velunori/clock/scripts/setup-deps.sh
```

## Google

1. In Google Cloud, enable the Google Calendar API for your project and configure OAuth consent. For a testing application, add your own account as a test user.
2. Create an OAuth client of type **Desktop app** and download its original JSON file.
3. In the calendar panel open **Calendars → Google**, enter the local path to that file, and select **Connect account**.
4. Finish consent in your system browser within three minutes. No account password is collected by Velunori.
5. The primary calendar is enabled initially. Enable other calendars under Calendars as needed; shared calendars respect Google access roles.

Authorization uses Calendar event read/write access and read-only calendar discovery. A local loopback callback receives the authorization code; refresh credentials are retained privately. No shared project/client credentials are shipped with this plugin.

[Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Calendar authorization](https://developers.google.com/workspace/calendar/api/auth).

## iCloud

1. Create an app-specific password in your Apple Account settings.
2. In **Calendars → iCloud**, enter the account email and that app-specific password. Do not use your main password.
3. Select Connect account. Discovered calendars appear in the source list.

CalDAV resources must use HTTPS addresses in the icloud.com domain. Server permissions determine whether a shared calendar accepts writes.

[Apple app-specific passwords](https://support.apple.com/en-us/102654), [python-caldav documentation](https://caldav.readthedocs.io/latest/tutorial.html).

## Synchronization and conflicts

Enabled cloud calendars sync when viewing a new month and every ten minutes while the panel is open. Sync also runs after account connection and remote saves. Manual Sync is available in the agenda footer and source settings. Last successful sync and failures appear under Calendars. Failed requests retain cached events.

Writes use cached ETags and reject stale edits. Sync and reopen an event after a conflict. For recurring events, edits create an occurrence override; deletion excludes that occurrence. Other occurrences, attendees, reminders and unrelated properties are preserved. New events are single events; creating recurrence rules or editing an entire series is not supported in this version.

Disconnect removes this plugin's local account credentials, calendar records and cached events. It does not remove remote calendars/events or revoke Google consent/Apple app-specific passwords; revoke those in the provider's account settings if desired.

## Validation limits

Local storage and the QML transport are tested in temporary directories. Provider tests mock HTTP pagination/conflicts and use real iCalendar fixtures for recurrence edits/deletions. Real Google/iCloud sign-in and writes have **not** been exercised; complete those checks with a disposable test event before relying on cloud sync. No credentials were provided to the coding agent and no real cloud events were changed during implementation.
