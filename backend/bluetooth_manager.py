#!/usr/bin/env python3

"""
Bluetooth Manager for Spotify Kids Manager
Handles Bluetooth device discovery, pairing, and audio routing
"""

import subprocess
import json
import logging
import re
import time
from typing import List, Dict, Optional

logger = logging.getLogger(__name__)


class BluetoothManager:
    """Manages Bluetooth connections and audio devices"""
    
    def __init__(self):
        self.paired_devices = []
        self.connected_device = None
        self.ensure_bluetooth_service()
    
    def ensure_bluetooth_service(self):
        """Ensure Bluetooth service is running"""
        try:
            # Start Bluetooth service if not running
            subprocess.run(['systemctl', 'start', 'bluetooth'], 
                         capture_output=True, check=False)
            # Enable Bluetooth adapter
            subprocess.run(['bluetoothctl', 'power', 'on'], 
                         capture_output=True, check=False)
            logger.info("Bluetooth service initialized")
        except Exception as e:
            logger.error(f"Failed to initialize Bluetooth: {e}")
    
    def scan_devices(self, duration: int = 10) -> List[Dict]:
        """Scan for available Bluetooth devices"""
        devices = []
        try:
            # Start scanning
            scan_proc = subprocess.Popen(
                ['bluetoothctl', 'scan', 'on'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Wait for scan duration
            time.sleep(duration)
            
            # Stop scanning
            subprocess.run(['bluetoothctl', 'scan', 'off'], 
                         capture_output=True, check=False)
            scan_proc.terminate()
            
            # Get discovered devices
            result = subprocess.run(
                ['bluetoothctl', 'devices'],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                # Parse device list
                for line in result.stdout.strip().split('\n'):
                    match = re.match(r'Device ([0-9A-F:]+) (.+)', line)
                    if match:
                        mac_address = match.group(1)
                        name = match.group(2)
                        
                        # Get device info
                        info = self.get_device_info(mac_address)
                        devices.append({
                            'mac_address': mac_address,
                            'name': name,
                            'connected': info.get('connected', False),
                            'paired': info.get('paired', False),
                            'trusted': info.get('trusted', False),
                            'icon': self.get_device_icon(info)
                        })
            
            logger.info(f"Found {len(devices)} Bluetooth devices")
            return devices
            
        except Exception as e:
            logger.error(f"Failed to scan Bluetooth devices: {e}")
            return []
    
    def get_device_info(self, mac_address: str) -> Dict:
        """Get detailed information about a Bluetooth device"""
        info = {
            'connected': False,
            'paired': False,
            'trusted': False,
            'class': None,
            'icon': None
        }
        
        try:
            result = subprocess.run(
                ['bluetoothctl', 'info', mac_address],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                output = result.stdout
                info['connected'] = 'Connected: yes' in output
                info['paired'] = 'Paired: yes' in output
                info['trusted'] = 'Trusted: yes' in output
                
                # Extract device class
                class_match = re.search(r'Class: (0x[0-9a-fA-F]+)', output)
                if class_match:
                    info['class'] = class_match.group(1)
                
                # Extract icon if available
                icon_match = re.search(r'Icon: (\w+)', output)
                if icon_match:
                    info['icon'] = icon_match.group(1)
                    
        except Exception as e:
            logger.error(f"Failed to get device info for {mac_address}: {e}")
        
        return info
    
    def get_device_icon(self, info: Dict) -> str:
        """Determine device icon based on device class or type"""
        icon = info.get('icon', '')
        device_class = info.get('class', '')
        
        if 'audio' in icon.lower() or device_class == '0x240404':
            return 'headphones'
        elif 'phone' in icon.lower():
            return 'smartphone'
        elif 'computer' in icon.lower():
            return 'computer'
        else:
            return 'bluetooth'
    
    def pair_device(self, mac_address: str) -> Dict:
        """Pair with a Bluetooth device"""
        try:
            # Trust the device first
            subprocess.run(
                ['bluetoothctl', 'trust', mac_address],
                capture_output=True,
                check=False
            )
            
            # Attempt to pair
            result = subprocess.run(
                ['bluetoothctl', 'pair', mac_address],
                capture_output=True,
                text=True,
                timeout=30,
                check=False
            )
            
            success = result.returncode == 0 or 'Already Paired' in result.stderr
            
            if success:
                logger.info(f"Successfully paired with {mac_address}")
                return {'success': True, 'message': 'Device paired successfully'}
            else:
                error_msg = result.stderr.strip() if result.stderr else 'Pairing failed'
                logger.error(f"Failed to pair with {mac_address}: {error_msg}")
                return {'success': False, 'message': error_msg}
                
        except subprocess.TimeoutExpired:
            logger.error(f"Pairing timeout for {mac_address}")
            return {'success': False, 'message': 'Pairing timeout - device may require PIN'}
        except Exception as e:
            logger.error(f"Failed to pair with {mac_address}: {e}")
            return {'success': False, 'message': str(e)}
    
    def connect_device(self, mac_address: str) -> Dict:
        """Connect to a paired Bluetooth device"""
        try:
            # Ensure device is trusted
            subprocess.run(
                ['bluetoothctl', 'trust', mac_address],
                capture_output=True,
                check=False
            )
            
            # Connect to device
            result = subprocess.run(
                ['bluetoothctl', 'connect', mac_address],
                capture_output=True,
                text=True,
                timeout=10,
                check=False
            )
            
            if result.returncode == 0:
                self.connected_device = mac_address
                
                # Set as default audio sink if it's an audio device
                self.set_audio_output(mac_address)
                
                logger.info(f"Successfully connected to {mac_address}")
                return {'success': True, 'message': 'Device connected successfully'}
            else:
                error_msg = result.stderr.strip() if result.stderr else 'Connection failed'
                logger.error(f"Failed to connect to {mac_address}: {error_msg}")
                return {'success': False, 'message': error_msg}
                
        except subprocess.TimeoutExpired:
            logger.error(f"Connection timeout for {mac_address}")
            return {'success': False, 'message': 'Connection timeout'}
        except Exception as e:
            logger.error(f"Failed to connect to {mac_address}: {e}")
            return {'success': False, 'message': str(e)}
    
    def disconnect_device(self, mac_address: str) -> Dict:
        """Disconnect from a Bluetooth device"""
        try:
            result = subprocess.run(
                ['bluetoothctl', 'disconnect', mac_address],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                if self.connected_device == mac_address:
                    self.connected_device = None
                logger.info(f"Successfully disconnected from {mac_address}")
                return {'success': True, 'message': 'Device disconnected successfully'}
            else:
                error_msg = result.stderr.strip() if result.stderr else 'Disconnection failed'
                logger.error(f"Failed to disconnect from {mac_address}: {error_msg}")
                return {'success': False, 'message': error_msg}
                
        except Exception as e:
            logger.error(f"Failed to disconnect from {mac_address}: {e}")
            return {'success': False, 'message': str(e)}
    
    def remove_device(self, mac_address: str) -> Dict:
        """Remove (unpair) a Bluetooth device"""
        try:
            # Disconnect first if connected
            if self.connected_device == mac_address:
                self.disconnect_device(mac_address)
            
            result = subprocess.run(
                ['bluetoothctl', 'remove', mac_address],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                logger.info(f"Successfully removed {mac_address}")
                return {'success': True, 'message': 'Device removed successfully'}
            else:
                error_msg = result.stderr.strip() if result.stderr else 'Removal failed'
                logger.error(f"Failed to remove {mac_address}: {error_msg}")
                return {'success': False, 'message': error_msg}
                
        except Exception as e:
            logger.error(f"Failed to remove {mac_address}: {e}")
            return {'success': False, 'message': str(e)}
    
    def set_audio_output(self, mac_address: str):
        """Set Bluetooth device as default audio output"""
        try:
            # Check if PulseAudio is available
            pa_check = subprocess.run(
                ['which', 'pactl'],
                capture_output=True,
                check=False
            )
            
            if pa_check.returncode == 0:
                # Use PulseAudio to set default sink
                # First, get the sink name for the Bluetooth device
                result = subprocess.run(
                    ['pactl', 'list', 'short', 'sinks'],
                    capture_output=True,
                    text=True,
                    check=False
                )
                
                if result.returncode == 0:
                    # Look for Bluetooth sink
                    mac_formatted = mac_address.replace(':', '_')
                    for line in result.stdout.strip().split('\n'):
                        if mac_formatted in line:
                            sink_name = line.split('\t')[1]
                            # Set as default sink
                            subprocess.run(
                                ['pactl', 'set-default-sink', sink_name],
                                capture_output=True,
                                check=False
                            )
                            logger.info(f"Set {mac_address} as default audio output")
                            break
            else:
                # Fallback to ALSA if PulseAudio not available
                logger.info("PulseAudio not available, using ALSA defaults")
                
        except Exception as e:
            logger.warning(f"Could not set audio output for {mac_address}: {e}")
    
    def get_paired_devices(self) -> List[Dict]:
        """Get list of paired Bluetooth devices"""
        devices = []
        try:
            result = subprocess.run(
                ['bluetoothctl', 'paired-devices'],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    match = re.match(r'Device ([0-9A-F:]+) (.+)', line)
                    if match:
                        mac_address = match.group(1)
                        name = match.group(2)
                        info = self.get_device_info(mac_address)
                        devices.append({
                            'mac_address': mac_address,
                            'name': name,
                            'connected': info.get('connected', False),
                            'paired': True,
                            'trusted': info.get('trusted', False),
                            'icon': self.get_device_icon(info)
                        })
            
            self.paired_devices = devices
            return devices
            
        except Exception as e:
            logger.error(f"Failed to get paired devices: {e}")
            return []
    
    def get_connected_devices(self) -> List[Dict]:
        """Get list of currently connected Bluetooth devices"""
        connected = []
        paired = self.get_paired_devices()
        
        for device in paired:
            if device.get('connected'):
                connected.append(device)
        
        return connected
    
    def enable_discovery(self, duration: int = 180) -> Dict:
        """Make system discoverable for pairing"""
        try:
            # Set discoverable on
            subprocess.run(
                ['bluetoothctl', 'discoverable', 'on'],
                capture_output=True,
                check=False
            )
            
            # Set pairable on
            subprocess.run(
                ['bluetoothctl', 'pairable', 'on'],
                capture_output=True,
                check=False
            )
            
            logger.info(f"Bluetooth discovery enabled for {duration} seconds")
            
            # Schedule turning off discovery after duration
            if duration > 0:
                import threading
                timer = threading.Timer(duration, self.disable_discovery)
                timer.daemon = True
                timer.start()
            
            return {'success': True, 'message': f'Discovery enabled for {duration} seconds'}
            
        except Exception as e:
            logger.error(f"Failed to enable discovery: {e}")
            return {'success': False, 'message': str(e)}
    
    def disable_discovery(self) -> Dict:
        """Disable Bluetooth discovery"""
        try:
            subprocess.run(
                ['bluetoothctl', 'discoverable', 'off'],
                capture_output=True,
                check=False
            )
            
            subprocess.run(
                ['bluetoothctl', 'pairable', 'off'],
                capture_output=True,
                check=False
            )
            
            logger.info("Bluetooth discovery disabled")
            return {'success': True, 'message': 'Discovery disabled'}
            
        except Exception as e:
            logger.error(f"Failed to disable discovery: {e}")
            return {'success': False, 'message': str(e)}
    
    def get_adapter_info(self) -> Dict:
        """Get Bluetooth adapter information"""
        info = {
            'powered': False,
            'discoverable': False,
            'pairable': False,
            'discovering': False,
            'name': 'Unknown',
            'address': 'Unknown'
        }
        
        try:
            result = subprocess.run(
                ['bluetoothctl', 'show'],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                output = result.stdout
                info['powered'] = 'Powered: yes' in output
                info['discoverable'] = 'Discoverable: yes' in output
                info['pairable'] = 'Pairable: yes' in output
                info['discovering'] = 'Discovering: yes' in output
                
                # Extract adapter name
                name_match = re.search(r'Name: (.+)', output)
                if name_match:
                    info['name'] = name_match.group(1)
                
                # Extract adapter address
                addr_match = re.search(r'Controller ([0-9A-F:]+)', output)
                if addr_match:
                    info['address'] = addr_match.group(1)
                    
        except Exception as e:
            logger.error(f"Failed to get adapter info: {e}")
        
        return info