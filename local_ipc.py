"""Private JSON-line transport between the bar widget and its single helper."""
import json
import os
from pathlib import Path
import queue
import socket
import sys
import threading


def socket_path():
    return Path(os.getenv('XDG_STATE_HOME', Path.home() / '.local/state')) / 'omarchy/toggl/helper.sock'


class Server:
    def __init__(self, path, inbox):
        self.path = Path(path)
        self.inbox = inbox
        self.lock = threading.Lock()
        self.clients = set()
        self.latest = None
        self.closed = threading.Event()
        self.socket = socket.socket(socket.AF_UNIX)
        self.path.unlink(missing_ok=True)
        self.socket.bind(str(self.path))
        self.path.chmod(0o600)
        self.socket.listen(8)
        self.socket.settimeout(0.2)
        threading.Thread(target=self.accept, daemon=True).start()

    @staticmethod
    def offer(outbox, data):
        # A slow/hidden widget must never delay API operations or Pomodoro stops.
        try:
            outbox.get_nowait()
        except queue.Empty:
            pass
        outbox.put_nowait(data)

    def publish(self, data):
        with self.lock:
            self.latest = data
            for _, outbox in self.clients:
                self.offer(outbox, data)

    def accept(self):
        while not self.closed.is_set():
            try:
                connection, _ = self.socket.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            outbox = queue.Queue(maxsize=1)
            with self.lock:
                if len(self.clients) >= 8:
                    connection.close()
                    continue
                self.clients.add((connection, outbox))
                if self.latest is not None:
                    self.offer(outbox, self.latest)
            threading.Thread(target=self.read, args=(connection, outbox), daemon=True).start()
            threading.Thread(target=self.write, args=(connection, outbox), daemon=True).start()

    def read(self, connection, outbox):
        try:
            with connection.makefile('rb') as stream:
                while line := stream.readline(65537):
                    if len(line) > 65536:
                        break
                    try:
                        command = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(command, dict) and isinstance(command.get('action'), str):
                        self.inbox.put(command, timeout=1)
        except (OSError, queue.Full):
            pass
        finally:
            with self.lock:
                self.clients.discard((connection, outbox))
                self.offer(outbox, None)
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()

    def write(self, connection, outbox):
        try:
            while (data := outbox.get()) is not None:
                connection.sendall(data)
        except OSError:
            pass

    def close(self):
        self.closed.set()
        self.socket.close()
        with self.lock:
            for connection, outbox in self.clients:
                self.offer(outbox, None)
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        self.path.unlink(missing_ok=True)


def client():
    # Credentials travel only over stdin and the owner-only Unix socket.
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(str(socket_path()))
        def forward():
            try:
                for line in sys.stdin.buffer:
                    connection.sendall(line)
            except OSError:
                pass
            finally:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        threading.Thread(target=forward, daemon=True).start()
        with connection.makefile('rb') as stream:
            for line in stream:
                sys.stdout.buffer.write(line)
                sys.stdout.buffer.flush()


if __name__ == '__main__':
    try:
        client()
    except (OSError, BrokenPipeError):
        sys.exit(1)
