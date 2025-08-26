import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Button,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  ListItemSecondaryAction,
  IconButton,
  Switch,
  CircularProgress,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Chip,
  Divider,
  Paper,
  Grid,
  Tooltip,
} from '@mui/material';
import {
  Bluetooth as BluetoothIcon,
  BluetoothSearching,
  BluetoothConnected,
  BluetoothDisabled,
  Headphones,
  Speaker,
  Smartphone,
  Computer,
  Delete,
  Link,
  LinkOff,
  Refresh,
  Settings,
  VolumeUp,
} from '@mui/icons-material';
import axios from 'axios';

interface BluetoothDevice {
  mac_address: string;
  name: string;
  connected: boolean;
  paired: boolean;
  trusted: boolean;
  icon: string;
}

interface AdapterInfo {
  powered: boolean;
  discoverable: boolean;
  pairable: boolean;
  discovering: boolean;
  name: string;
  address: string;
}

const BluetoothManager: React.FC = () => {
  const [devices, setDevices] = useState<BluetoothDevice[]>([]);
  const [pairedDevices, setPairedDevices] = useState<BluetoothDevice[]>([]);
  const [scanning, setScanning] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [adapterInfo, setAdapterInfo] = useState<AdapterInfo | null>(null);
  const [discoverable, setDiscoverable] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState<BluetoothDevice | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);

  useEffect(() => {
    loadAdapterInfo();
    loadPairedDevices();
  }, []);

  const loadAdapterInfo = async () => {
    try {
      const response = await axios.get('/api/bluetooth/adapter');
      setAdapterInfo(response.data);
      setDiscoverable(response.data.discoverable);
    } catch (err) {
      console.error('Failed to load adapter info:', err);
    }
  };

  const loadPairedDevices = async () => {
    try {
      const response = await axios.get('/api/bluetooth/paired');
      setPairedDevices(response.data);
    } catch (err) {
      console.error('Failed to load paired devices:', err);
    }
  };

  const scanForDevices = async () => {
    setScanning(true);
    setError(null);
    setDevices([]);
    
    try {
      const response = await axios.post('/api/bluetooth/scan', { duration: 10 });
      setDevices(response.data);
      setSuccess(`Found ${response.data.length} devices`);
    } catch (err: any) {
      setError('Failed to scan for devices');
    } finally {
      setScanning(false);
    }
  };

  const pairDevice = async (device: BluetoothDevice) => {
    setActionInProgress(device.mac_address);
    setError(null);
    
    try {
      const response = await axios.post(`/api/bluetooth/pair/${device.mac_address}`);
      if (response.data.success) {
        setSuccess(`Successfully paired with ${device.name}`);
        loadPairedDevices();
        scanForDevices();
      } else {
        setError(response.data.message || 'Failed to pair device');
      }
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to pair device');
    } finally {
      setActionInProgress(null);
    }
  };

  const connectDevice = async (device: BluetoothDevice) => {
    setActionInProgress(device.mac_address);
    setError(null);
    
    try {
      const response = await axios.post(`/api/bluetooth/connect/${device.mac_address}`);
      if (response.data.success) {
        setSuccess(`Connected to ${device.name}`);
        loadPairedDevices();
      } else {
        setError(response.data.message || 'Failed to connect');
      }
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to connect');
    } finally {
      setActionInProgress(null);
    }
  };

  const disconnectDevice = async (device: BluetoothDevice) => {
    setActionInProgress(device.mac_address);
    setError(null);
    
    try {
      const response = await axios.post(`/api/bluetooth/disconnect/${device.mac_address}`);
      if (response.data.success) {
        setSuccess(`Disconnected from ${device.name}`);
        loadPairedDevices();
      } else {
        setError(response.data.message || 'Failed to disconnect');
      }
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to disconnect');
    } finally {
      setActionInProgress(null);
    }
  };

  const removeDevice = async (device: BluetoothDevice) => {
    setActionInProgress(device.mac_address);
    setError(null);
    setDialogOpen(false);
    
    try {
      const response = await axios.delete(`/api/bluetooth/remove/${device.mac_address}`);
      if (response.data.success) {
        setSuccess(`Removed ${device.name}`);
        loadPairedDevices();
      } else {
        setError(response.data.message || 'Failed to remove device');
      }
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to remove device');
    } finally {
      setActionInProgress(null);
      setSelectedDevice(null);
    }
  };

  const toggleDiscoverable = async () => {
    setLoading(true);
    
    try {
      const endpoint = discoverable ? '/api/bluetooth/discoverable/off' : '/api/bluetooth/discoverable/on';
      const response = await axios.post(endpoint, { duration: 180 });
      if (response.data.success) {
        setDiscoverable(!discoverable);
        setSuccess(response.data.message);
        loadAdapterInfo();
      } else {
        setError(response.data.message || 'Failed to change discoverable mode');
      }
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to change discoverable mode');
    } finally {
      setLoading(false);
    }
  };

  const getDeviceIcon = (iconType: string) => {
    switch (iconType) {
      case 'headphones':
        return <Headphones />;
      case 'speaker':
        return <Speaker />;
      case 'smartphone':
        return <Smartphone />;
      case 'computer':
        return <Computer />;
      default:
        return <BluetoothIcon />;
    }
  };

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h4" gutterBottom sx={{ display: 'flex', alignItems: 'center' }}>
        <BluetoothIcon sx={{ mr: 2 }} />
        Bluetooth Audio Manager
      </Typography>

      {error && (
        <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {success && (
        <Alert severity="success" onClose={() => setSuccess(null)} sx={{ mb: 2 }}>
          {success}
        </Alert>
      )}

      {/* Adapter Status */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Bluetooth Adapter
          </Typography>
          {adapterInfo ? (
            <Grid container spacing={2}>
              <Grid item xs={12} md={6}>
                <Paper elevation={0} sx={{ p: 2, bgcolor: 'background.default' }}>
                  <Typography variant="body2" color="textSecondary">
                    Name: {adapterInfo.name}
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    Address: {adapterInfo.address}
                  </Typography>
                </Paper>
              </Grid>
              <Grid item xs={12} md={6}>
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Typography>
                    Make Discoverable
                  </Typography>
                  <Switch
                    checked={discoverable}
                    onChange={toggleDiscoverable}
                    disabled={loading}
                  />
                </Box>
                {discoverable && (
                  <Typography variant="caption" color="textSecondary">
                    Other devices can find this player for 3 minutes
                  </Typography>
                )}
              </Grid>
            </Grid>
          ) : (
            <CircularProgress size={24} />
          )}
        </CardContent>
      </Card>

      {/* Paired Devices */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
            <Typography variant="h6">
              Paired Devices
            </Typography>
            <IconButton onClick={loadPairedDevices} disabled={loading}>
              <Refresh />
            </IconButton>
          </Box>
          
          {pairedDevices.length > 0 ? (
            <List>
              {pairedDevices.map((device) => (
                <ListItem key={device.mac_address} divider>
                  <ListItemIcon>
                    {device.connected ? (
                      <Tooltip title="Connected">
                        <BluetoothConnected color="primary" />
                      </Tooltip>
                    ) : (
                      getDeviceIcon(device.icon)
                    )}
                  </ListItemIcon>
                  <ListItemText
                    primary={device.name}
                    secondary={
                      <Box>
                        <Typography variant="caption" display="block">
                          {device.mac_address}
                        </Typography>
                        {device.connected && (
                          <Chip
                            label="Connected"
                            size="small"
                            color="success"
                            sx={{ mt: 0.5 }}
                          />
                        )}
                      </Box>
                    }
                  />
                  <ListItemSecondaryAction>
                    <Box sx={{ display: 'flex', gap: 1 }}>
                      {device.connected ? (
                        <>
                          <Tooltip title="Set as Audio Output">
                            <IconButton size="small">
                              <VolumeUp />
                            </IconButton>
                          </Tooltip>
                          <Tooltip title="Disconnect">
                            <IconButton
                              onClick={() => disconnectDevice(device)}
                              disabled={actionInProgress === device.mac_address}
                              size="small"
                            >
                              {actionInProgress === device.mac_address ? (
                                <CircularProgress size={20} />
                              ) : (
                                <LinkOff />
                              )}
                            </IconButton>
                          </Tooltip>
                        </>
                      ) : (
                        <Tooltip title="Connect">
                          <IconButton
                            onClick={() => connectDevice(device)}
                            disabled={actionInProgress === device.mac_address}
                            size="small"
                            color="primary"
                          >
                            {actionInProgress === device.mac_address ? (
                              <CircularProgress size={20} />
                            ) : (
                              <Link />
                            )}
                          </IconButton>
                        </Tooltip>
                      )}
                      <Tooltip title="Remove Device">
                        <IconButton
                          onClick={() => {
                            setSelectedDevice(device);
                            setDialogOpen(true);
                          }}
                          disabled={actionInProgress === device.mac_address}
                          size="small"
                          color="error"
                        >
                          <Delete />
                        </IconButton>
                      </Tooltip>
                    </Box>
                  </ListItemSecondaryAction>
                </ListItem>
              ))}
            </List>
          ) : (
            <Typography color="textSecondary" align="center" sx={{ py: 2 }}>
              No paired devices
            </Typography>
          )}
        </CardContent>
      </Card>

      {/* Available Devices */}
      <Card>
        <CardContent>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
            <Typography variant="h6">
              Available Devices
            </Typography>
            <Button
              variant="contained"
              startIcon={scanning ? <CircularProgress size={20} /> : <BluetoothSearching />}
              onClick={scanForDevices}
              disabled={scanning}
            >
              {scanning ? 'Scanning...' : 'Scan for Devices'}
            </Button>
          </Box>

          {devices.length > 0 ? (
            <List>
              {devices.filter(d => !d.paired).map((device) => (
                <ListItem key={device.mac_address} divider>
                  <ListItemIcon>
                    {getDeviceIcon(device.icon)}
                  </ListItemIcon>
                  <ListItemText
                    primary={device.name}
                    secondary={device.mac_address}
                  />
                  <ListItemSecondaryAction>
                    <Button
                      variant="outlined"
                      size="small"
                      onClick={() => pairDevice(device)}
                      disabled={actionInProgress === device.mac_address}
                    >
                      {actionInProgress === device.mac_address ? (
                        <CircularProgress size={20} />
                      ) : (
                        'Pair'
                      )}
                    </Button>
                  </ListItemSecondaryAction>
                </ListItem>
              ))}
            </List>
          ) : scanning ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <Typography color="textSecondary" align="center" sx={{ py: 2 }}>
              Click "Scan for Devices" to find available Bluetooth devices
            </Typography>
          )}
        </CardContent>
      </Card>

      {/* Confirmation Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)}>
        <DialogTitle>Remove Device</DialogTitle>
        <DialogContent>
          <Typography>
            Are you sure you want to remove "{selectedDevice?.name}"? 
            You'll need to pair it again to use it.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>Cancel</Button>
          <Button
            onClick={() => selectedDevice && removeDevice(selectedDevice)}
            color="error"
            variant="contained"
          >
            Remove
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default BluetoothManager;