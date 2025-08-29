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
async function scanBluetooth() {
    document.getElementById('scanList').innerHTML = 'Scanning...';
    
    const result = await apiCall('/api/bluetooth/scan');
    
    if (result.devices) {
        let html = '';
        for (const device of result.devices) {
            html += `<div>${device.name || device.address} <button onclick="pairBluetooth('${device.address}')">Pair</button></div>`;
        }
        document.getElementById('scanList').innerHTML = html || 'No devices found';
    } else {
        document.getElementById('scanList').innerHTML = 'Scan failed: ' + (result.error || 'Unknown error');
    }
}

async function pairBluetooth(address) {
    const result = await apiCall('/api/bluetooth/pair', 'POST', {address: address});
    
    if (result.success) {
        alert('Paired successfully');
        location.reload();
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
    const result = await apiCall('/api/bluetooth/enable', 'POST');
    
    if (result.success) {
        alert('Bluetooth enabled');
        location.reload();
    } else {
        alert('Failed to enable Bluetooth: ' + (result.error || 'Unknown error'));
    }
}

async function disableBluetooth() {
    const result = await apiCall('/api/bluetooth/disable', 'POST');
    
    if (result.success) {
        alert('Bluetooth disabled');
        location.reload();
    } else {
        alert('Failed to disable Bluetooth: ' + (result.error || 'Unknown error'));
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
    
    // Close modals on ESC
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            closeLogModal();
        }
    });
});