#!/usr/bin/env python3
"""
Simple callback server for Spotify OAuth
Runs on port 8888 to handle the OAuth callback
"""

import os
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from spotipy.oauth2 import SpotifyOAuth

# Configuration
CONFIG_DIR = os.environ.get('SPOTIFY_CONFIG_DIR', '/opt/spotify-kids/config')
CACHE_DIR = os.path.join(CONFIG_DIR, '.cache')
CONFIG_FILE = os.path.join(CONFIG_DIR, 'spotify_config.json')

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('CallbackServer')

class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle the OAuth callback"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/callback':
            # Extract the authorization code
            query_params = parse_qs(parsed_path.query)
            
            if 'code' in query_params:
                auth_code = query_params['code'][0]
                logger.info(f"Received authorization code: {auth_code[:20]}...")
                
                # Try to complete the authentication
                success = self.complete_auth(auth_code)
                
                if success:
                    # Send success response
                    self.send_response(200)
                    self.send_header('Content-type', 'text/html')
                    self.end_headers()
                    
                    html = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <title>Spotify Authentication Successful</title>
                        <style>
                            body {
                                font-family: Arial, sans-serif;
                                display: flex;
                                justify-content: center;
                                align-items: center;
                                height: 100vh;
                                margin: 0;
                                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                            }
                            .container {
                                text-align: center;
                                background: white;
                                padding: 40px;
                                border-radius: 10px;
                                box-shadow: 0 10px 40px rgba(0,0,0,0.2);
                            }
                            h1 { color: #1db954; }
                            p { color: #666; margin: 20px 0; }
                            .code-box {
                                background: #f0f0f0;
                                padding: 15px;
                                border-radius: 5px;
                                font-family: monospace;
                                margin: 20px 0;
                                word-break: break-all;
                            }
                        </style>
                    </head>
                    <body>
                        <div class="container">
                            <h1>✅ Authentication Successful!</h1>
                            <p>Spotify has been successfully authenticated.</p>
                            <p>You can now close this window and return to the admin panel.</p>
                            <p style="margin-top: 30px;">
                                <a href="/" style="background: #1db954; color: white; padding: 10px 20px; border-radius: 5px; text-decoration: none;">
                                    Return to Admin Panel
                                </a>
                            </p>
                        </div>
                    </body>
                    </html>
                    """
                    self.wfile.write(html.encode())
                else:
                    # Send error response
                    self.send_error(500, "Failed to complete authentication")
            
            elif 'error' in query_params:
                error = query_params['error'][0]
                logger.error(f"OAuth error: {error}")
                self.send_error(400, f"Authentication failed: {error}")
            else:
                self.send_error(400, "No authorization code received")
        else:
            self.send_error(404, "Not found")
    
    def complete_auth(self, auth_code):
        """Complete the OAuth flow with the authorization code"""
        try:
            # Load config
            if not os.path.exists(CONFIG_FILE):
                logger.error("Config file not found")
                return False
            
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            
            # Create cache directory
            os.makedirs(CACHE_DIR, exist_ok=True)
            cache_file = os.path.join(CACHE_DIR, 'token.cache')
            
            # Create SpotifyOAuth instance
            auth_manager = SpotifyOAuth(
                client_id=config['client_id'],
                client_secret=config['client_secret'],
                redirect_uri=config.get('redirect_uri', 'http://localhost:8888/callback'),
                scope='user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read streaming',
                cache_path=cache_file,
                open_browser=False
            )
            
            # Exchange code for token
            token_info = auth_manager.get_access_token(auth_code, as_dict=True)
            
            if token_info:
                logger.info("Successfully obtained access token")
                # The token is automatically cached by SpotifyOAuth
                return True
            else:
                logger.error("Failed to obtain access token")
                return False
                
        except Exception as e:
            logger.error(f"Error completing auth: {e}")
            return False
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(format % args)

def main():
    """Run the callback server"""
    port = 8888
    server = HTTPServer(('localhost', port), CallbackHandler)
    logger.info(f"Callback server listening on http://localhost:{port}/callback")
    logger.info("Waiting for OAuth callback...")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server stopped")
        server.shutdown()

if __name__ == '__main__':
    main()