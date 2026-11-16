import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import google_oauth
import calendar_cloud as cloud
import calendar_store as store
from calendar_backend import dispatch


def client():
    return {'installed': {
        'client_id': 'fixture.apps.googleusercontent.com', 'client_secret': 'fixture-desktop-value',
        'auth_uri': 'https://accounts.google.com/o/oauth2/auth', 'token_uri': 'https://oauth2.googleapis.com/token'}}


class TemporaryData(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'google-oauth.json'
        self.config_patch = patch.object(google_oauth, 'CLIENT_FILE', self.path)
        self.data_patch = patch.object(store, 'DATA', Path(self.temp.name)/'data')
        self.config_patch.start(); self.data_patch.start()

    def tearDown(self):
        self.data_patch.stop(); self.config_patch.stop(); self.temp.cleanup()


class ConfigurationTests(TemporaryData):
    def test_unconfigured_build_has_clear_status_and_no_account_side_effects(self):
        self.assertFalse(dispatch(dict(action='snapshot', start='2026-11-01', end='2026-11-30'))['googleSignInReady'])
        with self.assertRaisesRegex(ValueError, 'Google sign-in is not available'):
            dispatch(dict(action='connectGoogle', start='2026-11-01', end='2026-11-30'))
        self.assertFalse((store.DATA/'accounts').exists())

    def test_valid_config_is_ready_and_excludes_account_tokens_and_extra_fields(self):
        value = client()
        value['token'] = 'fixture-account-token'
        value['installed']['redirect_uris'] = ['https://unexpected.example/']
        self.path.write_text(json.dumps(value))
        self.assertTrue(google_oauth.ready())
        self.assertEqual(google_oauth.load_client(), client())

    def test_malformed_and_untrusted_configuration_is_rejected_safely(self):
        for text in ('null', '[]', '{', json.dumps({'web': client()['installed']})):
            self.path.write_text(text)
            self.assertFalse(google_oauth.ready())
        for key, value in [('auth_uri', 'https://untrusted.example/auth'), ('token_uri', 'https://untrusted.example/token'), ('client_id', ''), ('client_secret', '')]:
            config = client(); config['installed'][key] = value
            self.path.write_text(json.dumps(config))
            with self.assertRaises(ValueError) as error: google_oauth.load_client()
            self.assertNotIn(value or 'fixture-desktop-value', str(error.exception))


@unittest.skipUnless(importlib.util.find_spec('google_auth_oauthlib'), 'Google cloud dependencies are not installed')
class BrowserSignInTests(TemporaryData):
    def setUp(self):
        super().setUp()
        self.path.write_text(json.dumps(client()))
        self.factory_patch = patch('google_auth_oauthlib.flow.InstalledAppFlow.from_client_config')
        self.factory = self.factory_patch.start()
        self.flow = self.factory.return_value
        self.credentials = Mock(granted_scopes=cloud.SCOPES)
        self.credentials.has_scopes.return_value = True
        self.credentials.to_json.return_value = '{"token":"fixture-account-token"}'
        self.flow.run_local_server.return_value = self.credentials
        self.provider_patch = patch.object(cloud, 'Google')
        self.provider = self.provider_patch.start()
        self.provider.return_value.pages.return_value = [{'id': 'primary', 'summary': 'Test', 'primary': True, 'accessRole': 'owner'}]

    def tearDown(self):
        self.provider_patch.stop(); self.factory_patch.stop(); super().tearDown()

    def test_click_without_client_file_opens_browser_and_saves_account(self):
        with patch.object(cloud, 'sync') as sync:
            dispatch(dict(action='connectGoogle', start='2026-11-01', end='2026-11-30'))
        self.factory.assert_called_once_with(client(), cloud.SCOPES, autogenerate_code_verifier=True)
        args = self.flow.run_local_server.call_args.kwargs
        self.assertEqual((args['host'], args['port'], args['open_browser']), ('127.0.0.1', 0, True))
        calendars = [row for row in store.calendars() if row['provider'] == 'google']
        self.assertEqual(len(calendars), 1)
        self.assertFalse(calendars[0]['readonly'])
        self.assertTrue(cloud.account_path(calendars[0]['account']).exists())
        sync.assert_called_once_with('2026-11-01', '2026-11-30')

    def test_timeout_does_not_connect_or_write_credentials(self):
        self.flow.run_local_server.side_effect = TimeoutError()
        with self.assertRaisesRegex(ValueError, 'cancelled, expired or denied'): cloud.connect_google()
        self.assertFalse((store.DATA/'accounts').exists())

    def test_partial_consent_does_not_save_credentials(self):
        self.credentials.granted_scopes = cloud.SCOPES[:1]
        with self.assertRaisesRegex(ValueError, 'approve both'): cloud.connect_google()
        self.assertFalse((store.DATA/'accounts').exists())

    def test_calendar_discovery_failure_removes_credentials(self):
        self.provider.return_value.pages.side_effect = OSError('fixture-offline')
        with self.assertRaises(OSError): cloud.connect_google()
        self.assertEqual(list((store.DATA/'accounts').glob('*.json')), [])
        self.assertFalse(any(row['provider'] == 'google' for row in store.calendars()))
