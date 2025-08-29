#!/usr/bin/env python3
"""
COMPLETE SYSTEM DIAGNOSTICS FOR SPOTIFY KIDS MANAGER
This checks EVERYTHING and creates a web-accessible report
"""

import os
import sys
import json
import subprocess
import time
import socket
import traceback
import psutil
from datetime import datetime
import hashlib
import re

class SpotifyKidsDiagnostics:
    def __init__(self):
        self.report = {
            'timestamp': datetime.now().isoformat(),
            'hostname': socket.gethostname(),
            'summary': {'total_issues': 0, 'critical': 0, 'warnings': 0, 'info': 0},
            'boot_splash': {},
            'player_app': {},
            'admin_panel': {},
            'system': {},
            'services': {},
            'network': {},
            'files': {},
            'permissions': {},
            'processes': {},
            'logs': {},
            'javascript': {},
            'tests': {}
        }
        self.issues = []
        
    def add_issue(self, severity, component, message, details=None):
        """Add an issue to the report"""
        issue = {
            'severity': severity,  # critical, warning, info
            'component': component,
            'message': message,
            'details': details or {}
        }
        self.issues.append(issue)
        self.report['summary']['total_issues'] += 1
        self.report['summary'][severity] += 1
        
    def run_command(self, cmd, timeout=10):
        """Run a command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            return result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", f"Command timed out after {timeout}s", -1
        except Exception as e:
            return "", str(e), -1
    
    def check_boot_splash(self):
        """Check Plymouth boot splash configuration"""
        print("🔍 Checking boot splash...")
        
        # Check if Plymouth is installed
        stdout, stderr, code = self.run_command("which plymouth")
        if code != 0:
            self.add_issue('warning', 'boot_splash', 'Plymouth not installed')
            self.report['boot_splash']['installed'] = False
            return
        
        self.report['boot_splash']['installed'] = True
        
        # Check current theme
        stdout, stderr, code = self.run_command("plymouth-set-default-theme")
        self.report['boot_splash']['current_theme'] = stdout.strip()
        
        # Check if spotify theme exists
        theme_path = '/usr/share/plymouth/themes/spotify-kids'
        if os.path.exists(theme_path):
            self.report['boot_splash']['spotify_theme_exists'] = True
            # Check theme files
            required_files = ['spotify-kids.plymouth', 'spotify-kids.script', 'logo.png']
            for file in required_files:
                filepath = os.path.join(theme_path, file)
                if not os.path.exists(filepath):
                    self.add_issue('warning', 'boot_splash', f'Missing theme file: {file}')
        else:
            self.report['boot_splash']['spotify_theme_exists'] = False
            self.add_issue('info', 'boot_splash', 'Spotify Kids theme not installed')
        
        # Check Plymouth config
        config_file = '/etc/plymouth/plymouthd.conf'
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                self.report['boot_splash']['config'] = f.read()
        
        # Check if splash is enabled in kernel cmdline
        cmdline_file = '/proc/cmdline'
        if os.path.exists(cmdline_file):
            with open(cmdline_file, 'r') as f:
                cmdline = f.read()
                self.report['boot_splash']['splash_enabled'] = 'splash' in cmdline
                self.report['boot_splash']['quiet_boot'] = 'quiet' in cmdline
    
    def check_player_app(self):
        """Check the main Spotify player application"""
        print("🎵 Checking player app...")
        
        # Check if player file exists
        player_file = '/opt/spotify-kids/spotify_player.py'
        if not os.path.exists(player_file):
            self.add_issue('critical', 'player_app', 'Player file not found', {'path': player_file})
            self.report['player_app']['exists'] = False
            return
        
        self.report['player_app']['exists'] = True
        
        # Check file permissions
        stat = os.stat(player_file)
        self.report['player_app']['permissions'] = oct(stat.st_mode)[-3:]
        
        # Check if player service is running
        stdout, stderr, code = self.run_command("systemctl is-active spotify-player")
        self.report['player_app']['service_status'] = stdout.strip()
        
        if stdout.strip() != 'active':
            self.add_issue('critical', 'player_app', 'Player service not running')
            
            # Get service logs
            stdout, stderr, code = self.run_command("journalctl -u spotify-player -n 50 --no-pager")
            self.report['player_app']['service_logs'] = stdout.split('\n')[-20:]  # Last 20 lines
        
        # Check if player process is running
        player_running = False
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                cmdline = ' '.join(proc.info.get('cmdline', []))
                if 'spotify_player.py' in cmdline:
                    player_running = True
                    self.report['player_app']['process'] = {
                        'pid': proc.info['pid'],
                        'cpu_percent': proc.cpu_percent(),
                        'memory_mb': proc.memory_info().rss / 1024 / 1024
                    }
                    break
            except:
                pass
        
        self.report['player_app']['process_running'] = player_running
        
        # Check Spotify API configuration
        spotify_config_file = '/opt/spotify-kids/config/spotify_config.json'
        if os.path.exists(spotify_config_file):
            try:
                with open(spotify_config_file, 'r') as f:
                    spotify_config = json.load(f)
                    self.report['player_app']['spotify_configured'] = bool(spotify_config.get('client_id'))
                    
                    # Test Spotify API connection
                    if spotify_config.get('client_id') and spotify_config.get('client_secret'):
                        # Try to get a token
                        import base64
                        import requests
                        
                        auth_str = f"{spotify_config['client_id']}:{spotify_config['client_secret']}"
                        auth_bytes = auth_str.encode("utf-8")
                        auth_base64 = str(base64.b64encode(auth_bytes), "utf-8")
                        
                        try:
                            response = requests.post(
                                "https://accounts.spotify.com/api/token",
                                headers={
                                    "Authorization": f"Basic {auth_base64}",
                                    "Content-Type": "application/x-www-form-urlencoded"
                                },
                                data={"grant_type": "client_credentials"},
                                timeout=5
                            )
                            
                            if response.status_code == 200:
                                self.report['player_app']['spotify_api_working'] = True
                            else:
                                self.report['player_app']['spotify_api_working'] = False
                                self.add_issue('critical', 'player_app', 'Spotify API authentication failed')
                        except:
                            self.report['player_app']['spotify_api_working'] = False
                            self.add_issue('warning', 'player_app', 'Could not test Spotify API')
            except Exception as e:
                self.add_issue('warning', 'player_app', f'Error reading Spotify config: {str(e)}')
        else:
            self.report['player_app']['spotify_configured'] = False
            self.add_issue('critical', 'player_app', 'Spotify not configured')
    
    def check_admin_panel(self):
        """Check the admin web panel"""
        print("🌐 Checking admin panel...")
        
        # Check if admin app exists
        admin_file = '/opt/spotify-kids/web/app.py'
        if not os.path.exists(admin_file):
            self.add_issue('critical', 'admin_panel', 'Admin app file not found')
            self.report['admin_panel']['exists'] = False
            return
        
        self.report['admin_panel']['exists'] = True
        
        # Check if service is running
        stdout, stderr, code = self.run_command("systemctl is-active spotify-admin")
        self.report['admin_panel']['service_status'] = stdout.strip()
        
        # Check if web server is responding
        import requests
        try:
            response = requests.get('http://localhost:8080', timeout=5)
            self.report['admin_panel']['web_responding'] = True
            self.report['admin_panel']['response_code'] = response.status_code
            
            # Parse the HTML to check for JavaScript errors
            html = response.text
            lines = html.split('\n')
            self.report['admin_panel']['html_lines'] = len(lines)
            
            # Check for specific functions in JavaScript
            functions_to_check = [
                'saveSpotifyConfig', 'testSpotifyConfig', 'restartServices',
                'connectBluetooth', 'disconnectBluetooth', 'removeBluetooth',
                'saveAdminSettings', 'saveContentFilter', 'login', 'logout'
            ]
            
            functions_found = []
            functions_missing = []
            
            for func in functions_to_check:
                if f'function {func}' in html:
                    functions_found.append(func)
                else:
                    # Check if function is called but not defined
                    if f'{func}(' in html:
                        functions_missing.append(func)
                        self.add_issue('critical', 'admin_panel', f'Function {func} called but not defined')
            
            self.report['admin_panel']['javascript'] = {
                'functions_defined': functions_found,
                'functions_missing': functions_missing
            }
            
            # Check line 808 specifically (where error was reported)
            if len(lines) > 808:
                self.report['admin_panel']['line_808'] = lines[807][:200]
                
                # Check for syntax errors around line 808
                for i in range(max(0, 805), min(len(lines), 812)):
                    line = lines[i]
                    # Check for common syntax errors
                    if line.count('"') % 2 != 0:
                        self.add_issue('critical', 'admin_panel', f'Unmatched quotes at line {i+1}')
                    if '{{' in line and '}}' not in line:
                        self.add_issue('warning', 'admin_panel', f'Unclosed template variable at line {i+1}')
            
            # Test each panel/endpoint
            test_endpoints = [
                '/api/logs/player',
                '/api/logs/admin',
                '/api/logs/system',
                '/api/player/status',
                '/api/bluetooth/status',
                '/diagnostics'
            ]
            
            for endpoint in test_endpoints:
                try:
                    response = requests.get(f'http://localhost:8080{endpoint}', timeout=3)
                    self.report['admin_panel'][f'endpoint_{endpoint}'] = response.status_code
                    if response.status_code != 200 and response.status_code != 401:
                        self.add_issue('warning', 'admin_panel', f'Endpoint {endpoint} returned {response.status_code}')
                except Exception as e:
                    self.report['admin_panel'][f'endpoint_{endpoint}'] = 'error'
                    self.add_issue('warning', 'admin_panel', f'Endpoint {endpoint} failed: {str(e)}')
            
        except requests.exceptions.ConnectionError:
            self.report['admin_panel']['web_responding'] = False
            self.add_issue('critical', 'admin_panel', 'Web server not responding on port 8080')
        except Exception as e:
            self.report['admin_panel']['web_responding'] = False
            self.add_issue('critical', 'admin_panel', f'Error checking web server: {str(e)}')
    
    def check_system(self):
        """Check system resources and configuration"""
        print("💻 Checking system...")
        
        # System info
        self.report['system'] = {
            'platform': os.uname().sysname,
            'hostname': os.uname().nodename,
            'kernel': os.uname().release,
            'arch': os.uname().machine,
            'cpu_count': psutil.cpu_count(),
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory': {
                'total_mb': psutil.virtual_memory().total / 1024 / 1024,
                'available_mb': psutil.virtual_memory().available / 1024 / 1024,
                'percent': psutil.virtual_memory().percent
            },
            'disk': {
                'total_gb': psutil.disk_usage('/').total / 1024 / 1024 / 1024,
                'free_gb': psutil.disk_usage('/').free / 1024 / 1024 / 1024,
                'percent': psutil.disk_usage('/').percent
            },
            'boot_time': datetime.fromtimestamp(psutil.boot_time()).isoformat()
        }
        
        # Check if running on Raspberry Pi
        try:
            with open('/proc/device-tree/model', 'r') as f:
                model = f.read().strip()
                self.report['system']['device_model'] = model
                self.report['system']['is_raspberry_pi'] = 'Raspberry Pi' in model
        except:
            self.report['system']['is_raspberry_pi'] = False
        
        # Check display
        stdout, stderr, code = self.run_command("echo $DISPLAY")
        self.report['system']['display'] = stdout.strip() or 'Not set'
        
        # Check if X11 is running
        stdout, stderr, code = self.run_command("pgrep -x Xorg")
        self.report['system']['x11_running'] = code == 0
        
        if not self.report['system']['x11_running']:
            self.add_issue('warning', 'system', 'X11 not running - touchscreen interface may not work')
    
    def check_services(self):
        """Check all related services"""
        print("⚙️ Checking services...")
        
        services = [
            'spotify-player',
            'spotify-admin', 
            'nginx',
            'bluetooth',
            'plymouth',
            'getty@tty1'
        ]
        
        for service in services:
            stdout, stderr, code = self.run_command(f"systemctl is-active {service}")
            status = stdout.strip()
            self.report['services'][service] = status
            
            if service in ['spotify-player', 'spotify-admin'] and status != 'active':
                self.add_issue('critical', 'services', f'{service} is not active: {status}')
            elif status not in ['active', 'unknown']:
                self.add_issue('warning', 'services', f'{service} is {status}')
    
    def check_network(self):
        """Check network connectivity"""
        print("🌐 Checking network...")
        
        # Get network interfaces
        interfaces = psutil.net_if_addrs()
        self.report['network']['interfaces'] = {}
        
        for iface, addrs in interfaces.items():
            if iface != 'lo':  # Skip loopback
                for addr in addrs:
                    if addr.family == socket.AF_INET:
                        self.report['network']['interfaces'][iface] = addr.address
        
        # Check internet connectivity
        stdout, stderr, code = self.run_command("ping -c 1 -W 2 8.8.8.8")
        self.report['network']['internet_connected'] = code == 0
        
        if not self.report['network']['internet_connected']:
            self.add_issue('critical', 'network', 'No internet connection')
        
        # Check if required ports are listening
        ports_to_check = [
            (8080, 'Admin Panel'),
            (8888, 'Spotify Callback'),
            (80, 'Nginx')
        ]
        
        for port, service in ports_to_check:
            for conn in psutil.net_connections():
                if conn.laddr.port == port and conn.status == 'LISTEN':
                    self.report['network'][f'port_{port}'] = 'listening'
                    break
            else:
                self.report['network'][f'port_{port}'] = 'not_listening'
                if port in [8080]:  # Critical ports
                    self.add_issue('critical', 'network', f'Port {port} ({service}) not listening')
    
    def check_files_and_permissions(self):
        """Check critical files and permissions"""
        print("📁 Checking files and permissions...")
        
        critical_files = {
            '/opt/spotify-kids/spotify_player.py': {'owner': 'spotify-kids', 'perms': '755'},
            '/opt/spotify-kids/web/app.py': {'owner': 'spotify-admin', 'perms': '755'},
            '/opt/spotify-kids/config': {'owner': 'spotify-kids', 'perms': '755', 'is_dir': True},
            '/var/log/spotify-kids': {'owner': 'spotify-kids', 'perms': '755', 'is_dir': True},
            '/etc/systemd/system/spotify-player.service': {'owner': 'root', 'perms': '644'},
            '/etc/systemd/system/spotify-admin.service': {'owner': 'root', 'perms': '644'}
        }
        
        for filepath, expected in critical_files.items():
            if os.path.exists(filepath):
                stat = os.stat(filepath)
                actual_perms = oct(stat.st_mode)[-3:]
                
                try:
                    import pwd, grp
                    actual_owner = pwd.getpwuid(stat.st_uid).pw_name
                except:
                    actual_owner = str(stat.st_uid)
                
                self.report['files'][filepath] = {
                    'exists': True,
                    'owner': actual_owner,
                    'permissions': actual_perms
                }
                
                # Check if permissions match expected
                if actual_perms != expected['perms']:
                    self.add_issue('warning', 'permissions', 
                                 f'{filepath} has permissions {actual_perms}, expected {expected["perms"]}')
                
                # Check owner (if not checking for root)
                if expected['owner'] != 'root' and actual_owner != expected['owner']:
                    self.add_issue('warning', 'permissions',
                                 f'{filepath} owned by {actual_owner}, expected {expected["owner"]}')
            else:
                self.report['files'][filepath] = {'exists': False}
                self.add_issue('critical', 'files', f'Missing critical file: {filepath}')
    
    def check_logs(self):
        """Collect recent log entries"""
        print("📋 Checking logs...")
        
        log_sources = [
            ('player', '/var/log/spotify-kids/player.log', 20),
            ('admin', '/var/log/spotify-kids/admin.log', 20),
            ('systemd_player', 'journalctl -u spotify-player -n 20 --no-pager', None),
            ('systemd_admin', 'journalctl -u spotify-admin -n 20 --no-pager', None),
            ('auth', 'tail -n 20 /var/log/auth.log', None)
        ]
        
        for name, source, lines in log_sources:
            if lines:  # File-based log
                if os.path.exists(source):
                    try:
                        stdout, stderr, code = self.run_command(f"tail -n {lines} {source}")
                        self.report['logs'][name] = stdout.split('\n')
                        
                        # Check for errors in logs
                        error_count = stdout.lower().count('error')
                        if error_count > 0:
                            self.add_issue('warning', 'logs', f'{error_count} errors found in {name} log')
                    except:
                        self.report['logs'][name] = ['Could not read log']
                else:
                    self.report['logs'][name] = ['Log file not found']
            else:  # Command-based log
                stdout, stderr, code = self.run_command(source)
                self.report['logs'][name] = stdout.split('\n')[-20:]  # Last 20 lines
    
    def run_tests(self):
        """Run functional tests"""
        print("🧪 Running functional tests...")
        
        tests_passed = 0
        tests_failed = 0
        
        # Test 1: Can create a test file in config directory
        test_file = '/opt/spotify-kids/config/test_write.tmp'
        try:
            with open(test_file, 'w') as f:
                f.write('test')
            os.remove(test_file)
            self.report['tests']['config_writable'] = True
            tests_passed += 1
        except:
            self.report['tests']['config_writable'] = False
            self.add_issue('critical', 'tests', 'Cannot write to config directory')
            tests_failed += 1
        
        # Test 2: Python modules available
        required_modules = ['flask', 'spotipy', 'psutil', 'flask_cors']
        for module in required_modules:
            try:
                __import__(module)
                self.report['tests'][f'module_{module}'] = True
                tests_passed += 1
            except ImportError:
                self.report['tests'][f'module_{module}'] = False
                self.add_issue('critical', 'tests', f'Python module {module} not installed')
                tests_failed += 1
        
        # Test 3: Can resolve Spotify API
        stdout, stderr, code = self.run_command("nslookup accounts.spotify.com")
        if code == 0:
            self.report['tests']['dns_resolution'] = True
            tests_passed += 1
        else:
            self.report['tests']['dns_resolution'] = False
            self.add_issue('critical', 'tests', 'Cannot resolve Spotify API domain')
            tests_failed += 1
        
        self.report['tests']['summary'] = {
            'passed': tests_passed,
            'failed': tests_failed,
            'total': tests_passed + tests_failed
        }
    
    def generate_report(self):
        """Generate the final diagnostic report"""
        print("\n📊 Generating report...")
        
        # Add issues to report
        self.report['issues'] = self.issues
        
        # Generate health score
        if self.report['summary']['critical'] > 0:
            health = 'CRITICAL'
            health_score = 0
        elif self.report['summary']['warnings'] > 5:
            health = 'DEGRADED'
            health_score = 50
        elif self.report['summary']['warnings'] > 0:
            health = 'WARNING'
            health_score = 75
        else:
            health = 'HEALTHY'
            health_score = 100
        
        self.report['health'] = {
            'status': health,
            'score': health_score
        }
        
        # Save report
        report_file = '/opt/spotify-kids/diagnostics_report.json'
        try:
            with open(report_file, 'w') as f:
                json.dump(self.report, f, indent=2, default=str)
            print(f"✅ Report saved to {report_file}")
        except Exception as e:
            print(f"❌ Could not save report: {e}")
            print("\nReport content:")
            print(json.dumps(self.report, indent=2, default=str))
        
        # Also save to web-accessible location
        web_report = '/opt/spotify-kids/web/static/diagnostics.json'
        try:
            os.makedirs('/opt/spotify-kids/web/static', exist_ok=True)
            with open(web_report, 'w') as f:
                json.dump(self.report, f, indent=2, default=str)
            print(f"✅ Web report saved to {web_report}")
        except:
            pass
        
        return self.report
    
    def run(self):
        """Run all diagnostics"""
        print("=" * 60)
        print("SPOTIFY KIDS MANAGER - COMPLETE SYSTEM DIAGNOSTICS")
        print("=" * 60)
        
        self.check_system()
        self.check_network()
        self.check_services()
        self.check_files_and_permissions()
        self.check_boot_splash()
        self.check_player_app()
        self.check_admin_panel()
        self.check_logs()
        self.run_tests()
        
        report = self.generate_report()
        
        print("\n" + "=" * 60)
        print(f"DIAGNOSTICS COMPLETE")
        print(f"Health Status: {report['health']['status']} ({report['health']['score']}%)")
        print(f"Issues Found: {report['summary']['total_issues']}")
        print(f"  Critical: {report['summary']['critical']}")
        print(f"  Warnings: {report['summary']['warnings']}")
        print(f"  Info: {report['summary']['info']}")
        print("=" * 60)
        
        if report['summary']['critical'] > 0:
            print("\n⚠️ CRITICAL ISSUES FOUND:")
            for issue in self.issues:
                if issue['severity'] == 'critical':
                    print(f"  - [{issue['component']}] {issue['message']}")
        
        print(f"\n📱 View report at: http://{socket.gethostname()}:8080/diagnostics")
        print(f"📄 Or check: /opt/spotify-kids/diagnostics_report.json")
        
        return report

if __name__ == "__main__":
    diag = SpotifyKidsDiagnostics()
    diag.run()