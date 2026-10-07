#!/usr/bin/env python3
"""Toggl helper: private cache, Secret Service token, serialized JSON-line IPC."""
import base64
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess
from pomodoro import Pomodoro
from local_ipc import Server
import sys
import time
import urllib.request
import urllib.error

class Failure(Exception):
    pass

class Backend:
    def __init__(self, directory=None):
        self.directory = Path(directory or Path(os.getenv('XDG_STATE_HOME', Path.home()/'.local/state'))/'omarchy/toggl')
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = self.directory/'state.json'
        try:
            self.data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            self.data = {}
        self.publisher = None
        self.token = ''
        self.online = False
        self.message = 'Connect your Toggl account'
        self.busy = False
        self.pomo = Pomodoro(self)

    def save(self):
        temporary = self.path.with_suffix('.tmp')
        fd = os.open(temporary, os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as file:
            json.dump(self.data, file)
        os.replace(temporary, self.path)

    def emit(self):
        line = json.dumps(dict(self.data, connected=bool(self.token), online=self.online,
                               busy=self.busy, message=self.message))
        print(line, flush=True)
        if self.publisher:
            self.publisher((line + "\n").encode())

    def secret(self, action, token=None):
        command = ['secret-tool', action]
        if action == 'store':
            command += ['--label=Omarchy Toggl Track']
        result = subprocess.run(command + ['application', 'fabi.toggl'],
                                input=token, text=True, capture_output=True, timeout=30)
        if result.returncode and action != 'lookup':
            raise Failure('Unlock your keyring, then retry account setup.')
        return result.stdout.strip()

    def request(self, method, path, body=None):
        now = time.time()
        calls = [x for x in self.data.get('calls', []) if now-x < 3600]
        if self.data.get('blocked_until', 0) > now or len(calls) >= 30:
            raise Failure('API quota reached. Try again after the hourly window resets.')
        if calls:
            time.sleep(max(0, 1.05-(now-calls[-1])))
        self.data['calls'] = calls + [time.time()]
        self.save()
        auth = base64.b64encode((self.token+':api_token').encode()).decode()
        request = urllib.request.Request('https://api.track.toggl.com/api/v9'+path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': 'Basic '+auth, 'Content-Type': 'application/json'}, method=method)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            if error.code in (402, 429):
                try:
                    delay = max(60, int(error.headers.get('Retry-After', '3600')))
                except ValueError:
                    delay = 3600
                self.data['blocked_until'] = time.time()+delay
                raise Failure('Toggl API quota reached. Synchronization will retry later.') from None
            if error.code == 401:
                self.token = ''
                raise Failure('Authentication failed. Reconnect in Account settings.') from None
            if error.code == 403:
                raise Failure('Access denied. Check your workspace and project permissions.') from None
            raise Failure('Toggl could not complete the request (HTTP %s). Refresh before retrying.' % error.code) from None
        except (OSError, ValueError, TimeoutError):
            raise Failure('Connection interrupted. Refresh to confirm the timer before retrying.') from None

    @staticmethod
    def entry(value):
        if not value:
            return None
        return {k: value.get(k) for k in ('id', 'workspace_id', 'project_id', 'description', 'start', 'stop', 'duration')}

    def recent(self, entries):
        self.data['recent'] = [self.entry(e) for e in sorted(entries, key=lambda e:e.get('start') or '', reverse=True)
                               if e.get('duration', -1) >= 0 and not e.get('server_deleted_at')][:30]

    @staticmethod
    def workspace_options(workspaces, organizations):
        names = {o['id']: o.get('name', '') for o in organizations}
        result = []
        for workspace in workspaces:
            raw = workspace.get('name') or 'Workspace'
            organization = workspace.get('organization_name') or names.get(workspace.get('organization_id'), '')
            label = organization if raw.lower() == 'workspace' and organization else (organization + ' · ' + raw if organization and organization != raw else raw)
            result.append({'id': workspace['id'], 'name': label})
        labels = [w['name'] for w in result]
        for workspace in result:
            if labels.count(workspace['name']) > 1:
                workspace['name'] += ' · ' + str(workspace['id'])
        return result

    def sync(self, full=False):
        if full or self.data.get('catalog_version') != 3 or time.time()-self.data.get('catalog_at', 0) > 86400:
            me = self.request('GET', '/me?with_related_data=true')
            if self.data.get('user_id') != me['id']:
                calls = self.data.get('calls', [])
                self.data = {'calls': calls}
            self.data['user_id'] = me['id']
            workspaces = me.get('workspaces') or []
            organizations = self.request('GET', '/me/organizations') if any(w.get('organization_id') and not w.get('organization_name') for w in workspaces) else []
            self.data['workspaces'] = self.workspace_options(workspaces, organizations)
            ids = [w['id'] for w in self.data['workspaces']]
            if self.data.get('workspace') not in ids:
                self.data['workspace'] = me.get('default_workspace_id') if me.get('default_workspace_id') in ids else (ids[0] if ids else None)
            self.data['projects'] = [{'id': p['id'], 'workspace_id': p.get('workspace_id', p.get('wid')), 'name': p['name']}
                                     for p in me.get('projects') or [] if p.get('active', True) and p.get('status') not in ('archived', 'deleted', 'ended') and not p.get('server_deleted_at')]
            self.recent(me.get('time_entries') or [])
            # Related-data can_track_time is false even for active personal projects.
            # The write endpoint remains authoritative for tracking permissions.
            self.data['catalog_version'] = 3
            self.data['catalog_at'] = time.time()
        self.data['current'] = self.entry(self.request('GET', '/me/time_entries/current'))
        self.data['synced_at'] = time.time()
        self.data['uncertain'] = False
        self.online = True
        self.message = 'Synced with Toggl'

    def mutate(self, command, prechecked=False):
        if not self.online or self.data.get('uncertain'):
            raise Failure('Refresh to confirm the timer before making changes.')
        expected = command.get('expected_id')
        if not prechecked:
            self.sync()
        current = self.data.get('current')
        if (current or {}).get('id') != expected:
            raise Failure('The timer changed on another device. Review it and try again.')
        action = command['action']
        workspace = self.data.get('workspace')
        project = command.get('project_id')
        description = command.get('description', '')
        if action == 'resume':
            old = next((e for e in self.data.get('recent', []) if e['id'] == command.get('id')), None)
            if not old:
                raise Failure('This recent entry is no longer available.')
            workspace, project, description = old['workspace_id'], old['project_id'], old['description'] or ''
        if action != 'stop':
            if workspace not in [w['id'] for w in self.data.get('workspaces', [])]:
                raise Failure('Select an available workspace in Account settings.')
            if project is not None and not any(p['id'] == project and p['workspace_id'] == workspace for p in self.data.get('projects', [])):
                raise Failure('Project unavailable. Refresh projects or choose another project.')
        # Reserve enough local quota before stopping, so switching cannot fail solely on our budget.
        needed = (1 if current else 0) + (0 if action == 'stop' else 1)
        if len(self.data.get('calls', []))+needed > 30:
            raise Failure('Not enough API quota for this change. Try again later.')
        self.data['uncertain'] = True
        self.save()
        if current:
            if command.get('stop_at') is not None:
                started = dt.datetime.fromisoformat(current['start'].replace('Z', '+00:00')).timestamp()
                stopped_at = started + max(0, int(command['stop_at']-started))
                stopped = self.request('PUT', '/workspaces/%s/time_entries/%s' % (current['workspace_id'], current['id']),
                    dict(start=current['start'], stop=dt.datetime.fromtimestamp(stopped_at, dt.timezone.utc).isoformat().replace('+00:00','Z'),
                         duration=max(0, int(stopped_at-started)), workspace_id=current['workspace_id'],
                         description=current.get('description') or '', project_id=current.get('project_id')))
            else:
                stopped = self.request('PATCH', '/workspaces/%s/time_entries/%s/stop' % (current['workspace_id'], current['id']))
            self.data['current'] = None
            if stopped:
                self.recent([stopped]+[e for e in self.data.get('recent', []) if e['id'] != stopped['id']])
            self.save()
        if action != 'stop':
            body = dict(workspace_id=workspace, project_id=project, description=description,
                        start=dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00','Z'),
                        duration=-1, created_with='Omarchy fabi.toggl')
            self.data['current'] = self.entry(self.request('POST', '/workspaces/%s/time_entries' % workspace, body))
        self.data['uncertain'] = False
        self.data['synced_at'] = time.time()
        self.message = 'Synced with Toggl'

    @staticmethod
    def fail(message):
        raise Failure(message)

    def notify(self, title, message):
        subprocess.Popen(['notify-send', '--app-name=Toggl Pomodoro', title, message], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def handle(self, command):
        self.busy = True
        self.emit()
        try:
            action = command.get('action')
            if action == 'connect':
                candidate = command.get('token', '').strip()
                if not candidate:
                    raise Failure('Enter your Toggl API token.')
                self.token = candidate
                self.sync(full=True)
                self.secret('store', candidate)
            elif action == 'init':
                self.token = self.secret('lookup')
                if self.token:
                    self.sync()
                    self.pomo.reconcile()
                else:
                    self.message = 'Connect your Toggl account, or unlock your keyring and retry.'
            elif action == 'disconnect':
                if self.pomo.state['status'] in ('running', 'starting', 'stop_pending', 'review') or self.pomo.state.get('entry_id'):
                    raise Failure('Reset Pomodoro before disconnecting your account.')
                self.secret('clear')
                self.token = ''
                preferences = self.pomo.state.get('settings', {})
                self.data = {'calls': self.data.get('calls', []), 'blocked_until': self.data.get('blocked_until', 0)}
                self.pomo.state['settings'] = preferences
                self.pomo.state['remaining'] = self.pomo.duration('focus')
                self.online = False
                self.message = 'Account disconnected. Any running Toggl timer continues.'
            elif action == 'workspace':
                if command.get('id') in [w['id'] for w in self.data.get('workspaces', [])]:
                    self.data['workspace'] = command['id']
            elif action == 'pomo_configure':
                self.pomo.action(command)
            elif action == 'pomo_tick':
                self.pomo.tick()
            elif self.token:
                if action.startswith('pomo_'):
                    self.pomo.action(command)
                elif action in ('refresh', 'poll'):
                    if action == 'poll' and time.time()-self.data.get('synced_at',0)<300:
                        return
                    self.sync(full=action=='refresh')
                    self.pomo.reconcile()
                elif action in ('start', 'stop', 'resume'):
                    if self.pomo.state['status'] in ('running', 'starting', 'stop_pending'):
                        raise Failure('Pause or reset Pomodoro before changing the Toggl timer manually.')
                    self.mutate(command)
            else:
                raise Failure('Connect your Toggl account first.')
        except (Failure, subprocess.TimeoutExpired) as error:
            self.online = False
            self.message = str(error) if isinstance(error, Failure) else 'Keyring did not respond. Unlock it and retry.'
            if command.get('action') == 'pomo_tick':
                self.notify('Pomodoro needs attention', 'Could not confirm that Toggl stopped. Open the timer and refresh. The Toggl entry may still be running.')
        except Exception:
            self.online = False
            self.message = 'Unable to complete the request. Refresh to recover.'
        finally:
            self.busy = False
            self.save()
            self.emit()

def main():
    os.umask(0o077)
    backend = Backend()
    lock = open(backend.directory/'helper.lock', 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        return
    # A bounded queue keeps stdin reading separate from serialized API operations.
    # This avoids buffered readline/select races and lets deadlines fire without UI input.
    import queue
    import threading
    inbox = queue.Queue(maxsize=32)
    server = Server(backend.directory/'helper.sock', inbox)
    backend.publisher = server.publish
    backend.emit()
    backend.handle({'action':'init'})
    def read_input():
        for line in sys.stdin:
            try:
                command = json.loads(line)
                if isinstance(command, dict):
                    inbox.put(command)
            except ValueError:
                pass
        inbox.put(None)
    threading.Thread(target=read_input, daemon=True).start()
    try:
        while True:
            if backend.pomo.due():
                backend.handle({'action': 'pomo_tick'})
            try:
                command = inbox.get(timeout=1)
            except queue.Empty:
                continue
            if command is None:
                break
            backend.handle(command)
    finally:
        server.close()

if __name__ == '__main__':
    main()
