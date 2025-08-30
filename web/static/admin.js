// Admin Panel JavaScript - Clean and Simple

// API Functions
async function apiCall(url, method = 'GET', data = null) {
    const options = {
        method: method,
        headers: {'Content-Type': 'application/json'}
    };
    if (data) {
        options.body = JSON.stringify(data);
    }
    try {
        const response = await fetch(url, options);
        const result = await response.json();
        return result;
    } catch (error) {
        console.error('API Error:', error);
        return {success: false, error: error.message};
    }
}

// Show status message
function showStatus(elementId, message, isError = false) {
    const statusDiv = document.getElementById(elementId);
    const statusBox = document.getElementById(elementId + 'Box');
    const statusMessage = document.getElementById(elementId + 'Message');
    
    if (statusDiv && statusBox && statusMessage) {
        statusDiv.style.display = 'block';
        statusBox.style.background = isError ? '#ef4444' : '#10b981';
        statusBox.style.color = 'white';
        statusMessage.innerHTML = message;
        setTimeout(() => { statusDiv.style.display = 'none'; }, 3000);
    } else if (statusDiv) {
        // Fallback if structure is different
        statusDiv.style.display = 'block';
        statusDiv.style.background = isError ? '#ef4444' : '#10b981';
        statusDiv.style.color = 'white';
        statusDiv.style.padding = '10px';
        statusDiv.innerHTML = message;
        setTimeout(() => { statusDiv.style.display = 'none'; }, 3000);
    }
}

// Spotify Functions
async function saveSpotifyConfig() {
    const clientId = document.getElementById('clientId').value;
    const clientSecret = document.getElementById('clientSecret').value;
    
    const result = await apiCall('/api/spotify/config', 'POST', {
        client_id: clientId,
        client_secret: clientSecret
    });
    
    if (result.success) {
        showStatus('spotifyStatus', '✓ Configuration saved successfully');
    } else {
        showStatus('spotifyStatus', '✗ Failed to save: ' + (result.error || 'Unknown error'), true);
    }
}

async function testSpotifyConfig() {
    const result = await apiCall('/api/spotify/test', 'POST');
    
    if (result.success) {
        showStatus('spotifyStatus', '✓ Connection successful!');
    } else {
        showStatus('spotifyStatus', '✗ ' + (result.error || 'Connection failed'), true);
    }
}

// Player Control
async function controlPlayer(action) {
    const result = await apiCall('/api/player/' + action, 'POST');
    
    if (result.success) {
        showStatus('playerStatus', '✓ Player ' + action);
    } else {
        showStatus('playerStatus', '✗ ' + (result.error || 'Command failed'), true);
    }
}

// System Functions
async function restartServices() {
    if (!confirm('Restart all services?')) return;
    
    const result = await apiCall('/api/system/restart-services', 'POST');
    if (result.success || result.status === 502) {
        alert('Services restarting. Page will reload in 5 seconds.');
        setTimeout(() => location.reload(), 5000);
    }
}

async function rebootSystem() {
    if (!confirm('Reboot the system?')) return;
    
    await apiCall('/api/system/reboot', 'POST');
    alert('System rebooting...');
}

async function powerOffSystem() {
    if (!confirm('Power off the system?')) return;
    
    await apiCall('/api/system/poweroff', 'POST');
    alert('System powering off...');
}

// Admin Settings
async function saveAdminSettings() {
    const password = document.getElementById('adminPassword').value;
    const autoStart = document.getElementById('autoStart').checked;
    const fullscreen = document.getElementById('fullscreen').checked;
    const idleTimeout = document.getElementById('idleTimeout').value;
    const volumeLimit = document.getElementById('volumeLimit').value;
    
    const result = await apiCall('/api/admin/settings', 'POST', {
        password: password,
        auto_start: autoStart,
        fullscreen: fullscreen,
        idle_timeout: parseInt(idleTimeout),
        volume_limit: parseInt(volumeLimit)
    });
    
    if (result.success) {
        showStatus('adminStatus', '✓ Settings saved');
    } else {
        showStatus('adminStatus', '✗ Failed to save settings', true);
    }
}

// Parental Controls
async function saveContentFilter() {
    const explicitBlocked = document.getElementById('explicitBlock').checked;
    const playlistApproval = document.getElementById('playlistApproval').checked;
    const blockedArtists = document.getElementById('blockedArtists').value.split('\n').filter(a => a.trim());
    
    const result = await apiCall('/api/parental/content-filter', 'POST', {
        explicit_blocked: explicitBlocked,
        require_playlist_approval: playlistApproval,
        blocked_artists: blockedArtists,
        blocked_songs: [],
        allowed_playlists: []
    });
    
    if (result.success) {
        showStatus('parentalStatus', '✓ Content filter saved');
    } else {
        showStatus('parentalStatus', '✗ Failed to save', true);
    }
}

async function saveSchedule() {
    const enabled = document.getElementById('scheduleEnabled').checked;
    const schedule = {
        enabled: enabled,
        weekday: {
            morning: {
                start: document.getElementById('weekdayMorningStart').value,
                end: document.getElementById('weekdayMorningEnd').value
            },
            afternoon: {
                start: document.getElementById('weekdayAfternoonStart').value,
                end: document.getElementById('weekdayAfternoonEnd').value
            }
        },
        weekend: {
            morning: {
                start: document.getElementById('weekendMorningStart').value,
                end: document.getElementById('weekendMorningEnd').value
            },
            afternoon: {
                start: document.getElementById('weekendAfternoonStart').value,
                end: document.getElementById('weekendAfternoonEnd').value
            }
        }
    };
    
    const result = await apiCall('/api/parental/schedule', 'POST', schedule);
    
    if (result.success) {
        showStatus('scheduleStatus', '✓ Schedule saved');
    } else {
        showStatus('scheduleStatus', '✗ Failed to save', true);
    }
}

async function saveLimits() {
    const dailyLimit = document.getElementById('dailyLimit').value;
    const sessionLimit = document.getElementById('sessionLimit').value;
    const breakTime = document.getElementById('breakTime').value;
    const skipLimit = document.getElementById('skipLimit').value;
    
    const result = await apiCall('/api/parental/limits', 'POST', {
        daily_limit_minutes: parseInt(dailyLimit),
        session_limit_minutes: parseInt(sessionLimit),
        break_time_minutes: parseInt(breakTime),
        skip_limit_per_hour: parseInt(skipLimit)
    });
    
    if (result.success) {
        showStatus('limitsStatus', '✓ Limits saved');
    } else {
        showStatus('limitsStatus', '✗ Failed to save', true);
    }
}

async function sendMessage() {
    const message = document.getElementById('playerMessage').value;
    if (!message.trim()) {
        alert('Please enter a message');
        return;
    }
    
    const result = await apiCall('/api/parental/send-message', 'POST', {message: message});
    
    if (result.success) {
        document.getElementById('playerMessage').value = '';
        showStatus('messageStatus', '✓ Message sent');
    } else {
        showStatus('messageStatus', '✗ Failed to send', true);
    }
}

async function emergencyStop() {
    if (!confirm('Stop music immediately?')) return;
    
    const result = await apiCall('/api/parental/emergency-stop', 'POST');
    
    if (result.success) {
        alert('Emergency stop activated');
    }
}

// Logs
let logModal = null;
let logRefreshInterval = null;

async function openLogModal(type) {
    if (!logModal) {
        // Create modal if it doesn't exist
        logModal = document.createElement('div');
        logModal.id = 'logModal';
        logModal.style.cssText = 'display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1000;';
        logModal.innerHTML = `
            <div style="background:white;margin:50px auto;padding:20px;width:80%;max-width:800px;max-height:80vh;overflow:auto;">
                <h3>Log Viewer</h3>
                <pre id="logContent" style="background:#f4f4f4;padding:10px;overflow:auto;max-height:400px;"></pre>
                <button onclick="closeLogModal()">Close</button>
            </div>
        `;
        document.body.appendChild(logModal);
    }
    
    logModal.style.display = 'block';
    document.getElementById('logContent').textContent = 'Loading logs...';
    
    const response = await fetch(`/api/logs/${type}?lines=100`);
    const logs = await response.text();
    document.getElementById('logContent').textContent = logs;
    
    // Refresh every 2 seconds
    logRefreshInterval = setInterval(async () => {
        const response = await fetch(`/api/logs/${type}?lines=100`);
        const logs = await response.text();
        document.getElementById('logContent').textContent = logs;
    }, 2000);
}

function closeLogModal() {
    if (logModal) {
        logModal.style.display = 'none';
    }
    if (logRefreshInterval) {
        clearInterval(logRefreshInterval);
        logRefreshInterval = null;
    }
}

async function clearLogs() {
    if (!confirm('Clear all logs?')) return;
    
    const result = await apiCall('/api/logs/clear', 'POST');
    
    if (result.success) {
        alert('Logs cleared');
    }
}

// Bluetooth
// Bluetooth Modal Functions
function openBluetoothScanModal() {
    const modal = document.getElementById('bluetoothScanModal');
    if (modal) {
        modal.style.display = 'flex';
        startBluetoothScan();
    }
}

function closeBluetoothScanModal() {
    const modal = document.getElementById('bluetoothScanModal');
    if (modal) {
        modal.style.display = 'none';
    }
}

// Alias functions for modal buttons
function closeScanModal() {
    closeBluetoothScanModal();
}

function stopScan() {
    // Stop scanning and close modal
    const scanStatus = document.getElementById('scanStatusText');
    if (scanStatus) {
        scanStatus.textContent = 'Scan stopped';
    }
    setTimeout(() => {
        closeBluetoothScanModal();
    }, 500);
}

async function startBluetoothScan() {
    const deviceList = document.getElementById('scanDeviceList');
    const scanStatus = document.getElementById('scanStatus');
    const scanSpinner = document.getElementById('scanSpinner');
    
    // Show scanning status
    if (scanStatus) scanStatus.textContent = 'Scanning for devices...';
    if (scanSpinner) scanSpinner.style.display = 'block';
    if (deviceList) deviceList.innerHTML = '<p>Searching for Bluetooth devices...</p>';
    
    try {
        const result = await apiCall('/api/bluetooth/scan');
        
        if (scanSpinner) scanSpinner.style.display = 'none';
        
        if (result.devices && result.devices.length > 0) {
            if (scanStatus) scanStatus.textContent = `Found ${result.devices.length} device(s)`;
            
            let html = '<div class="device-list">';
            for (const device of result.devices) {
                const name = device.name || 'Unknown Device';
                const address = device.address || '';
                const isPaired = device.paired || false;
                
                html += `
                    <div class="device-item" style="padding: 10px; margin: 5px 0; background: #f5f5f5; border-radius: 5px; display: flex; justify-content: space-between; align-items: center;">
                        <div>
                            <strong>${name}</strong><br>
                            <small style="color: #666;">${address}</small>
                            ${isPaired ? '<span style="color: green; margin-left: 10px;">✓ Paired</span>' : ''}
                        </div>
                        <div>
                            ${!isPaired ? `<button onclick="pairBluetoothDevice('${address}')" style="padding: 5px 10px; background: #4CAF50; color: white; border: none; border-radius: 3px; cursor: pointer;">Pair</button>` : 
                              `<button onclick="connectBluetooth('${address}')" style="padding: 5px 10px; background: #2196F3; color: white; border: none; border-radius: 3px; cursor: pointer;">Connect</button>`}
                        </div>
                    </div>`;
            }
            html += '</div>';
            
            if (deviceList) deviceList.innerHTML = html;
        } else {
            if (scanStatus) scanStatus.textContent = 'No devices found';
            if (deviceList) deviceList.innerHTML = '<p style="text-align: center; color: #666;">No Bluetooth devices found. Make sure devices are in pairing mode.</p>';
        }
    } catch (error) {
        if (scanSpinner) scanSpinner.style.display = 'none';
        if (scanStatus) scanStatus.textContent = 'Scan failed';
        if (deviceList) deviceList.innerHTML = `<p style="color: red;">Error: ${error.message || 'Failed to scan for devices'}</p>`;
    }
}

async function scanBluetooth() {
    // Open the modal if not already open, or refresh scan if modal is open
    const modal = document.getElementById('bluetoothScanModal');
    if (modal && modal.style.display === 'flex') {
        // Modal is already open, just refresh the scan
        startBluetoothScan();
    } else {
        // Open the modal and start scanning
        openBluetoothScanModal();
    }
}

async function pairBluetoothDevice(address) {
    const result = await apiCall('/api/bluetooth/pair', 'POST', {address: address});
    
    if (result.success) {
        alert('Device paired successfully!');
        // Refresh the scan to show updated status
        startBluetoothScan();
    } else {
        alert('Pairing failed: ' + (result.error || 'Unknown error'));
    }
}

async function connectBluetooth(address) {
    const result = await apiCall('/api/bluetooth/connect', 'POST', {address: address});
    
    if (result.success) {
        alert('Connected successfully');
        location.reload();
    } else {
        alert('Connection failed: ' + (result.error || 'Unknown error'));
    }
}

async function disconnectBluetooth(address) {
    const result = await apiCall('/api/bluetooth/disconnect', 'POST', {address: address});
    
    if (result.success) {
        alert('Disconnected');
        location.reload();
    } else {
        alert('Disconnect failed: ' + (result.error || 'Unknown error'));
    }
}

async function removeBluetooth(address) {
    if (!confirm('Remove device ' + address + '?')) return;
    
    const result = await apiCall('/api/bluetooth/remove', 'POST', {address: address});
    
    if (result.success) {
        alert('Device removed');
        location.reload();
    } else {
        alert('Remove failed: ' + (result.error || 'Unknown error'));
    }
}

async function toggleBluetooth() {
    const result = await apiCall('/api/bluetooth/toggle', 'POST');
    
    if (result.success) {
        alert(result.message || 'Bluetooth toggled');
        location.reload();
    } else {
        alert('Toggle failed: ' + (result.error || 'Unknown error'));
    }
}

async function enableBluetooth() {
    showBluetoothStatus('Enabling Bluetooth...', false);
    const result = await apiCall('/api/bluetooth/enable', 'POST');
    
    if (result.success) {
        showBluetoothStatus('Bluetooth enabled successfully!', false);
        setTimeout(() => updateBluetoothStatus(), 1000);
    } else {
        showBluetoothStatus('Failed to enable: ' + (result.error || 'Unknown error'), true);
    }
}

async function disableBluetooth() {
    showBluetoothStatus('Disabling Bluetooth...', false);
    const result = await apiCall('/api/bluetooth/disable', 'POST');
    
    if (result.success) {
        showBluetoothStatus('Bluetooth disabled successfully!', false);
        setTimeout(() => updateBluetoothStatus(), 1000);
    } else {
        showBluetoothStatus('Failed to disable: ' + (result.error || 'Unknown error'), true);
    }
}

async function checkBluetoothStatus() {
    await updateBluetoothStatus();
}

async function updateBluetoothStatus() {
    const result = await apiCall('/api/bluetooth/status');
    
    if (result.success) {
        const stateElement = document.getElementById('bluetoothState');
        const statusText = document.getElementById('bluetoothStatusText');
        const enableBtn = document.getElementById('enableBtBtn');
        const disableBtn = document.getElementById('disableBtBtn');
        
        if (stateElement) {
            stateElement.textContent = result.enabled ? 'Enabled' : 'Disabled';
        }
        
        if (statusText) {
            statusText.className = 'status ' + (result.enabled ? 'online' : 'offline');
        }
        
        if (enableBtn) {
            enableBtn.disabled = result.enabled;
        }
        
        if (disableBtn) {
            disableBtn.disabled = !result.enabled;
        }
    }
}

function showBluetoothStatus(message, isError = false) {
    const statusMsg = document.getElementById('bluetoothStatusMessage');
    if (statusMsg) {
        statusMsg.style.display = 'block';
        statusMsg.style.background = isError ? '#ef4444' : '#10b981';
        statusMsg.style.color = 'white';
        statusMsg.innerHTML = message;
        
        if (!message.includes('...')) {
            setTimeout(() => { statusMsg.style.display = 'none'; }, 3000);
        }
    }
}

// System functions
async function checkUpdates() {
    document.getElementById('updateMessage').textContent = 'Checking...';
    
    const result = await apiCall('/api/system/check-updates');
    
    if (result.success) {
        document.getElementById('updateMessage').innerHTML = result.message;
    } else {
        document.getElementById('updateMessage').textContent = 'Check failed';
    }
}

function closeUpdateModal() {
    const modal = document.getElementById('updateModal');
    if (modal) modal.style.display = 'none';
}

async function runUpdate() {
    if (!confirm('Run system update? This may take several minutes.')) return;
    
    alert('Update started. Check back in a few minutes.');
    // Note: Real update would use SSE for progress
}

// Points system
async function addBonusPoints() {
    const points = prompt('How many points to add?', '10');
    if (!points) return;
    
    const result = await apiCall('/api/parental/add-points', 'POST', {points: parseInt(points)});
    
    if (result.success) {
        alert('Points added');
        location.reload();
    }
}

async function resetPoints() {
    if (!confirm('Reset all points?')) return;
    
    const result = await apiCall('/api/parental/reset-points', 'POST');
    
    if (result.success) {
        alert('Points reset');
        location.reload();
    }
}

// Utility functions
async function logout() {
    await apiCall('/api/logout', 'POST');
    location.reload();
}

async function clearUsageStats() {
    if (!confirm('Clear all usage statistics?')) return;
    
    const result = await apiCall('/api/parental/clear-stats', 'POST');
    
    if (result.success) {
        alert('Usage statistics cleared');
        location.reload();
    }
}

async function refreshUsageStats() {
    location.reload();
}

async function copyLogsToClipboard() {
    const logContent = document.getElementById('logContent');
    if (logContent) {
        try {
            await navigator.clipboard.writeText(logContent.textContent);
            alert('Logs copied to clipboard');
        } catch (err) {
            alert('Failed to copy logs: ' + err);
        }
    }
}

async function takeScreenshot() {
    const result = await apiCall('/api/parental/screenshot', 'POST');
    
    if (result.success && result.screenshot) {
        window.open(result.screenshot, '_blank');
    } else {
        alert('Screenshot captured');
    }
}

async function login() {
    const username = document.getElementById('loginUser').value;
    const password = document.getElementById('loginPass').value;
    
    const result = await apiCall('/api/login', 'POST', {
        username: username,
        password: password
    });
    
    if (result.success) {
        location.reload();
    } else {
        alert('Invalid credentials');
    }
}

// Export stats
function exportUsageStats() {
    window.location.href = '/api/parental/export-stats';
}

function downloadLogs() {
    window.location.href = '/api/logs/download';
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    // Set up any event listeners
    const loginPass = document.getElementById('loginPass');
    if (loginPass) {
        loginPass.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') login();
        });
    }
    
    // Volume slider
    const volumeLimit = document.getElementById('volumeLimit');
    if (volumeLimit) {
        volumeLimit.addEventListener('input', function(e) {
            const display = document.getElementById('volumeValue');
            if (display) display.textContent = e.target.value + '%';
        });
    }
    
    // Check Bluetooth status on page load
    if (document.getElementById('bluetoothState')) {
        updateBluetoothStatus();
    }
    
    // Close modals on ESC
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            closeLogModal();
        }
    });
});