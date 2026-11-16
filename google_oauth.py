"""Release-owned desktop OAuth configuration; never contains account tokens."""
import json
from pathlib import Path

CLIENT_FILE = Path(__file__).with_name('google-oauth.json')
UNAVAILABLE = 'Google sign-in is not available in this build. Velunori needs its Google application registration configured.'


def load_client(path=None):
    path = Path(path) if path is not None else CLIENT_FILE
    try:
        if path.stat().st_size > 100000: raise ValueError()
        config = json.loads(path.read_text())
        settings = config['installed']
        if not isinstance(settings, dict): raise ValueError()
        if not isinstance(settings.get('client_id'), str) or not settings['client_id'].endswith('.apps.googleusercontent.com'): raise ValueError()
        if not isinstance(settings.get('client_secret'), str) or not settings['client_secret'].strip(): raise ValueError()
        if settings.get('auth_uri') not in ('https://accounts.google.com/o/oauth2/auth', 'https://accounts.google.com/o/oauth2/v2/auth'): raise ValueError()
        if settings.get('token_uri') != 'https://oauth2.googleapis.com/token': raise ValueError()
        # Do not pass arbitrary extra fields, redirect destinations or account tokens.
        return {'installed': {key: settings[key] for key in ('client_id', 'client_secret', 'auth_uri', 'token_uri')}}
    except (OSError, ValueError, KeyError, TypeError):
        raise ValueError(UNAVAILABLE if path == CLIENT_FILE else 'Use the original Google Desktop OAuth client JSON.') from None


def ready():
    try: load_client()
    except ValueError: return False
    return True
