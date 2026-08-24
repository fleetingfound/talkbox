import functools
import http.server
import socket
import sys

directory = sys.argv[1]
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
port = sock.getsockname()[1]
print(port, flush=True)

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)


class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        self.socket = sock
        self.server_address = self.socket.getsockname()


Server(("127.0.0.1", 0), handler).serve_forever()
