"""Local calendar store and cache, independent of cloud libraries."""
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
import os
from pathlib import Path
import sqlite3
import uuid
from zoneinfo import ZoneInfo

DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))/'velunori/clock'
PALETTE = ['#c4aff1', '#a0ddbf', '#e8bf8a', '#91baf0', '#eaa7bb']


def local_zone():
    name = os.environ.get('TZ', '').removeprefix(':')
    if not name:
        path = str(Path('/etc/localtime').resolve())
        name = path.split('/zoneinfo/', 1)[-1] if '/zoneinfo/' in path else 'UTC'
    try: return ZoneInfo(name)
    except (KeyError, ValueError): return ZoneInfo('UTC')


@contextmanager
def database():
    DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(DATA, 0o700)
    connection = sqlite3.connect(DATA/'calendar.sqlite3', timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA journal_mode=WAL')
    connection.executescript('''
    CREATE TABLE IF NOT EXISTS calendars(id TEXT PRIMARY KEY, name TEXT, provider TEXT, color TEXT, enabled INTEGER, readonly INTEGER, account TEXT, remote TEXT);
    CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY, calendar_id TEXT, start TEXT, end TEXT, allday INTEGER, title TEXT, location TEXT, description TEXT, remote TEXT, etag TEXT);
    CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
    ''')
    connection.execute('INSERT OR IGNORE INTO calendars VALUES(?,?,?,?,?,?,?,?)', ('local','Personal','local',PALETTE[0],1,0,'',''))
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally: connection.close()
    os.chmod(DATA/'calendar.sqlite3', 0o600)


def calendars():
    with database() as db: return [dict(row) for row in db.execute('SELECT * FROM calendars ORDER BY provider,name')]


def calendar_by_id(identifier):
    with database() as db: row = db.execute('SELECT * FROM calendars WHERE id=?',(identifier,)).fetchone()
    if not row: raise ValueError('Calendar is no longer available')
    return dict(row)


def add_calendar(name, color=PALETTE[0], provider='local', account='', remote='', readonly=False, enabled=True):
    if not str(name).strip() or len(str(name))>160: raise ValueError('Enter a calendar name')
    if len(color)!=7 or color[0]!='#' or any(c not in '0123456789abcdefABCDEF' for c in color[1:]): raise ValueError('Choose a valid color')
    identifier = str(uuid.uuid5(uuid.NAMESPACE_URL,provider+':'+account+':'+remote)) if provider!='local' else str(uuid.uuid4())
    with database() as db:
        db.execute('INSERT INTO calendars VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,readonly=excluded.readonly', (identifier,name.strip(),provider,color,int(enabled),int(readonly),account,remote))
    return identifier


def validate_event(request):
    title = str(request.get('title','')).strip()
    if not title or len(title)>500: raise ValueError('Enter a title (up to 500 characters)')
    allday = bool(request.get('allDay'))
    try:
        if allday:
            start, end = date.fromisoformat(request['start']), date.fromisoformat(request['end'])
        else:
            start, end = datetime.fromisoformat(request['start']), datetime.fromisoformat(request['end'])
            zone = local_zone()
            moments=[]
            for moment in (start,end):
                if moment.tzinfo is None:
                    moment=moment.replace(tzinfo=zone)
                    if moment.replace(fold=0).utcoffset() != moment.replace(fold=1).utcoffset():
                        # Reject rather than silently choosing a repeated/nonexistent hour.
                        raise ValueError('This time crosses a daylight saving change. Use an explicit offset, e.g. 02:30+01:00.')
                    if moment.astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) != moment.replace(tzinfo=None):
                        raise ValueError('This time does not exist in your time zone')
                moments.append(moment)
            start,end=moments
    except (KeyError, TypeError) as error: raise ValueError('Choose valid start and end dates/times') from error
    invalid_range = end <= start if allday else end.timestamp() < start.timestamp()
    if invalid_range: raise ValueError('End must be after start' if allday else 'End must not be before start')
    return dict(title=title,start=start.isoformat(),end=end.isoformat(),allDay=allday,
                location=str(request.get('location',''))[:1000],description=str(request.get('description',''))[:10000])


def save_event(calendar_id, payload, identifier=None, remote='', etag=''):
    calendar = calendar_by_id(calendar_id)
    if calendar['readonly']: raise ValueError('This calendar is read-only')
    event = validate_event(payload)
    identifier = identifier or str(uuid.uuid4())
    with database() as db:
        if db.execute('SELECT calendar_id FROM events WHERE id=? AND calendar_id<>?',(identifier,calendar_id)).fetchone():
            raise ValueError('Moving events between calendars is not supported')
        db.execute('INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET start=excluded.start,end=excluded.end,allday=excluded.allday,title=excluded.title,location=excluded.location,description=excluded.description,remote=excluded.remote,etag=excluded.etag',
                   (identifier,calendar_id,event['start'],event['end'],int(event['allDay']),event['title'],event['location'],event['description'],remote,etag))
    return identifier


def get_event(identifier):
    with database() as db: row=db.execute('SELECT * FROM events WHERE id=?',(identifier,)).fetchone()
    if not row: raise ValueError('Event is no longer available')
    return dict(row)


def delete_event(identifier):
    row=get_event(identifier)
    if calendar_by_id(row['calendar_id'])['readonly']: raise ValueError('This calendar is read-only')
    with database() as db: db.execute('DELETE FROM events WHERE id=?',(identifier,))


def day_keys(row):
    if row['allday']:
        first=date.fromisoformat(row['start']); last=date.fromisoformat(row['end'])-timedelta(days=1)
    else:
        first=datetime.fromisoformat(row['start']).astimezone(local_zone()).date()
        end=datetime.fromisoformat(row['end']).astimezone(local_zone())
        start=datetime.fromisoformat(row['start']).astimezone(local_zone())
        last=(end-timedelta(microseconds=1)).date() if end.timestamp() > start.timestamp() else first
    return first.isoformat(), last.isoformat()


def snapshot(start, end):
    first, last=date.fromisoformat(start),date.fromisoformat(end)
    if last<first or (last-first).days>370: raise ValueError('Choose a calendar window of at most one year')
    with database() as db:
        rows=[dict(row) for row in db.execute('SELECT events.*,calendars.name AS calendarName,calendars.color,calendars.provider,calendars.readonly FROM events JOIN calendars ON events.calendar_id=calendars.id WHERE calendars.enabled=1')]
        meta={row['key']:row['value'] for row in db.execute('SELECT * FROM meta')}
    result=[]
    for row in rows:
        a,b=day_keys(row)
        if a>last.isoformat() or b<first.isoformat(): continue
        row.update(startDay=a,endDay=b,allDay=bool(row['allday']))
        if not row['allday']:
            row['start']=datetime.fromisoformat(row['start']).astimezone(local_zone()).isoformat()
            row['end']=datetime.fromisoformat(row['end']).astimezone(local_zone()).isoformat()
        result.append(row)
    result.sort(key=lambda row:(not row['allDay'],row['start'],row['title']))
    return dict(calendars=calendars(),events=result,lastSync=meta.get('lastSync',''),syncError=meta.get('syncError',''),timezone=str(local_zone()))
