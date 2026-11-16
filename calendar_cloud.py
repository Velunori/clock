"""Optional cloud providers. Imports and account access are explicit, never on startup."""
from contextlib import contextmanager
from copy import deepcopy
from datetime import date, datetime, time, timedelta, timezone
import fcntl
import json
import os
from pathlib import Path
from urllib.parse import quote, urlparse
import uuid
from zoneinfo import ZoneInfo
import calendar_store as store
import google_oauth

SCOPES = ['https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/calendar.calendarlist.readonly']
API = 'https://www.googleapis.com/calendar/v3/'


class InvalidRemoteEvent(ValueError):
    """Safe, credential-free diagnostics for rejected provider data."""


@contextmanager
def write_lock():
    store.DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (store.DATA/'write.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('Another calendar operation is running. Try again shortly.')
        yield


def account_path(identifier):
    if str(uuid.UUID(identifier)) != identifier: raise ValueError('Invalid account')
    return store.DATA/'accounts'/(identifier+'.json')


def write_account(identifier, value):
    path = account_path(identifier)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    temp = path.with_suffix('.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream: json.dump(value, stream)
    os.replace(temp, path)


def read_account(identifier):
    return json.loads(account_path(identifier).read_text())


def check_response(response):
    status = getattr(response, 'status_code', getattr(response, 'status', 0))
    if status == 412: raise ValueError('This event changed on another device. Sync, then reopen it before editing.')
    if status in (401, 403): raise ValueError('Calendar access was denied. Check account authorization and calendar permissions.')
    if status < 200 or status >= 300: raise ValueError('Calendar server request failed. Your cached events have been kept.')
    return response


class Google:
    def __init__(self, account):
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import AuthorizedSession
        self.account = account
        self.credentials = Credentials.from_authorized_user_info(read_account(account)['credentials'], SCOPES)
        self.session = AuthorizedSession(self.credentials)

    def request(self, method, path, **kwargs):
        response = check_response(self.session.request(method, API+path, timeout=25, **kwargs))
        write_account(self.account, {'provider': 'google', 'credentials': json.loads(self.credentials.to_json())})
        return response.json() if response.content else {}

    def pages(self, path, **params):
        rows = []
        while True:
            response = self.request('GET', path, params=params)
            rows.extend(response.get('items', []))
            if not response.get('nextPageToken'): return rows
            params['pageToken'] = response['nextPageToken']

    def events(self, calendar, start, end):
        rows = self.pages('calendars/'+quote(calendar['remote'], safe='')+'/events', singleEvents='true',
                          timeMin=start.isoformat(), timeMax=end.isoformat(), timeZone='UTC', maxResults=2500)
        result = []
        for row in rows:
            if row.get('status') == 'cancelled': continue
            a, b = row.get('start', {}), row.get('end', {})
            allday = 'date' in a
            payload = dict(title=str(row.get('summary') or '').strip() or '(Untitled)', start=google_time(a), end=google_time(b),
                           allDay=allday, location=row.get('location', ''), description=row.get('description', ''))
            try: result.append(record(calendar, payload, row['id'], row.get('etag', '')))
            except (ValueError, KeyError, TypeError) as error:
                raise InvalidRemoteEvent('Google returned an event with invalid dates or content.') from error
        return result

    def save(self, calendar, event, previous=None):
        body = {'summary': event['title'], 'location': event['location'], 'description': event['description']}
        for key in ('start', 'end'):
            body[key] = {'date' if event['allDay'] else 'dateTime': event[key]}
        path = 'calendars/'+quote(calendar['remote'], safe='')+'/events'
        headers = {}
        if previous:
            if not previous['etag']: raise ValueError('Sync this event before editing it')
            path += '/'+quote(previous['remote'], safe=''); headers['If-Match'] = previous['etag']
        # PATCH only supported fields: preserve attendees, reminders and other metadata.
        self.request('PATCH' if previous else 'POST', path, json=body, headers=headers)

    def delete(self, calendar, previous):
        if not previous['etag']: raise ValueError('Sync this event before removing it')
        self.request('DELETE', 'calendars/'+quote(calendar['remote'], safe='')+'/events/'+quote(previous['remote'], safe=''), headers={'If-Match': previous['etag']})


def google_time(value):
    if 'date' in value: return value['date']
    try:
        moment = datetime.fromisoformat(value['dateTime'])
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=ZoneInfo(value.get('timeZone') or 'UTC'))
        return moment.isoformat()
    except (KeyError, TypeError, ValueError) as error:
        raise InvalidRemoteEvent('Google returned an event with invalid dates or time zone.') from error


def connect_google(client_file=''):
    config = google_oauth.load_client(Path(client_file).expanduser() if client_file else None)
    from google_auth_oauthlib.flow import InstalledAppFlow
    from oauthlib.oauth2 import OAuth2Error
    flow = InstalledAppFlow.from_client_config(config, SCOPES, autogenerate_code_verifier=True)
    try:
        credentials = flow.run_local_server(host='127.0.0.1', port=0, open_browser=True, timeout_seconds=180,
            authorization_prompt_message='', success_message='Google sign-in received. Return to Velunori to check the connection.')
    except (OAuth2Error, TimeoutError):
        raise ValueError('Google sign-in was cancelled, expired or denied. Press Connect Google to try again.') from None
    if credentials is None or not credentials.has_scopes(SCOPES) or (credentials.granted_scopes is not None and not set(SCOPES).issubset(credentials.granted_scopes)):
        raise ValueError('Google calendar access was not granted. Connect again and approve both calendar permissions.')
    identifier = str(uuid.uuid4())
    write_account(identifier, {'provider': 'google', 'credentials': json.loads(credentials.to_json())})
    try:
        rows = Google(identifier).pages('users/me/calendarList', maxResults=250)
        if not rows: raise ValueError('No Google calendars are available for this account')
        for index, row in enumerate(rows):
            store.add_calendar(row.get('summary', 'Google calendar'), row.get('backgroundColor', store.PALETTE[index % 5]),
                provider='google', account=identifier, remote=row['id'], readonly=row.get('accessRole') not in ('owner', 'writer'), enabled=bool(row.get('primary')))
    except Exception:
        account_path(identifier).unlink(missing_ok=True)
        with store.database() as db: db.execute('DELETE FROM calendars WHERE account=?', (identifier,))
        raise


def icloud_url(url):
    parsed = urlparse(str(url))
    if parsed.scheme != 'https' or not parsed.hostname or not (parsed.hostname == 'icloud.com' or parsed.hostname.endswith('.icloud.com')) or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('iCloud returned an unexpected calendar address')
    return str(url)


class ICloud:
    def __init__(self, account=None, username=None, password=None, url='https://caldav.icloud.com'):
        import caldav
        server = icloud_url(url)
        data = read_account(account) if account else {'username': username, 'password': password}
        self.client = caldav.DAVClient(url=server, username=data['username'], password=data['password'], timeout=25)

    def request(self, method, url, **kwargs):
        return check_response(self.client.request(icloud_url(url), method=method, **kwargs))

    def events(self, calendar, start, end):
        import caldav
        from icalendar import Calendar
        import recurring_ical_events
        collection = caldav.Calendar(client=self.client, url=icloud_url(calendar['remote']))
        result = []
        for resource in collection.search(start=start, end=end, event=True, expand=False):
            url = icloud_url(resource.url)
            response = self.request('GET', url)
            source = Calendar.from_ical(response.raw)
            components = source.walk('VEVENT')
            recurring = any('RRULE' in e or 'RDATE' in e or 'RECURRENCE-ID' in e for e in components)
            for occurrence in recurring_ical_events.of(source).between(start, end):
                a = occurrence.decoded('DTSTART'); b = occurrence.decoded('DTEND', None)
                if b is None: b = a + occurrence.decoded('DURATION', timedelta(days=1) if not isinstance(a, datetime) else timedelta(hours=1))
                allday = not isinstance(a, datetime)
                if not allday:
                    if a.tzinfo is None: a = a.replace(tzinfo=store.local_zone())
                    if b.tzinfo is None: b = b.replace(tzinfo=store.local_zone())
                rid = occurrence.get('RECURRENCE-ID') if recurring else None
                remote = json.dumps({'url': url, 'rid': rid.dt.isoformat() if rid else '', 'uid': str(occurrence['UID'])}, sort_keys=True)
                payload = dict(title=str(occurrence.get('SUMMARY') or '(Untitled)'), start=a.isoformat(), end=b.isoformat(), allDay=allday,
                               location=str(occurrence.get('LOCATION', '')), description=str(occurrence.get('DESCRIPTION', '')))
                result.append(record(calendar, payload, remote, response.headers.get('ETag', '')))
        return result

    def save(self, calendar, event, previous=None):
        from icalendar import Calendar, Event
        if previous:
            remote = json.loads(previous['remote']); response = self.request('GET', remote['url'])
            if not previous['etag'] or response.headers.get('ETag') != previous['etag']: raise ValueError('This event changed on another device. Sync and reopen it.')
            source = Calendar.from_ical(response.raw)
            mutate_ical(source, remote, event)
            self.request('PUT', remote['url'], body=source.to_ical().decode(), headers={'Content-Type': 'text/calendar; charset=utf-8', 'If-Match': previous['etag']})
        else:
            source = Calendar(); source.add('PRODID', '-//Velunori//Calendar//EN'); source.add('VERSION', '2.0')
            component = Event(); component.add('UID', str(uuid.uuid4())); component.add('DTSTAMP', datetime.now(timezone.utc)); source.add_component(component)
            set_ical_fields(component, event)
            url = calendar['remote'].rstrip('/')+'/'+str(component['UID'])+'.ics'
            self.request('PUT', url, body=source.to_ical().decode(), headers={'Content-Type': 'text/calendar; charset=utf-8', 'If-None-Match': '*'})

    def delete(self, calendar, previous):
        from icalendar import Calendar
        remote = json.loads(previous['remote'])
        if not previous['etag']: raise ValueError('Sync this event before removing it')
        if not remote['rid']:
            self.request('DELETE', remote['url'], headers={'If-Match': previous['etag']})
        else:
            response = self.request('GET', remote['url'])
            if response.headers.get('ETag') != previous['etag']: raise ValueError('This event changed on another device. Sync and reopen it.')
            source = Calendar.from_ical(response.raw); mutate_ical(source, remote, None)
            self.request('PUT', remote['url'], body=source.to_ical().decode(), headers={'Content-Type': 'text/calendar; charset=utf-8', 'If-Match': previous['etag']})


def parse_rid(value):
    return datetime.fromisoformat(value) if 'T' in value else date.fromisoformat(value)


def set_ical_fields(component, event):
    for key in ('SUMMARY', 'DTSTART', 'DTEND', 'DURATION', 'LOCATION', 'DESCRIPTION', 'DTSTAMP'):
        component.pop(key, None)
    component.add('SUMMARY', event['title']); component.add('LOCATION', event['location']); component.add('DESCRIPTION', event['description'])
    for key in ('start', 'end'):
        value = date.fromisoformat(event[key]) if event['allDay'] else datetime.fromisoformat(event[key]).astimezone(timezone.utc)
        component.add('DT'+key.upper(), value)
    component.add('DTSTAMP', datetime.now(timezone.utc))
    component['SEQUENCE'] = int(component.get('SEQUENCE', 0)) + 1


def mutate_ical(source, remote, event):
    components = [e for e in source.walk('VEVENT') if str(e.get('UID')) == remote['uid']]
    master = next((e for e in components if 'RECURRENCE-ID' not in e), None)
    if master is None: raise ValueError('The recurring event cannot be edited safely')
    if not remote['rid']:
        if event is None: raise ValueError('Missing occurrence information')
        set_ical_fields(master, event); return
    rid = parse_rid(remote['rid'])
    override = next((e for e in components if e.get('RECURRENCE-ID') and e.decoded('RECURRENCE-ID') == rid), None)
    if event is None:
        master.add('EXDATE', rid)
        if override is not None: source.subcomponents.remove(override)
        master['SEQUENCE'] = int(master.get('SEQUENCE', 0)) + 1
        return
    if override is None:
        override = deepcopy(master)
        for key in ('RRULE', 'RDATE', 'EXDATE'): override.pop(key, None)
        override.add('RECURRENCE-ID', rid); source.add_component(override)
    set_ical_fields(override, event)


def connect_icloud(username, password):
    if not username.strip() or not password.strip(): raise ValueError('Enter your Apple Account and an app-specific password')
    provider = ICloud(username=username.strip(), password=password.strip())
    rows = provider.client.principal().calendars()
    if not rows: raise ValueError('No iCloud calendars are available for this account')
    identifier = str(uuid.uuid4())
    # Validate all addresses before storing any credential or calendar.
    for row in rows: icloud_url(row.url)
    write_account(identifier, {'provider': 'icloud', 'username': username.strip(), 'password': password.strip()})
    try:
        for index, row in enumerate(rows):
            store.add_calendar(row.name or 'iCloud calendar', store.PALETTE[index % 5], provider='icloud', account=identifier, remote=str(row.url))
    except Exception:
        account_path(identifier).unlink(missing_ok=True)
        with store.database() as db: db.execute('DELETE FROM calendars WHERE account=?', (identifier,))
        raise


def provider(calendar):
    return Google(calendar['account']) if calendar['provider'] == 'google' else ICloud(calendar['account'], url=calendar['remote'])


def record(calendar, payload, remote, etag):
    payload = store.validate_event(dict(payload, title=str(payload['title'])[:500]))
    return (str(uuid.uuid5(uuid.NAMESPACE_URL, calendar['id']+':'+remote)), calendar['id'], payload['start'], payload['end'], int(payload['allDay']),
            payload['title'], payload['location'], payload['description'], remote, etag)


def sync(start, end):
    first, last = date.fromisoformat(start), date.fromisoformat(end)
    if last < first or (last-first).days > 370: raise ValueError('Invalid sync window')
    a = datetime.combine(first, time.min, store.local_zone()); b = datetime.combine(last+timedelta(days=1), time.min, store.local_zone())
    for calendar in store.calendars():
        if calendar['provider'] == 'local' or not calendar['enabled']: continue
        rows = provider(calendar).events(calendar, a, b)
        # Replace only the successfully fetched window in a transaction. Retain
        # other months and all cached data on a network/parse error.
        with store.database() as db:
            for old in db.execute('SELECT * FROM events WHERE calendar_id=?', (calendar['id'],)).fetchall():
                x, y = store.day_keys(dict(old))
                if x <= end and y >= start: db.execute('DELETE FROM events WHERE id=?', (old['id'],))
            db.executemany('INSERT OR REPLACE INTO events VALUES(?,?,?,?,?,?,?,?,?,?)', rows)
    with store.database() as db:
        db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('lastSync', datetime.now(timezone.utc).isoformat()))
        db.execute('DELETE FROM meta WHERE key=?', ('syncError',))
