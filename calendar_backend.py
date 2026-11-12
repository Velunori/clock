#!/usr/bin/env python3
"""One JSON request on stdin, one JSON response on stdout. Never log credentials."""
import json
import sys
import calendar_store as store


def dispatch(request):
    action = request.get('action', 'snapshot')
    if action == 'snapshot':
        return store.snapshot(request['start'], request['end'])
    if action == 'addCalendar':
        return {'id': store.add_calendar(request['name'], request.get('color', store.PALETTE[0]))}
    if action == 'visibility':
        store.calendar_by_id(request['id'])
        with store.database() as db:
            db.execute('UPDATE calendars SET enabled=? WHERE id=?', (int(bool(request['enabled'])), request['id']))
        return {}
    if action == 'save':
        calendar = store.calendar_by_id(request['calendarId'])
        if calendar['provider'] != 'local':
            raise ValueError('Cloud accounts are not connected yet')
        return {'id': store.save_event(calendar['id'], request['event'], request.get('id'))}
    if action == 'delete':
        event = store.get_event(request['id'])
        if store.calendar_by_id(event['calendar_id'])['provider'] != 'local':
            raise ValueError('Cloud accounts are not connected yet')
        store.delete_event(request['id'])
        return {}
    raise ValueError('Unknown calendar action')


if __name__ == '__main__':
    try:
        raw = sys.stdin.read(100001)
        if len(raw) > 100000: raise ValueError('Request is too large')
        result = {'ok': True, 'data': dispatch(json.loads(raw))}
    except (ValueError, KeyError, TypeError) as error:
        result = {'ok': False, 'error': str(error) if isinstance(error, ValueError) else 'Invalid calendar request'}
    except Exception:
        result = {'ok': False, 'error': 'Calendar storage is unavailable'}
    print(json.dumps(result))
