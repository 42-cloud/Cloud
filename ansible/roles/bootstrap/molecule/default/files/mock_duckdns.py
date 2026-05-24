import http.server
import urllib.parse
import logging

logging.basicConfig(filename='/tmp/mock.log', level=logging.INFO)


class MockDuckDNS(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        ok = (
            q.get('domains') == ['test-domain'] and
            q.get('token') == ['test-token']
        )
        body = b"OK" if ok else b"KO"
        logging.info("Request: %s -> %s", self.path, body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 8081), MockDuckDNS)
    server.serve_forever()