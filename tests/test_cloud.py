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

    def test_google_sync_instant_event_and_explicit_timezone(self):
        identifier = store.add_calendar('Google', provider='google', account='account', remote='calendar')
        provider = object.__new__(cloud.Google)
        provider.pages = Mock(return_value=[
            {'id': 'instant', 'etag': 'v1', 'start': {'dateTime': '2026-11-12T00:00:00Z'}, 'end': {'dateTime': '2026-11-12T00:00:00Z'}},
            {'id': 'zone', 'summary': '   ', 'start': {'dateTime': '2026-11-12T10:00:00', 'timeZone': 'America/New_York'},
             'end': {'dateTime': '2026-11-12T16:00:00Z'}},
            {'id': 'cancelled', 'status': 'cancelled'}])
        with patch.dict(store.os.environ, {'TZ': 'UTC'}), patch.object(cloud, 'provider', return_value=provider):
            cloud.sync('2026-11-01', '2026-11-30')
            events = store.snapshot('2026-11-12', '2026-11-12')['events']
            self.assertEqual(len(events), 2)
            self.assertTrue(all(event['calendar_id'] == identifier for event in events))
            self.assertEqual(events[0]['start'], events[0]['end'])
            self.assertEqual(events[0]['endDay'], '2026-11-12')
            self.assertEqual(events[1]['start'], '2026-11-12T15:00:00+00:00')
            self.assertEqual(events[1]['title'], '(Untitled)')
            self.assertEqual(provider.pages.call_args.kwargs['timeZone'], 'UTC')
            events[0]['title'] = 'Edited instant'
            provider.request = Mock()
            provider.save({'remote': 'calendar'}, store.validate_event(events[0]), events[0])
            self.assertEqual(provider.request.call_args.kwargs['json']['start'], provider.request.call_args.kwargs['json']['end'])

    def test_invalid_google_event_keeps_cache_and_reports_sync_error(self):
        from calendar_backend import dispatch
        identifier = store.add_calendar('Google', provider='google', account='account', remote='calendar')
        store.save_event(identifier, dict(title='Keep', start='2026-11-12', end='2026-11-13', allDay=True))
        provider = object.__new__(cloud.Google)
        provider.pages = Mock(return_value=[{'id': 'bad', 'start': {'date': '2026-11-12'}, 'end': {'date': '2026-11-11'}}])
        with patch.object(cloud, 'provider', return_value=provider):
            with self.assertRaisesRegex(ValueError, 'Sync failed.*Cached events'):
                dispatch(dict(action='sync', start='2026-11-01', end='2026-11-30'))
        snapshot = store.snapshot('2026-11-01', '2026-11-30')
        self.assertEqual(snapshot['events'][0]['title'], 'Keep')
        self.assertIn('Sync failed', snapshot['syncError'])
        self.assertIn('Google returned an event with invalid dates', snapshot['syncError'])

    def test_google_invalid_timezone_is_reported_without_event_details(self):
        with self.assertRaisesRegex(cloud.InvalidRemoteEvent, 'invalid dates or time zone') as failure:
            cloud.google_time({'dateTime': '2026-11-12T10:00:00', 'timeZone': 'private-invalid-zone'})
        self.assertNotIn('private-invalid-zone', str(failure.exception))
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
    def test_discovered_calendar_uses_its_own_icloud_server(self):
        import caldav
        calendar = {'provider': 'icloud', 'account': 'fixture', 'remote': 'https://p123-caldav.icloud.com/fixture/calendar/'}
        with patch.object(cloud, 'read_account', return_value={'username': 'fixture', 'password': 'fixture'}):
            provider = cloud.provider(calendar)
        try:
            collection = caldav.Calendar(client=provider.client, url=calendar['remote'])
            self.assertEqual(str(collection.url), calendar['remote'])
        finally:
            provider.client.close()

    def test_untrusted_calendar_server_rejected_before_reading_credentials(self):
        with patch.object(cloud, 'read_account') as read:
            with self.assertRaisesRegex(ValueError, 'unexpected calendar address'):
                cloud.provider({'provider': 'icloud', 'account': 'fixture', 'remote': 'https://icloud.com.evil.test/calendar/'})
            read.assert_not_called()

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
