import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import calendar_store as store
from calendar_backend import dispatch

class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = store.DATA
        store.DATA = Path(self.temp.name)
    def tearDown(self):
        store.DATA = self.previous
        self.temp.cleanup()
    def test_crud_and_exclusive_end(self):
        event = dict(title='Two days', start='2026-11-12', end='2026-11-14', allDay=True)
        identifier = store.save_event('local', event)
        self.assertEqual(len(store.snapshot('2026-11-13', '2026-11-13')['events']), 1)
        self.assertEqual(store.snapshot('2026-11-14', '2026-11-14')['events'], [])
        event['title'] = 'Updated'
        store.save_event('local', event, identifier)
        self.assertEqual(store.get_event(identifier)['title'], 'Updated')
        store.delete_event(identifier)
        self.assertEqual(store.snapshot('2026-11-01', '2026-11-30')['events'], [])
    def test_invalid_range(self):
        with self.assertRaises(ValueError):
            store.save_event('local', dict(title='Invalid', start='2026-11-12', end='2026-11-12', allDay=True))
    def test_readonly(self):
        calendar = store.add_calendar('Shared', provider='google', account='test', remote='test', readonly=True)
        with self.assertRaises(ValueError):
            store.save_event(calendar, dict(title='No',start='2026-11-12',end='2026-11-13',allDay=True))
    def test_backend_actions(self):
        result = dispatch(dict(action='save', calendarId='local', event=dict(title='RPC', start='2026-11-12', end='2026-11-13', allDay=True)))
        self.assertEqual(dispatch(dict(action='snapshot', start='2026-11-12', end='2026-11-12'))['events'][0]['id'], result['id'])
        dispatch(dict(action='visibility', id='local', enabled=False))
        self.assertEqual(dispatch(dict(action='snapshot', start='2026-11-12', end='2026-11-12'))['events'], [])
        dispatch(dict(action='delete', id=result['id']))
    def test_persistence(self):
        store.save_event('local', dict(title='Saved',start='2026-11-12T10:00:00+01:00',end='2026-11-12T11:00:00+01:00'))
        self.assertEqual(store.snapshot('2026-11-12','2026-11-12')['events'][0]['title'], 'Saved')
        self.assertEqual((store.DATA/'calendar.sqlite3').stat().st_mode & 0o777, 0o600)

if __name__ == '__main__': unittest.main()
