import copy
import io
import json
import tempfile
import time
import unittest
from unittest.mock import patch
from backend import Backend, Failure

ENTRY = dict(id=11, workspace_id=1, project_id=None, description='Study', start='2026-10-03T12:00:00Z', stop=None, duration=-1)

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.b = Backend(self.temp.name)
        self.b.token = 'test-secret'
        self.b.online = True
        self.b.data = dict(user_id=7, workspace=1, workspaces=[dict(id=1,name='Personal')], projects=[], recent=[], current=None, catalog_at=time.time(), catalog_version=3)
        self.calls = []
        self.remote = None
        def request(method, path, body=None):
            self.calls.append((method, path, body))
            if method == 'GET':
                return copy.deepcopy(self.remote)
            if method == 'PATCH':
                result = dict(self.remote, stop='2026-10-03T13:00:00Z', duration=3600)
                self.remote = None
                return result
            self.remote = dict(ENTRY, **{k:v for k,v in body.items() if k in ENTRY})
            return copy.deepcopy(self.remote)
        self.b.request = request

    def test_active_projects_survive_false_tracking_hint(self):
        projects = [dict(id=1, workspace_id=1, name='Study', active=True, can_track_time=False),
                    dict(id=2, workspace_id=1, name='Archived', active=False),
                    dict(id=3, workspace_id=1, name='Deleted', active=True, status='deleted')]
        self.b.request = lambda method,path,body=None: dict(id=7, projects=projects,
            workspaces=[dict(id=1,name='Personal'),dict(id=2,name='Work')], default_workspace_id=1) if path.startswith('/me?') else None
        self.b.sync(full=True)
        self.assertEqual([p['id'] for p in self.b.data['projects']], [1])
        self.assertEqual([w['name'] for w in self.b.data['workspaces']], ['Personal','Work'])

    def test_old_project_cache_refreshes_on_upgrade(self):
        self.b.data.pop('catalog_version')
        calls = []
        def request(method,path,body=None):
            calls.append(path)
            return dict(id=7,workspaces=[dict(id=1,name='Personal')],projects=[]) if path.startswith('/me?') else None
        self.b.request = request
        self.b.sync()
        self.assertEqual(calls[0], '/me?with_related_data=true')
        self.assertEqual(self.b.data['catalog_version'], 3)

    def test_generic_workspaces_use_organization_names(self):
        rows = Backend.workspace_options(
            [dict(id=1,name='Workspace',organization_id=10), dict(id=2,name='Workspace',organization_id=20)],
            [dict(id=10,name='Study'),dict(id=20,name='Personal')])
        self.assertEqual([w['name'] for w in rows], ['Study','Personal'])

    def test_duplicate_workspaces_remain_distinguishable(self):
        rows = Backend.workspace_options([dict(id=1,name='Workspace'), dict(id=2,name='Workspace')], [])
        self.assertNotEqual(rows[0]['name'],rows[1]['name'])

    def test_start_empty_description(self):
        self.b.mutate(dict(action='start', expected_id=None, description=''))
        self.assertEqual(self.b.data['current']['description'], '')
        self.assertEqual(self.calls[-1][2]['duration'], -1)
        self.assertFalse(self.b.data['uncertain'])

    def test_switch_stops_before_start(self):
        self.remote = dict(ENTRY)
        self.b.mutate(dict(action='start', expected_id=11, description='Next'))
        self.assertEqual([c[0] for c in self.calls], ['GET', 'PATCH', 'POST'])
        self.assertEqual(self.b.data['recent'][0]['id'], 11)

    def test_external_change_does_not_stop_new_timer(self):
        self.remote = dict(ENTRY, id=12)
        with self.assertRaises(Failure):
            self.b.mutate(dict(action='stop', expected_id=11))
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.b.data['current']['id'], 12)

    def test_resume_creates_new_entry(self):
        self.b.data['recent'] = [dict(ENTRY, duration=50)]
        self.b.mutate(dict(action='resume', id=11, expected_id=None))
        self.assertEqual(self.calls[-1][2]['description'], 'Study')
        self.assertNotIn('id', self.calls[-1][2])

    def test_missing_project_preserves_running_timer(self):
        self.remote = dict(ENTRY)
        with self.assertRaises(Failure):
            self.b.mutate(dict(action='start', expected_id=11, project_id=999))
        self.assertEqual(len(self.calls), 1)

    def test_offline_no_mutation(self):
        self.b.online = False
        with self.assertRaises(Failure):
            self.b.mutate(dict(action='start'))
        self.assertFalse(self.calls)

    def test_ambiguous_write_requires_reconcile(self):
        original = self.b.request
        def request(method, path, body=None):
            result = original(method,path,body)
            if method == 'POST':
                raise Failure('Timeout')
            return result
        self.b.request = request
        with self.assertRaises(Failure):
            self.b.mutate(dict(action='start', expected_id=None))
        self.assertTrue(self.b.data['uncertain'])
        with self.assertRaises(Failure):
            self.b.mutate(dict(action='start', expected_id=None))
        self.assertEqual(len([c for c in self.calls if c[0]=='POST']), 1)
        self.b.sync()
        self.assertFalse(self.b.data['uncertain'])
        self.assertEqual(self.b.data['current']['id'], 11)

    def test_budget_persists_no_network_at_limit(self):
        self.b.data['calls'] = [time.time()]*30
        self.b.save()
        restored = Backend(self.temp.name)
        with patch('urllib.request.urlopen') as network:
            with self.assertRaises(Failure):
                restored.request('GET', '/me')
            network.assert_not_called()
        self.assertEqual(self.b.path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('test-secret', self.b.path.read_text())

    def test_quota_response_backoff(self):
        import urllib.error
        b = Backend(self.temp.name)
        with patch('urllib.request.urlopen', side_effect=urllib.error.HTTPError('url',402,'limit',{},None)):
            with self.assertRaises(Failure):
                b.request('GET','/me')
        self.assertGreater(b.data['blocked_until'], time.time())

    def test_auth_failure_clears_memory_token(self):
        import urllib.error
        b = Backend(self.temp.name)
        b.token='secret'
        with patch('urllib.request.urlopen', side_effect=urllib.error.HTTPError('url',401,'bad',{},None)):
            with self.assertRaises(Failure):
                b.request('GET','/me')
        self.assertEqual(b.token,'')

    def test_account_response_token_never_cached(self):
        self.b.request = lambda method,path,body=None: dict(id=7, api_token='do-not-cache', workspaces=[dict(id=1,name='Personal')], default_workspace_id=1) if path.startswith('/me?') else None
        self.b.sync(full=True)
        self.b.save()
        self.assertNotIn('do-not-cache', self.b.path.read_text())

    def test_stop_only(self):
        self.remote = dict(ENTRY)
        self.b.mutate(dict(action='stop', expected_id=11))
        self.assertIsNone(self.b.data['current'])
        self.assertEqual([c[0] for c in self.calls], ['GET','PATCH'])

if __name__ == '__main__':
    unittest.main()
