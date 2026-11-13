import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from datetime import datetime, timezone
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import calendar_cloud as cloud
import calendar_store as store

HAS_ICAL = importlib.util.find_spec('icalendar') is not None

class CloudTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = store.DATA
        store.DATA = Path(self.temp.name)
    def tearDown(self):
        store.DATA = self.previous
        self.temp.cleanup()
    def test_untrusted_icloud_addresses_rejected(self):
        for url in ('http://caldav.icloud.com/a', 'https://icloud.com.evil.test/a', 'https://evil.test/a', 'https://user:pass@icloud.com/a'):
            with self.assertRaises(ValueError): cloud.icloud_url(url)
        self.assertEqual(cloud.icloud_url('https://p123-caldav.icloud.com/a'), 'https://p123-caldav.icloud.com/a')
    def test_accounts_are_private(self):
        identifier = '36638862-4068-433e-b7ba-a0859748192d'
        cloud.write_account(identifier, {'provider': 'test'})
        self.assertEqual(cloud.read_account(identifier), {'provider': 'test'})
        self.assertEqual(cloud.account_path(identifier).stat().st_mode & 0o777, 0o600)
        with self.assertRaises(ValueError): cloud.account_path('../file')
    def test_google_pagination_and_patch_preserve_unknown_fields(self):
        provider = object.__new__(cloud.Google)
        provider.request = Mock(side_effect=[{'items': [1], 'nextPageToken': 'next'}, {'items': [2]}])
        self.assertEqual(provider.pages('events', maxResults=2500), [1, 2])
        self.assertEqual(provider.request.call_args.kwargs['params']['pageToken'], 'next')
        provider.request = Mock()
        event = dict(title='New', start='2026-11-12', end='2026-11-13', allDay=True, location='', description='')
        provider.save({'remote': 'calendar@example.test'}, event, {'remote': 'event', 'etag': 'old'})
        args, kwargs = provider.request.call_args
        self.assertEqual(args[0], 'PATCH')
        self.assertEqual(kwargs['headers'], {'If-Match': 'old'})
        self.assertNotIn('attendees', kwargs['json'])
        self.assertNotIn('recurrence', kwargs['json'])
        self.assertEqual(kwargs['json']['start'], {'date': '2026-11-12'})
    def test_conflicts_are_explicit(self):
        response = Mock(status_code=412)
        with self.assertRaisesRegex(ValueError, 'another device'): cloud.check_response(response)
    def test_stale_editor_cannot_use_a_newly_refreshed_etag(self):
        from calendar_backend import dispatch
        identifier = store.add_calendar('Google', provider='google', account='account', remote='calendar')
        payload = dict(title='Current',start='2026-11-12',end='2026-11-13',allDay=True)
        event = store.save_event(identifier, payload, etag='current')
        with patch.object(cloud, 'provider') as provider:
            for request in ({'action':'save','calendarId':identifier,'id':event,'event':payload}, {'action':'delete','id':event}):
                with self.assertRaisesRegex(ValueError, 'changed'):
                    dispatch(dict(request, expectedEtag='old'))
            provider.assert_not_called()

    def test_sync_failure_keeps_cached_window(self):
        identifier = store.add_calendar('Google', provider='google', account='account', remote='calendar')
        store.save_event(identifier, dict(title='Keep',start='2026-11-12',end='2026-11-13',allDay=True))
        with patch.object(cloud, 'provider') as provider:
            provider.return_value.events.side_effect = OSError('offline')
            with self.assertRaises(OSError): cloud.sync('2026-11-01', '2026-11-30')
        self.assertEqual(store.snapshot('2026-11-01','2026-11-30')['events'][0]['title'], 'Keep')
    def test_sync_replaces_only_requested_window(self):
        identifier = store.add_calendar('Google', provider='google', account='account', remote='calendar')
        for day in ('2026-11-12','2026-12-12'):
            store.save_event(identifier, dict(title='Keep December',start=day,end=store.date.fromisoformat(day).replace(day=13).isoformat(),allDay=True))
        with patch.object(cloud, 'provider') as provider:
            provider.return_value.events.return_value = []
            cloud.sync('2026-11-01','2026-11-30')
        self.assertEqual(store.snapshot('2026-11-01','2026-11-30')['events'], [])
        self.assertEqual(len(store.snapshot('2026-12-01','2026-12-31')['events']),1)

@unittest.skipUnless(HAS_ICAL, 'Cloud dependencies are not installed')
class RecurrenceTests(unittest.TestCase):
    def source(self):
        from icalendar import Calendar
        return Calendar.from_ical('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:series\r\nDTSTART:20261112T100000Z\r\nDTEND:20261112T110000Z\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Original\r\nX-CUSTOM:keep\r\nEND:VEVENT\r\nEND:VCALENDAR')
    def test_edit_creates_only_one_override_and_preserves_series(self):
        source=self.source()
        cloud.mutate_ical(source, {'uid':'series','rid':'2026-11-13T10:00:00+00:00'}, dict(title='Changed',start='2026-11-13T12:00:00+00:00',end='2026-11-13T13:00:00+00:00',allDay=False,location='',description=''))
        from recurring_ical_events import of
        rows=of(source).between(datetime(2026,11,12,tzinfo=timezone.utc),datetime(2026,11,15,tzinfo=timezone.utc))
        self.assertEqual([str(row['SUMMARY']) for row in rows], ['Original','Changed','Original'])
        self.assertEqual([row.decoded('DTSTART').hour for row in rows], [10,12,10])
        self.assertTrue(all(str(row['X-CUSTOM']) == 'keep' for row in rows))
        self.assertIn('RRULE', source.walk('VEVENT')[0])
    def test_delete_excludes_only_selected_occurrence(self):
        source=self.source()
        cloud.mutate_ical(source, {'uid':'series','rid':'2026-11-13T10:00:00+00:00'}, None)
        from recurring_ical_events import of
        rows=of(source).between(datetime(2026,11,12,tzinfo=timezone.utc),datetime(2026,11,15,tzinfo=timezone.utc))
        self.assertEqual([row.decoded('DTSTART').day for row in rows], [12,14])



@unittest.skipUnless(HAS_ICAL, 'Cloud dependencies are not installed')
class ICloudAdapterTests(unittest.TestCase):
    def test_fetch_expands_series_and_retains_resource_etag(self):
        import caldav
        provider = object.__new__(cloud.ICloud)
        provider.client = Mock()
        provider.request = Mock(return_value=Mock(raw=RecurrenceTests().source().to_ical(), headers={'ETag': 'version-1'}))
        calendar = {'id':'source', 'remote':'https://caldav.icloud.com/cal/'}
        with patch.object(caldav, 'Calendar') as collection:
            collection.return_value.search.return_value = [Mock(url='https://caldav.icloud.com/cal/event.ics')]
            rows = provider.events(calendar, datetime(2026,11,12,tzinfo=timezone.utc), datetime(2026,11,15,tzinfo=timezone.utc))
        self.assertEqual(len(rows), 3)
        self.assertEqual(len({row[0] for row in rows}), 3)
        self.assertTrue(all(row[-1] == 'version-1' for row in rows))
        self.assertIn('2026-11-13T10:00:00', json.loads(rows[1][-2])['rid'])
    def test_stale_resource_is_never_put(self):
        provider = object.__new__(cloud.ICloud)
        provider.request = Mock(return_value=Mock(headers={'ETag':'changed'}))
        with self.assertRaisesRegex(ValueError, 'another device'):
            provider.save({}, {}, {'etag':'old','remote':json.dumps({'url':'https://caldav.icloud.com/cal/a.ics','uid':'series','rid':''})})
        self.assertEqual(provider.request.call_count, 1)
        self.assertEqual(provider.request.call_args.args[0], 'GET')

if __name__ == '__main__': unittest.main()
