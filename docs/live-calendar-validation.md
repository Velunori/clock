# Live calendar validation

Validated on 16 November 2026 against the locally installed calendar backend,
using connected Google and iCloud accounts. This is live provider evidence,
separate from the fixture tests.

## Scope and method

The user completed browser sign-in for Google and app-specific-password sign-in
for iCloud, and confirmed events arriving in the desktop panel. iCloud reads
initially failed because a client rooted at the discovery server could not open
calendar URLs on Apple's numbered CalDAV servers. Using each discovered
calendar's validated HTTPS URL for the client corrected that failure. A live
read then returned a normal event, which the user confirmed in Velunori.

Write tests used the installed Python dispatcher, one writable primary Google
calendar and one writable personal iCloud calendar. A temporary private local
database kept test cache and account-token writes separate from the user's
normal database. Only uniquely marked disposable events were created or changed.
Provider-side changes were made directly through Google Calendar API / Apple
CalDAV requests, independently of the dispatcher's save/delete actions. No
unrelated event contents or credentials were included in the report.

| Live check | Google | iCloud |
| --- | --- | --- |
| Create through backend, verify directly at provider: timed and all-day | Passed | Passed |
| Edit through backend, verify directly at provider: timed and all-day | Passed | Passed |
| Independently edit remotely, sync into cache: timed and all-day | Passed | Passed |
| Reject stale backend edit after remote change without overwriting it | Passed | Passed |
| Preserve an unrelated remote property during a subsequent backend edit | Passed | Passed |
| Delete through backend, verify absence at provider: timed and all-day | Passed | Passed |
| Independently create remotely, sync into cache: timed | Passed | Passed |
| Independently delete remotely, sync removal into cache: timed | Passed | Passed |
| Remove all generated test events | Passed | Passed |

The extra-property checks used Google private extended properties and an iCalendar
X-property. Conflict checks used the providers' real ETags. No remote events
other than the generated test objects were edited or deleted.

## Limits

This verifies the installed backend and real provider APIs for the tested
accounts. It does not establish universal provider compatibility. It is not an
automated test of mouse/keyboard event editing in the desktop panel or of the
Google Calendar / iCloud.com web interfaces. Live recurrence-occurrence edits,
DST edge cases, offline recovery, long-term token refresh and persistence after
a further restart remain separate checks. Recurrence and DST fixture tests do
not replace those live checks.

iCloud birthdays generated from Contacts are outside the current CalDAV
integration. An absent generated birthday does not demonstrate a failure of
ordinary CalDAV event synchronization; Contacts access has not been tested or
enabled.
