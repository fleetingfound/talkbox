import functools
import http.server
import socket
import sys

directory = sys.argv[1]
bind = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
family = socket.AF_INET6 if ":" in bind else socket.AF_INET
sock = socket.socket(family)
sock.bind((bind, 0))
port = sock.getsockname()[1]
print(port, flush=True)

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)


class Server(http.server.ThreadingHTTPServer):
    address_family = family

    def server_bind(self):
        self.socket = sock
        self.server_address = self.socket.getsockname()


Server((bind, 0), handler).serve_forever()
