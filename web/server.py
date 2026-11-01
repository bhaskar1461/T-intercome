#!/usr/bin/env python3
import http.server
import socketserver
import os
import mimetypes

PORT = int(os.environ.get("PORT", 8080))
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(WEB_DIR)

mimetypes.add_type("application/octet-stream", ".ipa")
mimetypes.add_type("text/html", ".html")
mimetypes.add_type("image/png", ".png")

class SplitBudsHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Serve SplitBudsPTT.ipa from the project root if requested
        if path.strip("/") == "SplitBudsPTT.ipa":
            ipa_path = os.path.join(PROJECT_ROOT, "SplitBudsPTT.ipa")
            if os.path.exists(ipa_path):
                return ipa_path
            # Check build artifacts fallback
            alt_path = os.path.join(WEB_DIR, "SplitBudsPTT.ipa")
            if os.path.exists(alt_path):
                return alt_path
        # Otherwise serve from web directory
        clean_path = path.split("?")[0].split("#")[0].strip("/")
        if not clean_path:
            clean_path = "index.html"
        return os.path.join(WEB_DIR, clean_path)

    def end_headers(self):
        # Allow CORS and caching headers
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

def run():
    with socketserver.TCPServer(("", PORT), SplitBudsHandler) as httpd:
        print(f"[*] SplitBuds PTT Container serving at http://0.0.0.0:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    run()

