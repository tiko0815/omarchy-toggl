import json
from pathlib import Path
import queue
import socket
import tempfile
import time
import unittest
from local_ipc import Server


class LocalTransportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / 'helper.sock'
        self.inbox = queue.Queue(maxsize=32)
        self.server = Server(self.path, self.inbox)
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(self.server.close)

    def connect(self):
        client = socket.socket(socket.AF_UNIX)
        client.settimeout(2)
        client.connect(str(self.path))
        self.addCleanup(client.close)
        stream = client.makefile('rb')
        self.addCleanup(stream.close)
        return client, stream

    def test_initial_state_updates_and_commands_share_one_backend(self):
        self.server.publish(b'{"connected":true}\n')
        first, first_stream = self.connect()
        _, second_stream = self.connect()
        self.assertTrue(json.loads(first_stream.readline())['connected'])
        self.assertTrue(json.loads(second_stream.readline())['connected'])
        first.sendall(b'{"action":"connect","token":"test-only"}\n')
        self.assertEqual(self.inbox.get(timeout=2), {'action': 'connect', 'token': 'test-only'})
        self.server.publish(b'{"connected":false}\n')
        self.assertFalse(json.loads(first_stream.readline())['connected'])
        self.assertFalse(json.loads(second_stream.readline())['connected'])
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_bad_input_does_not_block_valid_commands(self):
        client, _ = self.connect()
        client.sendall(b'broken\n[]\n{"action":null}\n{"action":"init"}\n')
        self.assertEqual(self.inbox.get(timeout=2), {'action': 'init'})
        self.assertTrue(self.inbox.empty())

    def test_reconnecting_receives_latest_state(self):
        self.server.publish(b'{"connected":true}\n')
        client, stream = self.connect()
        stream.readline()
        client.shutdown(socket.SHUT_RDWR)
        stream.close()
        client.close()
        self.server.publish(b'{"connected":false}\n')
        _, stream = self.connect()
        self.assertFalse(json.loads(stream.readline())['connected'])

    def test_slow_reader_does_not_block_publishing(self):
        self.connect()
        started = time.monotonic()
        for _ in range(1000):
            self.server.publish(b'x' * 4096 + b'\n')
        self.assertLess(time.monotonic() - started, 1)


if __name__ == '__main__':
    unittest.main()
