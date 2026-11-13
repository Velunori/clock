#!/usr/bin/env python3
"""One JSON request on stdin, one JSON response on stdout. Never log credentials."""
import json
import sys
import logging
logging.disable(logging.CRITICAL)
import calendar_store as store


def dispatch(request):
    action = request.get('action', 'snapshot')
    if action == 'snapshot':
        return store.snapshot(request['start'], request['end'])
    if action in ('connectGoogle', 'connectIcloud', 'sync', 'disconnect'):
        import calendar_cloud as cloud
        with cloud.write_lock():
            if action == 'connectGoogle': cloud.connect_google(request.get('clientFile', ''))
            elif action == 'connectIcloud': cloud.connect_icloud(request.get('username', ''), request.get('password', ''))
            elif action == 'disconnect':
                account = request.get('account', '')
                path = cloud.account_path(account)
                with store.database() as db:
                    db.execute('DELETE FROM events WHERE calendar_id IN (SELECT id FROM calendars WHERE account=?)', (account,))
                    db.execute('DELETE FROM calendars WHERE account=?', (account,))
                path.unlink(missing_ok=True)
                return {}
            try: cloud.sync(request['start'], request['end'])
            except Exception:
                with store.database() as db: db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('syncError', 'Sync failed. Cached events have been kept.'))
                if action == 'sync': raise
                return {'warning': 'Account connected. Initial sync failed; try Sync again.'}
        return {}
    if action == 'addCalendar':
        return {'id': store.add_calendar(request['name'], request.get('color', store.PALETTE[0]))}
    if action == 'visibility':
        store.calendar_by_id(request['id'])
        with store.database() as db:
            db.execute('UPDATE calendars SET enabled=? WHERE id=?', (int(bool(request['enabled'])), request['id']))
        return {}
    if action == 'save':
        calendar = store.calendar_by_id(request['calendarId'])
        if calendar['provider'] == 'local':
            return {'id': store.save_event(calendar['id'], request['event'], request.get('id'))}
        import calendar_cloud as cloud
        if calendar['readonly']: raise ValueError('This calendar is read-only')
        previous = store.get_event(request['id']) if request.get('id') else None
        if previous and previous['calendar_id'] != calendar['id']: raise ValueError('Moving events between calendars is not supported')
        if previous and request.get('expectedEtag') != previous['etag']: raise ValueError('This event changed. Reopen it before editing.')
        payload = store.validate_event(request['event'])
        with cloud.write_lock():
            cloud.provider(calendar).save(calendar, payload, previous)
            try: cloud.sync(request['start'], request['end'])
            except Exception: return {'warning': 'Saved to your account. Refresh with Sync to update the agenda.'}
        return {}
    if action == 'delete':
        event = store.get_event(request['id'])
        calendar = store.calendar_by_id(event['calendar_id'])
        if calendar['provider'] != 'local':
            import calendar_cloud as cloud
            if calendar['readonly']: raise ValueError('This calendar is read-only')
            if request.get('expectedEtag') != event['etag']: raise ValueError('This event changed. Reopen it before removing it.')
            with cloud.write_lock(): cloud.provider(calendar).delete(calendar, event)
        store.delete_event(request['id'])
        return {}
    raise ValueError('Unknown calendar action')


if __name__ == '__main__':
    try:
        raw = sys.stdin.readline(100001)
        if len(raw) > 100000: raise ValueError('Request is too large')
        result = {'ok': True, 'data': dispatch(json.loads(raw))}
    except (ValueError, KeyError, TypeError) as error:
        result = {'ok': False, 'error': str(error) if isinstance(error, ValueError) else 'Invalid calendar request'}
    except ImportError:
        result = {'ok': False, 'error': 'Cloud libraries are missing. Run clock/scripts/setup-deps.sh.'}
    except Exception:
        result = {'ok': False, 'error': 'Calendar operation failed. Check your connection and account authorization, then try again.'}
    print(json.dumps(result))
