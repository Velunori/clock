# Calendar accounts and event storage

Local calendars are editable and persistent. The panel shows a month grid with calendar-colored markers and the selected day's agenda, defaulting to today. All-day end dates are inclusive in the editor and exclusive in storage/provider APIs.

## Local data

Data is in `$XDG_DATA_HOME/velunori/clock`, falling back to `~/.local/share/velunori/clock`. `calendar.sqlite3` stores local events and cloud cache. Account files live under `accounts/`. Directories use 0700 and account/database files use 0600. Credentials are stored on disk, **not encrypted**. Do not share this directory or commit it.

Local calendars require Python 3 only. For cloud providers run:

```bash
bash ~/dev/Velunori/clock/scripts/setup-deps.sh
```

## Google

1. Open **Calendars → Add account → Google → Connect Google**.
2. Sign in to your Google account in the browser and approve both calendar permissions within three minutes.
3. Return to Velunori. The primary calendar is enabled initially; enable other calendars under Calendars as needed.

Personal Gmail accounts are supported. Users do not need Google Cloud projects, OAuth clients or JSON files. Authorization uses Calendar event read/write access and read-only calendar discovery, with a local loopback callback, PKCE and privately retained refresh credentials. Passwords are entered only on Google's website.

**Current release dependency:** Google browser sign-in is implemented but unavailable in builds without a Velunori-owned Desktop OAuth registration. Those builds explain this and disable Connect Google. No registration is currently supplied in this checkout; the installed desktop has a registration configured and Google sign-in plus initial sync have been exercised.

### Maintainer configuration (once for Velunori)

Create a Velunori-owned Google Cloud project, enable Calendar API, configure Google Auth Platform with External audience, and register a Desktop app OAuth client. Testing requires an explicitly listed test account. Public release requires the appropriate Google brand and sensitive-scope verification, including a homepage, privacy policy and justification of these scopes:

- `https://www.googleapis.com/auth/calendar.events`
- `https://www.googleapis.com/auth/calendar.calendarlist.readonly`

Keep the downloaded registration outside Git. After committing the clock implementation and updating the bundle's component pin, inject it at release build time:

```bash
python3 velunori/installer/build.py --site-dir velunori.github.io --google-oauth-client /path/to/velunori-desktop-client.json
```

The builder validates the pinned clock's configuration loader and embeds only the Desktop client configuration, covered by the installer's integrity hashes. Never supply user authorization/token JSON. For local development, put the registration in `clock/google-oauth.json` (Git-ignored). The deployed copied plugin needs its own `google-oauth.json`. This application registration identifies Velunori and is separate from each user's private account credentials. The legacy backend `clientFile` request remains compatible with earlier integrations; the UI does not require it.

[Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Calendar authorization](https://developers.google.com/workspace/calendar/api/auth).

## iCloud

1. Create an app-specific password in your Apple Account settings.
2. In **Calendars → Add account → iCloud**, follow the inline steps and **Open Apple Account** link, then enter the account email and that app-specific password. Do not use your main password.
3. Select Connect account. Discovered calendars appear in the source list.

The iCloud client uses each discovered calendar’s own HTTPS server address, including Apple’s numbered CalDAV hosts. Birthdays generated from iCloud Contacts are not imported: this integration accesses CalDAV calendars, not CardDAV contacts. Ordinary birthday events saved in a CalDAV calendar are handled like other events.

CalDAV resources must use HTTPS addresses in the icloud.com domain. Server permissions determine whether a shared calendar accepts writes.

[Apple app-specific passwords](https://support.apple.com/en-us/102654), [python-caldav documentation](https://caldav.readthedocs.io/latest/tutorial.html).

## Synchronization and conflicts

Enabled cloud calendars sync when viewing a new month and every ten minutes while the panel is open. Sync also runs after account connection and remote saves. Manual Sync is available in the agenda footer and source settings. Last successful sync and failures appear under Calendars. Failed requests retain cached events.

Timed events may have identical start and end times; these appear on the start day, including at midnight. All-day events still require an exclusive end date after the start date. Google event time zones are preserved when interpreting timestamps; invalid remote dates stop replacement of that calendar's cached window and report a sync error.

Writes use cached ETags and reject stale edits. Sync and reopen an event after a conflict. For recurring events, edits create an occurrence override; deletion excludes that occurrence. Other occurrences, attendees, reminders and unrelated properties are preserved. New events are single events; creating recurrence rules or editing an entire series is not supported in this version.

Disconnect removes this plugin's local account credentials, calendar records and cached events. It does not remove remote calendars/events or revoke Google consent/Apple app-specific passwords; revoke those in the provider's account settings if desired.

## Validation limits

Local storage and the QML transport are tested in temporary directories. Provider tests mock HTTP pagination/conflicts and use real iCalendar fixtures for recurrence edits/deletions. Google and iCloud sign-in and bidirectional create/edit/delete have been exercised against live accounts using disposable events through the installed backend. Timed/all-day writes, remote-to-cache changes, real ETag conflicts and preservation of unrelated properties passed; all generated events were removed. The iCloud server-host correction was also verified by a real returned event and the user’s desktop confirmation. See [the live validation record](live-calendar-validation.md) for the exact method and remaining checks. The Google desktop app registration is stored privately outside Git; account tokens are never logged.
