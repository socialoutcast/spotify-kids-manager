#!/usr/bin/env python3
"""
Remote Fix System for Spotify Kids Manager
Allows remote execution of repair commands through the web interface
"""

import os
import sys
import subprocess
import json
import hashlib
import time
from datetime import datetime

class RemoteFixer:
    def __init__(self):
        self.fixes = {
            'restart_player': {
                'name': 'Restart Player Service',
                'description': 'Restarts the Spotify player service',
                'commands': [
                    'systemctl restart spotify-player',
                    'systemctl status spotify-player'
                ]
            },
            'restart_admin': {
                'name': 'Restart Admin Panel',
                'description': 'Restarts the admin web panel',
                'commands': [
                    'systemctl restart spotify-admin',
                    'systemctl status spotify-admin'
                ]
            },
            'fix_permissions': {
                'name': 'Fix File Permissions',
                'description': 'Fixes ownership and permissions for all files',
                'commands': [
                    'chown -R spotify-kids:spotify-kids /opt/spotify-kids',
                    'chown -R spotify-kids:spotify-kids /var/log/spotify-kids',
                    'chmod 755 /opt/spotify-kids',
                    'chmod 755 /opt/spotify-kids/spotify_player.py',
                    'chmod 755 /opt/spotify-kids/web/app.py',
                    'chmod -R 755 /opt/spotify-kids/config',
                    'chown spotify-admin:spotify-admin /opt/spotify-kids/web/app.py'
                ]
            },
            'clear_cache': {
                'name': 'Clear Cache',
                'description': 'Clears all cache files',
                'commands': [
                    'rm -rf /opt/spotify-kids/config/.cache/*',
                    'rm -rf /tmp/spotify-*',
                    'rm -f /tmp/cookies.txt',
                    'rm -f /tmp/debug_cookies.txt'
                ]
            },
            'reinstall_packages': {
                'name': 'Reinstall Python Packages',
                'description': 'Reinstalls all required Python packages',
                'commands': [
                    'pip3 install --upgrade spotipy flask flask-cors pillow requests psutil'
                ]
            },
            'fix_spotify_auth': {
                'name': 'Reset Spotify Authentication',
                'description': 'Clears Spotify auth cache and tokens',
                'commands': [
                    'rm -rf /opt/spotify-kids/config/.cache',
                    'mkdir -p /opt/spotify-kids/config/.cache',
                    'chown spotify-kids:spotify-kids /opt/spotify-kids/config/.cache',
                    'chmod 755 /opt/spotify-kids/config/.cache'
                ]
            },
            'fix_display': {
                'name': 'Fix Display Issues',
                'description': 'Fixes X11 display and touchscreen issues',
                'commands': [
                    'export DISPLAY=:0',
                    'xhost +local:',
                    'systemctl restart getty@tty1'
                ]
            },
            'update_code': {
                'name': 'Update Code from GitHub',
                'description': 'Pulls latest code from GitHub',
                'commands': [
                    'cd /opt/spotify-kids && git pull',
                    'systemctl restart spotify-player',
                    'systemctl restart spotify-admin'
                ]
            },
            'enable_services': {
                'name': 'Enable All Services',
                'description': 'Enables all services to start on boot',
                'commands': [
                    'systemctl enable spotify-player',
                    'systemctl enable spotify-admin',
                    'systemctl daemon-reload'
                ]
            },
            'check_logs': {
                'name': 'Check Recent Errors',
                'description': 'Shows recent errors from all logs',
                'commands': [
                    'journalctl -u spotify-player -n 20 --no-pager | grep -i error || echo "No errors in player logs"',
                    'journalctl -u spotify-admin -n 20 --no-pager | grep -i error || echo "No errors in admin logs"',
                    'tail -n 20 /var/log/spotify-kids/player.log 2>/dev/null | grep -i error || echo "No errors in player.log"'
                ]
            },
            'test_spotify_api': {
                'name': 'Test Spotify API Connection',
                'description': 'Tests if Spotify API credentials are working',
                'commands': [
                    'python3 -c "import spotipy; from spotipy.oauth2 import SpotifyClientCredentials; import json; config = json.load(open(\'/opt/spotify-kids/config/spotify_config.json\')); sp = spotipy.Spotify(client_credentials_manager=SpotifyClientCredentials(client_id=config[\'client_id\'], client_secret=config[\'client_secret\'])); print(\'API Working:\', sp.search(q=\'test\', limit=1)[\'tracks\'][\'total\'] > 0)"'
                ]
            },
            'kill_stuck_processes': {
                'name': 'Kill Stuck Processes',
                'description': 'Kills any stuck Python or Chromium processes',
                'commands': [
                    'pkill -9 -f spotify_player.py || true',
                    'pkill -9 -f "python.*app.py" || true',
                    'pkill -9 chromium || true',
                    'sleep 2',
                    'systemctl start spotify-player',
                    'systemctl start spotify-admin'
                ]
            },
            'reset_admin_password': {
                'name': 'Reset Admin Password',
                'description': 'Resets admin password to default (changeme)',
                'commands': [
                    'python3 -c "import json; config = json.load(open(\'/opt/spotify-kids/config/config.json\')); from werkzeug.security import generate_password_hash; config[\'admin_pass\'] = generate_password_hash(\'changeme\'); json.dump(config, open(\'/opt/spotify-kids/config/config.json\', \'w\'), indent=2); print(\'Password reset to: changeme\')"'
                ]
            },
            'install_missing_deps': {
                'name': 'Install Missing Dependencies',
                'description': 'Installs any missing system dependencies',
                'commands': [
                    'apt-get update',
                    'apt-get install -y python3-pip python3-tk python3-pil python3-pil.imagetk chromium-browser xinit x11-xserver-utils'
                ]
            },
            'rebuild_services': {
                'name': 'Rebuild Service Files',
                'description': 'Recreates systemd service files',
                'commands': [
                    '''cat > /etc/systemd/system/spotify-player.service << 'EOF'
[Unit]
Description=Spotify Kids Player
After=network.target

[Service]
Type=simple
User=spotify-kids
Environment="DISPLAY=:0"
Environment="HOME=/home/spotify-kids"
WorkingDirectory=/opt/spotify-kids
ExecStart=/usr/bin/python3 /opt/spotify-kids/spotify_player.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF''',
                    '''cat > /etc/systemd/system/spotify-admin.service << 'EOF'
[Unit]
Description=Spotify Kids Admin Panel
After=network.target

[Service]
Type=simple
User=spotify-admin
WorkingDirectory=/opt/spotify-kids/web
ExecStart=/usr/bin/python3 /opt/spotify-kids/web/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF''',
                    'systemctl daemon-reload',
                    'systemctl restart spotify-player',
                    'systemctl restart spotify-admin'
                ]
            }
        }
    
    def run_fix(self, fix_id, verbose=True):
        """Run a specific fix"""
        if fix_id not in self.fixes:
            return {
                'success': False,
                'error': f'Unknown fix: {fix_id}',
                'available_fixes': list(self.fixes.keys())
            }
        
        fix = self.fixes[fix_id]
        results = {
            'fix_id': fix_id,
            'name': fix['name'],
            'description': fix['description'],
            'timestamp': datetime.now().isoformat(),
            'commands': [],
            'success': True
        }
        
        for cmd in fix['commands']:
            cmd_result = {
                'command': cmd if verbose else cmd[:50] + '...',
                'stdout': '',
                'stderr': '',
                'returncode': 0
            }
            
            try:
                # Handle multi-line commands
                if '\n' in cmd:
                    # It's a script, write to temp file and execute
                    import tempfile
                    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
                        f.write(cmd)
                        temp_script = f.name
                    
                    result = subprocess.run(['bash', temp_script], 
                                          capture_output=True, text=True, 
                                          timeout=30)
                    os.unlink(temp_script)
                else:
                    # Regular command
                    result = subprocess.run(cmd, shell=True, 
                                          capture_output=True, text=True, 
                                          timeout=30)
                
                cmd_result['stdout'] = result.stdout[-500:] if len(result.stdout) > 500 else result.stdout
                cmd_result['stderr'] = result.stderr[-500:] if len(result.stderr) > 500 else result.stderr
                cmd_result['returncode'] = result.returncode
                
                if result.returncode != 0 and 'true' not in cmd:
                    results['success'] = False
                    
            except subprocess.TimeoutExpired:
                cmd_result['stderr'] = 'Command timed out'
                cmd_result['returncode'] = -1
                results['success'] = False
            except Exception as e:
                cmd_result['stderr'] = str(e)
                cmd_result['returncode'] = -1
                results['success'] = False
            
            results['commands'].append(cmd_result)
        
        return results
    
    def run_custom_command(self, command, timeout=10):
        """Run a custom command (with restrictions)"""
        # Security: Restrict dangerous commands
        dangerous = ['rm -rf /', 'dd if=', 'mkfs', 'format', ':(){ :|:& };:']
        for danger in dangerous:
            if danger in command:
                return {
                    'success': False,
                    'error': 'Command contains dangerous pattern',
                    'command': command
                }
        
        try:
            result = subprocess.run(command, shell=True, 
                                  capture_output=True, text=True, 
                                  timeout=timeout)
            
            return {
                'success': result.returncode == 0,
                'command': command,
                'stdout': result.stdout[-1000:] if len(result.stdout) > 1000 else result.stdout,
                'stderr': result.stderr[-1000:] if len(result.stderr) > 1000 else result.stderr,
                'returncode': result.returncode
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'command': command,
                'error': f'Command timed out after {timeout} seconds'
            }
        except Exception as e:
            return {
                'success': False,
                'command': command,
                'error': str(e)
            }
    
    def get_available_fixes(self):
        """Get list of available fixes"""
        return {
            fix_id: {
                'name': fix['name'],
                'description': fix['description']
            }
            for fix_id, fix in self.fixes.items()
        }

if __name__ == '__main__':
    fixer = RemoteFixer()
    
    if len(sys.argv) > 1:
        fix_id = sys.argv[1]
        print(f"Running fix: {fix_id}")
        result = fixer.run_fix(fix_id)
        print(json.dumps(result, indent=2))
    else:
        print("Available fixes:")
        for fix_id, info in fixer.get_available_fixes().items():
            print(f"  {fix_id}: {info['name']}")
            print(f"    {info['description']}")