"""Persistent Pomodoro phases coordinated with acknowledged Toggl writes."""
import time

DURATIONS = {'focus': 25 * 60, 'short': 5 * 60, 'long': 15 * 60}
DEFAULT_SETTINGS = dict(focus_minutes=25, short_minutes=5, long_minutes=15, long_every=4)
LIMITS = dict(focus_minutes=180, short_minutes=60, long_minutes=120, long_every=12)

def settings(state):
    return dict(DEFAULT_SETTINGS, **state.get('settings', {}))

LABELS = {'focus': 'Focus', 'short': 'Short break', 'long': 'Long break'}

def initial():
    return dict(phase='focus', status='idle', completed=0, remaining=DURATIONS['focus'], deadline=0, entry_id=None)

def remaining(state, now):
    return max(0, state['deadline']-now) if state['status']=='running' else state['remaining']

def next_phase(state):
    return ('long' if state['completed'] % settings(state)['long_every'] == 0 else 'short') if state['phase']=='focus' else 'focus'

class Pomodoro:
    def __init__(self, backend):
        self.backend = backend

    @property
    def state(self):
        return self.backend.data.setdefault('pomodoro', initial())

    def duration(self, phase):
        return settings(self.state)[phase + '_minutes'] * 60

    def configure(self, values):
        if not isinstance(values, dict) or not values:
            self.fail('Enter Pomodoro settings.')
        for key, value in values.items():
            if key not in LIMITS or type(value) is not int or not 1 <= value <= LIMITS[key]:
                self.fail('Invalid Pomodoro setting.')
        p = self.state
        p['settings'] = dict(settings(p), **values)
        if p['status'] == 'idle':
            p['remaining'] = self.duration(p['phase'])
        self.backend.message = 'Pomodoro settings saved. Active and paused sessions keep their duration.'

    def fail(self, message):
        self.backend.fail(message)

    def start(self, command):
        b, p = self.backend, self.state
        if p['status'] in ('running', 'starting', 'stop_pending', 'review'):
            self.fail('Finish or reset the current Pomodoro before starting another.')
        if p['status'] == 'finished':
            p['phase'] = next_phase(p)
            p['remaining'] = self.duration(p['phase'])
            p['status'] = 'idle'
        if p['phase'] == 'focus':
            if p['status'] != 'paused':
                p['description'] = command.get('description', '')
                p['project_id'] = command.get('project_id')
                p['workspace'] = b.data.get('workspace')
            if p.get('workspace') != b.data.get('workspace'):
                self.fail('Return to the focus session’s workspace, or reset Pomodoro.')
            # Persist intent before a network request. A lost create response is never retried.
            previous = p['status']
            p['status'] = 'starting'
            b.save()
            try:
                b.mutate(dict(action='start', expected_id=command.get('expected_id'),
                              description=p['description'], project_id=p['project_id']))
            except Exception:
                p['status'] = 'review' if b.data.get('uncertain') else previous
                raise
            p['entry_id'] = b.data['current']['id']
            # Begin the countdown only after Toggl acknowledges creation.
        p['status'] = 'running'
        p['deadline'] = time.time()+p['remaining']
        b.message = LABELS[p['phase']] + ' started'

    def request_stop(self, target, now):
        p = self.state
        if p['status'] != 'stop_pending':
            p['stop_at'] = p['deadline'] if target == 'finished' else now
        p['remaining'] = remaining(p, now)
        p['status'] = 'stop_pending'
        p['target_status'] = target
        p['deadline'] = 0
        self.backend.save()
        self.finish_stop()

    def finish_stop(self):
        b, p = self.backend, self.state
        if p.get('entry_id'):
            # Fetch fresh state; never stop a timer started elsewhere.
            b.sync()
            current = b.data.get('current')
            if current and current['id'] == p['entry_id']:
                b.mutate(dict(action='stop', expected_id=p['entry_id'], stop_at=p.get('stop_at')), prechecked=True)
        p['entry_id'] = None
        target = p.pop('target_status', 'paused')
        p['status'] = target
        if target == 'finished':
            if p['phase'] == 'focus':
                p['completed'] += 1
            b.save()  # Persist completion before notifying; restarts cannot duplicate it.
            b.notify(LABELS[p['phase']] + ' complete', 'Ready for '+LABELS[next_phase(p)].lower()+'. Start it when you’re ready.')
        elif target == 'idle':
            p['remaining'] = self.duration(p['phase'])
        b.message = 'Pomodoro '+target

    def action(self, command):
        action = command['action']
        p = self.state
        now = time.time()
        if action == 'pomo_configure':
            self.configure(command.get('settings'))
        elif action == 'pomo_start':
            self.start(command)
        elif action == 'pomo_pause' and p['status'] == 'running':
            self.request_stop('paused', now)
        elif action == 'pomo_reset':
            if p.get('entry_id'):
                self.request_stop('idle', now)
            else:
                p.update(status='idle', remaining=self.duration(p['phase']), deadline=0)
        elif action == 'pomo_select':
            if p['status'] not in ('idle', 'finished'):
                self.fail('Reset the current Pomodoro before changing phases.')
            phase = command.get('phase')
            if phase in DURATIONS:
                p.update(phase=phase, status='idle', remaining=self.duration(phase), deadline=0)

    def reconcile(self):
        p, b = self.state, self.backend
        if p['status'] == 'review':
            b.message = 'Focus start needs review. Check the Toggl timer before resetting Pomodoro.'
        elif p['status'] == 'starting':
            p['status'] = 'review'
            b.message = 'Focus start was interrupted. Check the Toggl timer before resetting Pomodoro.'
        elif p['status'] == 'stop_pending':
            self.finish_stop()
        elif p['status'] == 'running' and p['phase'] == 'focus' and (b.data.get('current') or {}).get('id') != p.get('entry_id'):
            p.update(remaining=remaining(p,time.time()), status='paused', deadline=0, entry_id=None)
            b.message = 'Pomodoro paused: its Toggl entry was changed elsewhere.'

    def due(self):
        p = self.state
        return p['status'] == 'running' and remaining(p,time.time()) == 0

    def tick(self):
        if self.due():
            self.request_stop('finished', time.time())
