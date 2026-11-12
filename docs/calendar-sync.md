# Calendar integration work in progress

The requested target is bidirectional Google Calendar and iCloud synchronization, editable local calendars, month markers and an agenda for the selected day (today on opening).

The current backend foundation implements persistent local calendars and event CRUD in SQLite. Cloud connections and the calendar UI are not implemented yet; do not describe this foundation as a finished synchronization feature.

Local data: `$XDG_DATA_HOME/velunori/clock/calendar.sqlite3`, falling back to `~/.local/share`. All-day end dates are exclusive. Timed events carry a UTC offset and display in the system time zone. The directory is private (0700), database 0600. No credentials are currently collected or stored.

`calendar_backend.py` reads one JSON request on stdin and returns one JSON response. Supported actions: `snapshot`, `addCalendar`, `visibility`, `save`, `delete`. Mutating remote calendar records is explicitly rejected until provider integrations exist.

## Next implementation steps

- Wire the backend to the existing QML calendar; add source filters, colored day markers, today's agenda, create/edit/delete forms, bounded popup height and scrolling.
- Google: desktop OAuth client with loopback sign-in; Calendar API calendar discovery and expanded event listing; create, patch and delete with ETag conflict checks. Never use an account password.
- iCloud: CalDAV discovery using an app-specific password; preserve original iCalendar properties on updates. Handle recurrence overrides and exclusions without deleting a series accidentally.
- Keep cached events after a failed sync and show last successful synchronization. Serialize simultaneous writes from different monitor widgets.
- Add mocked provider tests and exercise actual sign-in on user-connected accounts before claiming live cloud synchronization.

Provider dependencies can be installed into a private project environment with `bash scripts/setup-deps.sh`. The coding environment could not download them because DNS/network access was unavailable. Local storage requires only Python's standard library.

References: [Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Google event API](https://developers.google.com/workspace/calendar/api/v3/reference/events), [Apple app-specific passwords](https://support.apple.com/en-us/102654), [python-caldav](https://caldav.readthedocs.io/latest/tutorial.html).
