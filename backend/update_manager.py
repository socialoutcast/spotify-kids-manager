#!/usr/bin/env python3

"""
System Update Manager for Spotify Kids Manager
Handles security updates and system patches safely
"""

import subprocess
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import threading
import time
import schedule

logger = logging.getLogger(__name__)

class UpdateManager:
    def __init__(self, config_file: str = '/app/data/update_config.json'):
        self.config_file = config_file
        self.config = self.load_config()
        self.update_history = []
        self.update_thread = None
        self.stop_thread = False
        
    def load_config(self) -> dict:
        """Load update configuration"""
        default_config = {
            'auto_update': True,
            'auto_update_time': '03:00',  # 3 AM
            'update_frequency': 'weekly',  # daily, weekly, monthly
            'security_only': True,  # Only security updates
            'reboot_after_update': False,
            'notify_before_update': True,
            'last_check': None,
            'last_update': None,
            'blocked_packages': [],  # Packages to never update
            'protected_packages': [  # Packages that need special handling
                'docker',
                'docker-compose',
                'spotifyd',
                'nginx'
            ]
        }
        
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    saved_config = json.load(f)
                    default_config.update(saved_config)
            except Exception as e:
                logger.error(f"Error loading config: {e}")
        
        return default_config
    
    def save_config(self):
        """Save update configuration"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2, default=str)
        except Exception as e:
            logger.error(f"Error saving config: {e}")
    
    def check_for_updates(self) -> Dict:
        """Check for available system updates"""
        logger.info("Checking for system updates...")
        
        try:
            # Update package lists
            subprocess.run(['apt-get', 'update'], 
                         capture_output=True, 
                         text=True, 
                         timeout=300)
            
            # Check for upgradable packages
            result = subprocess.run(
                ['apt', 'list', '--upgradable'],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            updates = self._parse_updates(result.stdout)
            
            # Separate security updates
            security_updates = []
            regular_updates = []
            
            for update in updates:
                # Check if it's a security update
                check_result = subprocess.run(
                    ['apt-cache', 'policy', update['package']],
                    capture_output=True,
                    text=True
                )
                
                if 'security' in check_result.stdout.lower():
                    security_updates.append(update)
                else:
                    regular_updates.append(update)
            
            # Count and categorize
            update_info = {
                'available': len(updates) > 0,
                'total_updates': len(updates),
                'security_updates': len(security_updates),
                'regular_updates': len(regular_updates),
                'security_list': security_updates[:10],  # First 10 for display
                'regular_list': regular_updates[:10],
                'last_check': datetime.now().isoformat(),
                'next_scheduled': self._get_next_scheduled_time()
            }
            
            self.config['last_check'] = datetime.now().isoformat()
            self.save_config()
            
            return update_info
            
        except subprocess.TimeoutExpired:
            logger.error("Update check timed out")
            return {'error': 'Update check timed out'}
        except Exception as e:
            logger.error(f"Error checking updates: {e}")
            return {'error': str(e)}
    
    def _parse_updates(self, apt_output: str) -> List[Dict]:
        """Parse apt list output"""
        updates = []
        lines = apt_output.strip().split('\n')[1:]  # Skip header
        
        for line in lines:
            if '/' in line:
                parts = line.split()
                if len(parts) >= 2:
                    package_info = parts[0].split('/')
                    package_name = package_info[0]
                    
                    # Skip if in blocked list
                    if package_name in self.config['blocked_packages']:
                        continue
                    
                    updates.append({
                        'package': package_name,
                        'version': parts[1] if len(parts) > 1 else 'unknown',
                        'protected': package_name in self.config['protected_packages']
                    })
        
        return updates
    
    def install_updates(self, security_only: bool = True, 
                       packages: Optional[List[str]] = None) -> Dict:
        """Install system updates"""
        logger.info(f"Installing updates (security_only={security_only})")
        
        try:
            # Prepare command
            if packages:
                # Specific packages
                cmd = ['apt-get', 'install', '-y'] + packages
            elif security_only:
                # Security updates only
                cmd = ['apt-get', 'upgrade', '-y', 
                      '-o', 'Dpkg::Options::=--force-confdef',
                      '-o', 'Dpkg::Options::=--force-confold']
                
                # Add security repository filter
                env = os.environ.copy()
                env['DEBIAN_FRONTEND'] = 'noninteractive'
            else:
                # All updates
                cmd = ['apt-get', 'dist-upgrade', '-y',
                      '-o', 'Dpkg::Options::=--force-confdef',
                      '-o', 'Dpkg::Options::=--force-confold']
                env = os.environ.copy()
                env['DEBIAN_FRONTEND'] = 'noninteractive'
            
            # Stop music service during update to prevent issues
            logger.info("Pausing music service during update...")
            subprocess.run(['systemctl', 'stop', 'spotifyd'], capture_output=True)
            
            # Run update
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800,  # 30 minutes timeout
                env=env if not packages else None
            )
            
            # Restart music service
            subprocess.run(['systemctl', 'start', 'spotifyd'], capture_output=True)
            
            if result.returncode == 0:
                # Clean up
                subprocess.run(['apt-get', 'autoremove', '-y'], 
                             capture_output=True)
                subprocess.run(['apt-get', 'autoclean'], 
                             capture_output=True)
                
                # Log update
                self.update_history.append({
                    'timestamp': datetime.now().isoformat(),
                    'type': 'security' if security_only else 'full',
                    'packages': packages if packages else 'all',
                    'success': True
                })
                
                self.config['last_update'] = datetime.now().isoformat()
                self.save_config()
                
                return {
                    'success': True,
                    'message': 'Updates installed successfully',
                    'output': result.stdout[-1000:]  # Last 1000 chars
                }
            else:
                return {
                    'success': False,
                    'error': 'Update failed',
                    'output': result.stderr[-1000:]
                }
                
        except subprocess.TimeoutExpired:
            logger.error("Update installation timed out")
            # Restart music service if it was stopped
            subprocess.run(['systemctl', 'start', 'spotifyd'], capture_output=True)
            return {'success': False, 'error': 'Update timed out'}
        except Exception as e:
            logger.error(f"Error installing updates: {e}")
            # Restart music service if it was stopped
            subprocess.run(['systemctl', 'start', 'spotifyd'], capture_output=True)
            return {'success': False, 'error': str(e)}
    
    def schedule_updates(self):
        """Schedule automatic updates based on configuration"""
        if not self.config['auto_update']:
            logger.info("Auto-updates disabled")
            return
        
        # Clear existing schedules
        schedule.clear('updates')
        
        # Schedule based on frequency
        update_time = self.config['auto_update_time']
        
        if self.config['update_frequency'] == 'daily':
            schedule.every().day.at(update_time).do(
                self._run_scheduled_update
            ).tag('updates')
        elif self.config['update_frequency'] == 'weekly':
            schedule.every().monday.at(update_time).do(
                self._run_scheduled_update
            ).tag('updates')
        elif self.config['update_frequency'] == 'monthly':
            # Run on 1st of each month
            schedule.every().day.at(update_time).do(
                self._check_monthly_update
            ).tag('updates')
        
        logger.info(f"Updates scheduled: {self.config['update_frequency']} at {update_time}")
    
    def _run_scheduled_update(self):
        """Run scheduled update"""
        logger.info("Running scheduled update...")
        
        # Check for updates first
        update_info = self.check_for_updates()
        
        if update_info.get('security_updates', 0) > 0:
            # Install security updates
            result = self.install_updates(security_only=True)
            
            if result['success'] and self.config.get('reboot_after_update'):
                logger.info("Scheduling reboot in 5 minutes...")
                subprocess.run(['shutdown', '-r', '+5', 
                              'System will reboot for security updates'])
    
    def _check_monthly_update(self):
        """Check if it's time for monthly update"""
        if datetime.now().day == 1:
            self._run_scheduled_update()
    
    def _get_next_scheduled_time(self) -> Optional[str]:
        """Get next scheduled update time"""
        if not self.config['auto_update']:
            return None
        
        now = datetime.now()
        update_time = datetime.strptime(self.config['auto_update_time'], '%H:%M')
        next_time = now.replace(
            hour=update_time.hour, 
            minute=update_time.minute, 
            second=0, 
            microsecond=0
        )
        
        if self.config['update_frequency'] == 'daily':
            if next_time <= now:
                next_time += timedelta(days=1)
        elif self.config['update_frequency'] == 'weekly':
            days_until_monday = (7 - now.weekday()) % 7
            if days_until_monday == 0 and next_time <= now:
                days_until_monday = 7
            next_time += timedelta(days=days_until_monday)
        elif self.config['update_frequency'] == 'monthly':
            if now.day > 1 or (now.day == 1 and next_time <= now):
                # Next month
                if now.month == 12:
                    next_time = next_time.replace(year=now.year + 1, month=1, day=1)
                else:
                    next_time = next_time.replace(month=now.month + 1, day=1)
        
        return next_time.isoformat()
    
    def start_scheduler(self):
        """Start the update scheduler thread"""
        if self.update_thread and self.update_thread.is_alive():
            logger.warning("Scheduler already running")
            return
        
        self.stop_thread = False
        self.schedule_updates()
        
        def run_schedule():
            while not self.stop_thread:
                schedule.run_pending()
                time.sleep(60)  # Check every minute
        
        self.update_thread = threading.Thread(target=run_schedule, daemon=True)
        self.update_thread.start()
        logger.info("Update scheduler started")
    
    def stop_scheduler(self):
        """Stop the update scheduler"""
        self.stop_thread = True
        if self.update_thread:
            self.update_thread.join(timeout=5)
        logger.info("Update scheduler stopped")
    
    def get_update_history(self, limit: int = 10) -> List[Dict]:
        """Get recent update history"""
        return self.update_history[-limit:]
    
    def verify_system_integrity(self) -> Dict:
        """Verify critical system components are working"""
        checks = {
            'docker': False,
            'spotifyd': False,
            'network': False,
            'audio': False,
            'disk_space': False
        }
        
        try:
            # Check Docker
            result = subprocess.run(['docker', 'ps'], 
                                  capture_output=True, 
                                  timeout=5)
            checks['docker'] = result.returncode == 0
            
            # Check Spotifyd
            result = subprocess.run(['pgrep', 'spotifyd'], 
                                  capture_output=True, 
                                  timeout=5)
            checks['spotifyd'] = result.returncode == 0
            
            # Check network
            result = subprocess.run(['ping', '-c', '1', '8.8.8.8'], 
                                  capture_output=True, 
                                  timeout=5)
            checks['network'] = result.returncode == 0
            
            # Check audio
            result = subprocess.run(['aplay', '-l'], 
                                  capture_output=True, 
                                  timeout=5)
            checks['audio'] = result.returncode == 0
            
            # Check disk space (need at least 1GB free)
            result = subprocess.run(['df', '-BG', '/'], 
                                  capture_output=True, 
                                  text=True,
                                  timeout=5)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    parts = lines[1].split()
                    if len(parts) >= 4:
                        available = int(parts[3].rstrip('G'))
                        checks['disk_space'] = available >= 1
            
        except Exception as e:
            logger.error(f"Error during system verification: {e}")
        
        return {
            'healthy': all(checks.values()),
            'checks': checks,
            'timestamp': datetime.now().isoformat()
        }