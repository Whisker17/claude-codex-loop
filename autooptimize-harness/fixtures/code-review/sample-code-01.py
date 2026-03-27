"""Thread-safe PostgreSQL connection pool."""
import threading
import time
from queue import Queue, Empty
from contextlib import contextmanager


class ConnectionPool:
    def __init__(self, dsn, min_size=2, max_size=10, idle_timeout=300, connect_timeout=30):
        self.dsn = dsn
        self.min_size = min_size
        self.max_size = max_size
        self.idle_timeout = idle_timeout
        self.connect_timeout = connect_timeout

        self._pool = Queue()
        self._size = 0
        self._lock = threading.Lock()

        # Pre-create min_size connections
        for _ in range(min_size):
            conn = self._create_connection()
            self._pool.put((conn, time.monotonic()))
            self._size += 1

        # Start idle cleaner
        self._cleaner = threading.Thread(target=self._clean_idle, daemon=True)
        self._cleaner.start()

    def _create_connection(self):
        import psycopg2
        return psycopg2.connect(self.dsn)

    def _validate(self, conn):
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
            return True
        except Exception:
            return False

    def get_connection(self):
        # Try to get from pool first
        while True:
            try:
                conn, last_used = self._pool.get_nowait()
                # Check idle timeout
                if time.monotonic() - last_used > self.idle_timeout:
                    conn.close()
                    with self._lock:
                        self._size -= 1
                    continue
                # Validate
                if not self._validate(conn):
                    conn.close()
                    with self._lock:
                        self._size -= 1
                    continue
                return conn
            except Empty:
                break

        # Pool empty — try to create new connection
        with self._lock:
            if self._size < self.max_size:
                self._size += 1
                return self._create_connection()

        # At max size — wait for a connection to be returned
        try:
            conn, last_used = self._pool.get(timeout=self.connect_timeout)
            if self._validate(conn):
                return conn
            conn.close()
            with self._lock:
                self._size -= 1
            return self.get_connection()  # recurse
        except Empty:
            raise TimeoutError(f"Could not get connection within {self.connect_timeout}s")

    def release_connection(self, conn):
        if conn.closed:
            with self._lock:
                self._size -= 1
            return
        self._pool.put((conn, time.monotonic()))

    @contextmanager
    def connection(self):
        conn = self.get_connection()
        try:
            yield conn
        except Exception:
            conn.rollback()
            raise
        finally:
            self.release_connection(conn)

    def _clean_idle(self):
        while True:
            time.sleep(60)
            cleaned = []
            while not self._pool.empty():
                try:
                    conn, last_used = self._pool.get_nowait()
                    if time.monotonic() - last_used > self.idle_timeout:
                        conn.close()
                        with self._lock:
                            self._size -= 1
                    else:
                        cleaned.append((conn, last_used))
                except Empty:
                    break
            for item in cleaned:
                self._pool.put(item)

    def close_all(self):
        while not self._pool.empty():
            try:
                conn, _ = self._pool.get_nowait()
                conn.close()
            except Empty:
                break
        with self._lock:
            self._size = 0
