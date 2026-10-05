import copy
import datetime as dt
import io
import json
import tempfile
import unittest
from unittest.mock import patch
from backend import Backend, Failure
from pomodoro import DURATIONS, remaining, next_phase

class PomodoroTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.now=1791172800
        self.clock=patch('time.time',side_effect=lambda:self.now); self.clock.start(); self.addCleanup(self.clock.stop)
        self.b=Backend(self.tmp.name); self.b.token='test'; self.b.online=True
        self.b.data=dict(workspace=1,user_id=7,workspaces=[dict(id=1,name='Personal')],projects=[],recent=[],catalog_version=3,catalog_at=self.now,current=None)
        self.remote=None; self.calls=[]; self.notices=[]; self.counter=0
        self.b.notify=lambda *args:self.notices.append(args)
        def request(method,path,body=None):
            self.calls.append((method,path,body))
            if method=='GET': return copy.deepcopy(self.remote)
            if method=='POST':
                self.counter+=1
                self.remote=dict(body,id=self.counter,stop=None,start=dt.datetime.fromtimestamp(self.now,dt.timezone.utc).isoformat())
                return copy.deepcopy(self.remote)
            if method in ('PUT','PATCH'):
                stopped=dict(self.remote,**(body or {}))
                if method=='PATCH': stopped.update(stop=dt.datetime.fromtimestamp(self.now,dt.timezone.utc).isoformat(),duration=1)
                self.remote=None
                return stopped
            raise AssertionError(method)
        self.b.request=request

    def start(self):
        self.b.pomo.action(dict(action='pomo_start',expected_id=(self.b.data.get('current') or {}).get('id'),description='Study'))

    def test_start_creates_tracked_focus(self):
        self.start(); p=self.b.pomo.state
        self.assertEqual(p['entry_id'],self.remote['id']); self.assertEqual(p['status'],'running')
        self.assertEqual(remaining(p,self.now),1500)

    def test_pause_stops_and_resume_creates_new_segment(self):
        self.start(); first=self.remote['id']; self.now+=60
        self.b.pomo.action(dict(action='pomo_pause'))
        self.assertIsNone(self.remote); self.assertEqual(self.b.pomo.state['remaining'],1440)
        self.now+=1000; self.start()
        self.assertNotEqual(self.remote['id'],first); self.assertEqual(remaining(self.b.pomo.state,self.now),1440)
        self.assertEqual(self.b.pomo.state['completed'],0)

    def test_sleep_completion_stops_at_deadline_not_wakeup(self):
        self.start(); deadline=self.b.pomo.state['deadline']; self.now+=9000
        self.b.pomo.tick(); p=self.b.pomo.state
        self.assertEqual(p['status'],'finished'); self.assertEqual(p['completed'],1); self.assertIsNone(self.remote)
        put=[c for c in self.calls if c[0]=='PUT'][-1][2]
        self.assertEqual(put['duration'],1500)
        self.assertEqual(dt.datetime.fromisoformat(put['stop'].replace('Z','+00:00')).timestamp(),deadline)
        self.b.pomo.tick(); self.assertEqual(len(self.notices),1)

    def test_breaks_make_no_api_calls_and_wait_for_start(self):
        self.start(); self.now+=1500; self.b.pomo.tick(); count=len(self.calls)
        self.assertEqual(next_phase(self.b.pomo.state),'short'); self.assertIsNone(self.remote)
        self.start(); self.assertEqual(self.b.pomo.state['phase'],'short')
        self.assertEqual(len(self.calls),count)
        self.now+=300; self.b.pomo.tick(); self.assertEqual(len(self.calls),count)
        self.assertEqual(self.b.pomo.state['status'],'finished')

    def test_four_focus_sessions_select_long_break(self):
        for n in range(4):
            self.b.pomo.action(dict(action='pomo_select',phase='focus')); self.start()
            self.now+=1500; self.b.pomo.tick()
        self.assertEqual(self.b.pomo.state['completed'],4)
        self.assertEqual(next_phase(self.b.pomo.state),'long')
        self.start(); self.assertEqual(remaining(self.b.pomo.state,self.now),900)

    def test_changed_remote_entry_is_never_stopped(self):
        self.start(); self.remote=dict(self.remote,id=999); self.now+=1500
        self.b.pomo.tick()
        self.assertEqual(self.remote['id'],999)
        self.assertFalse(any(c[0]=='PUT' for c in self.calls))

    def test_external_stop_pauses_on_refresh(self):
        self.start(); self.now+=90; self.remote=None
        self.b.sync(); self.b.pomo.reconcile()
        self.assertEqual(self.b.pomo.state['status'],'paused')
        self.assertEqual(self.b.pomo.state['remaining'],1410)

    def test_lost_stop_response_reconciles_without_second_write(self):
        self.start(); original=self.b.request
        def uncertain(method,path,body=None):
            result=original(method,path,body)
            if method=='PUT': raise Failure('lost response')
            return result
        self.b.request=uncertain; self.now+=1500
        with self.assertRaises(Failure): self.b.pomo.tick()
        self.assertEqual(self.b.pomo.state['status'],'stop_pending')
        self.b.pomo.reconcile()
        self.assertEqual(self.b.pomo.state['completed'],1)
        self.assertEqual(len([c for c in self.calls if c[0]=='PUT']),1)

    def test_lost_start_requires_review_and_never_retries(self):
        original=self.b.request
        def uncertain(method,path,body=None):
            result=original(method,path,body)
            if method=='POST': raise Failure('lost response')
            return result
        self.b.request=uncertain
        with self.assertRaises(Failure): self.start()
        self.assertEqual(self.b.pomo.state['status'],'review')
        with self.assertRaises(Failure): self.start()
        self.assertEqual(len([c for c in self.calls if c[0]=='POST']),1)

    def test_reset_stops_known_entry_without_counting_completion(self):
        self.start(); self.now+=60; self.b.pomo.action(dict(action='pomo_reset'))
        self.assertIsNone(self.remote); self.assertEqual(self.b.pomo.state['status'],'idle')
        self.assertEqual(self.b.pomo.state['completed'],0)

    def test_saved_deadline_survives_reload(self):
        self.start(); self.b.save(); restored=Backend(self.tmp.name)
        self.now+=80; self.assertEqual(remaining(restored.pomo.state,self.now),1420)

    def test_manual_changes_are_blocked_during_focus(self):
        self.start(); count=len(self.calls)
        with patch('sys.stdout',new=io.StringIO()): self.b.handle(dict(action='stop',expected_id=self.remote['id']))
        self.assertEqual(len(self.calls),count); self.assertIsNotNone(self.remote)

    def test_stop_failure_preserves_deadline_for_retry(self):
        self.start(); deadline=self.b.pomo.state['deadline']; original=self.b.request
        self.b.request=lambda *args,**kwargs: (_ for _ in ()).throw(Failure('offline'))
        self.now+=1500
        with self.assertRaises(Failure): self.b.pomo.tick()
        self.assertFalse(self.b.pomo.due()); self.assertEqual(self.b.pomo.state['stop_at'],deadline)
        self.b.request=original; self.now+=600; self.b.pomo.reconcile()
        put=[c for c in self.calls if c[0]=='PUT'][-1][2]
        self.assertEqual(put['duration'],1500)

if __name__=='__main__': unittest.main()
