import re
import socket
import time
from typing import Optional

# MemcachedClient and MemcachedStats taken and modified from:
# https://github.com/czanoli/ETH-Cloud-Computing-Architectures-2024/blob/master/scheduler.py

# hyperparameters
poll_interval = 0.10 # 100ms
max_qps_one_core = 29_000
max_cpu_threshold = 45 # out of 200

ONE_S_IN_NS = 1e9
ONE_S_IN_US = 1e6

class MemcachedClient:
    _client = None
    _buffer = b''
    _stat_regex = re.compile(r"STAT (.*) (.*)\r")

    def __init__(self, host='localhost', port=11211):
        self._host = host
        self._port = port

    @property
    def client(self):
        if self._client is None:
            self._client = socket.create_connection((self._host, self._port))
        return self._client

    def read_until(self, delim):
        while delim not in self._buffer:
            data = self.client.recv(1024)
            if not data: # socket closed
                return None
            self._buffer += data
        line,_,self._buffer = self._buffer.partition(delim)
        return line

    def command(self, cmd):
        self.client.send(("%s\n" % cmd).encode('ascii'))
        buf = self.read_until(b'END')
        assert(buf is not None)
        return buf.decode('ascii')

    def stats(self):
        return dict(self._stat_regex.findall(self.command('stats')))

class MemcachedStats:
    get_count = 0
    set_count = 0
    last_readings = []

    def __init__(self, host) -> None:
        self.client = MemcachedClient(host=host, port=11211)
        self.read()
        self.last_readings = []

    def read(self):
        stats = self.client.stats()
        curr_get_count = int(stats['cmd_get'])
        get_diff = curr_get_count - self.get_count
        self.get_count = curr_get_count
        self.last_readings.append((time.time_ns(), get_diff))
        self.cleanup()

    def cleanup(self):
        now = time.time_ns()
        delete_before = None
        for i, (t, _) in reversed(list(enumerate(self.last_readings))):
            if now - t > ONE_S_IN_NS:
                delete_before = i
                break

        if delete_before is not None:
            del self.last_readings[:delete_before]

    # queries received in the last count*10ms
    def last_measurements(self, count=10):
        total_get_after = 0
        summed = 0
        start = time.time_ns()
        end = 0
        for i, (t, g) in enumerate(reversed(self.last_readings)):
            if i >= count:
                break
            start = min(start, t)
            end = max(end, t)
            total_get_after += g
            summed += 1

        time_diff = abs(end-start)
        if time_diff == 0:
            return 0
        else:
            return int((total_get_after) / ((end-start)/ONE_S_IN_NS))

    def qps(self):
        return self.last_measurements(int(1/poll_interval))


if __name__ == "__main__":

    import sys
    if len(sys.argv) != 2:
        print("Usage: python scheduler.py <host>")
        sys.exit(1)
        
    host = sys.argv[1]
    stats = MemcachedStats(host=host)

    print("Scheduler started")
    from time import sleep

    for i in range(1000):
        start = time.time()
        stats.read()
        print(stats.qps(), flush=True)
        time.sleep(max(0, 0.1 - (time.time() - start)))