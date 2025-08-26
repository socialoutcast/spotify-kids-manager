import React, { useState, useEffect } from 'react';
import {
  Box,
  Paper,
  Typography,
  Button,
  Alert,
  CircularProgress,
  Chip,
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  Switch,
  FormControlLabel,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  TextField,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Badge,
  IconButton,
  Tooltip,
  LinearProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Grid,
  Card,
  CardContent
} from '@mui/material';
import {
  Security as SecurityIcon,
  Update as UpdateIcon,
  Schedule as ScheduleIcon,
  CheckCircle as CheckIcon,
  Warning as WarningIcon,
  ExpandMore as ExpandMoreIcon,
  Info as InfoIcon,
  Refresh as RefreshIcon,
  Download as DownloadIcon,
  Block as BlockIcon,
  Shield as ShieldIcon,
  AccessTime as TimeIcon
} from '@mui/icons-material';
import axios from 'axios';
import { format } from 'date-fns';

interface UpdateInfo {
  available: boolean;
  total_updates: number;
  security_updates: number;
  regular_updates: number;
  security_list: Array<{
    package: string;
    version: string;
    protected: boolean;
  }>;
  regular_list: Array<{
    package: string;
    version: string;
    protected: boolean;
  }>;
  last_check: string;
  next_scheduled: string;
}

interface UpdateConfig {
  auto_update: boolean;
  auto_update_time: string;
  update_frequency: 'daily' | 'weekly' | 'monthly';
  security_only: boolean;
  reboot_after_update: boolean;
  notify_before_update: boolean;
  blocked_packages: string[];
}

const SystemUpdates: React.FC = () => {
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [config, setConfig] = useState<UpdateConfig>({
    auto_update: true,
    auto_update_time: '03:00',
    update_frequency: 'weekly',
    security_only: true,
    reboot_after_update: false,
    notify_before_update: true,
    blocked_packages: []
  });
  const [loading, setLoading] = useState(false);
  const [checking, setChecking] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [installProgress, setInstallProgress] = useState(0);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [confirmDialog, setConfirmDialog] = useState(false);
  const [systemHealth, setSystemHealth] = useState<any>(null);

  useEffect(() => {
    loadConfig();
    checkForUpdates();
    checkSystemHealth();
  }, []);

  const loadConfig = async () => {
    try {
      const response = await axios.get('/api/updates/config', {
        withCredentials: true
      });
      setConfig(response.data);
    } catch (err) {
      console.error('Failed to load update config:', err);
    }
  };

  const saveConfig = async () => {
    setError('');
    setSuccess('');
    try {
      await axios.post('/api/updates/config', config, {
        withCredentials: true
      });
      setSuccess('Update settings saved successfully');
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to save settings');
    }
  };

  const checkForUpdates = async () => {
    setChecking(true);
    setError('');
    try {
      const response = await axios.get('/api/updates/check', {
        withCredentials: true
      });
      setUpdateInfo(response.data);
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to check for updates');
    } finally {
      setChecking(false);
    }
  };

  const installUpdates = async (securityOnly: boolean = true) => {
    setConfirmDialog(false);
    setInstalling(true);
    setError('');
    setSuccess('');
    setInstallProgress(0);

    // Simulate progress
    const progressInterval = setInterval(() => {
      setInstallProgress((prev) => Math.min(prev + 10, 90));
    }, 3000);

    try {
      const response = await axios.post('/api/updates/install', {
        security_only: securityOnly
      }, {
        withCredentials: true,
        timeout: 1800000 // 30 minutes
      });

      if (response.data.success) {
        setSuccess('Updates installed successfully');
        setInstallProgress(100);
        // Refresh update info
        setTimeout(checkForUpdates, 2000);
      } else {
        throw new Error(response.data.error);
      }
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to install updates');
    } finally {
      clearInterval(progressInterval);
      setInstalling(false);
      setInstallProgress(0);
    }
  };

  const checkSystemHealth = async () => {
    try {
      const response = await axios.get('/api/updates/health', {
        withCredentials: true
      });
      setSystemHealth(response.data);
    } catch (err) {
      console.error('Failed to check system health:', err);
    }
  };

  const addBlockedPackage = (packageName: string) => {
    if (packageName && !config.blocked_packages.includes(packageName)) {
      setConfig({
        ...config,
        blocked_packages: [...config.blocked_packages, packageName]
      });
    }
  };

  const removeBlockedPackage = (packageName: string) => {
    setConfig({
      ...config,
      blocked_packages: config.blocked_packages.filter(p => p !== packageName)
    });
  };

  return (
    <Box>
      <Typography variant="h5" gutterBottom sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <ShieldIcon color="primary" />
        System Updates & Security
      </Typography>

      {/* System Health Status */}
      {systemHealth && (
        <Card sx={{ mb: 3, bgcolor: systemHealth.healthy ? 'success.light' : 'warning.light' }}>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              System Health {systemHealth.healthy ? '✅' : '⚠️'}
            </Typography>
            <Grid container spacing={2}>
              {Object.entries(systemHealth.checks).map(([key, value]) => (
                <Grid item xs={6} md={2.4} key={key}>
                  <Chip
                    icon={value ? <CheckIcon /> : <WarningIcon />}
                    label={key.replace('_', ' ').toUpperCase()}
                    color={value ? 'success' : 'warning'}
                    variant="outlined"
                    size="small"
                  />
                </Grid>
              ))}
            </Grid>
          </CardContent>
        </Card>
      )}

      {/* Update Status */}
      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Typography variant="h6">
            Update Status
          </Typography>
          <Button
            variant="outlined"
            startIcon={checking ? <CircularProgress size={20} /> : <RefreshIcon />}
            onClick={checkForUpdates}
            disabled={checking || installing}
          >
            Check for Updates
          </Button>
        </Box>

        {updateInfo && (
          <Box>
            <Grid container spacing={3}>
              <Grid item xs={12} md={4}>
                <Card variant="outlined">
                  <CardContent>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <Badge badgeContent={updateInfo.security_updates} color="error">
                        <SecurityIcon color="primary" />
                      </Badge>
                      <Box>
                        <Typography variant="h6">
                          {updateInfo.security_updates}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          Security Updates
                        </Typography>
                      </Box>
                    </Box>
                  </CardContent>
                </Card>
              </Grid>

              <Grid item xs={12} md={4}>
                <Card variant="outlined">
                  <CardContent>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <Badge badgeContent={updateInfo.regular_updates} color="info">
                        <UpdateIcon />
                      </Badge>
                      <Box>
                        <Typography variant="h6">
                          {updateInfo.regular_updates}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          Regular Updates
                        </Typography>
                      </Box>
                    </Box>
                  </CardContent>
                </Card>
              </Grid>

              <Grid item xs={12} md={4}>
                <Card variant="outlined">
                  <CardContent>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <TimeIcon color="action" />
                      <Box>
                        <Typography variant="body2" color="text.secondary">
                          Last Check
                        </Typography>
                        <Typography variant="body2">
                          {updateInfo.last_check 
                            ? format(new Date(updateInfo.last_check), 'MMM dd, HH:mm')
                            : 'Never'}
                        </Typography>
                      </Box>
                    </Box>
                  </CardContent>
                </Card>
              </Grid>
            </Grid>

            {updateInfo.security_updates > 0 && (
              <Alert severity="warning" sx={{ mt: 2 }}>
                <strong>Security updates available!</strong> It's recommended to install these immediately.
              </Alert>
            )}

            {/* Update Lists */}
            {(updateInfo.security_list.length > 0 || updateInfo.regular_list.length > 0) && (
              <Box sx={{ mt: 3 }}>
                {updateInfo.security_list.length > 0 && (
                  <Accordion defaultExpanded={updateInfo.security_updates <= 5}>
                    <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                      <Typography>
                        Security Updates ({updateInfo.security_list.length})
                      </Typography>
                    </AccordionSummary>
                    <AccordionDetails>
                      <List dense>
                        {updateInfo.security_list.map((pkg) => (
                          <ListItem key={pkg.package}>
                            <ListItemIcon>
                              <SecurityIcon color="error" fontSize="small" />
                            </ListItemIcon>
                            <ListItemText
                              primary={pkg.package}
                              secondary={`Version: ${pkg.version}`}
                            />
                            {pkg.protected && (
                              <Chip label="Protected" size="small" color="warning" />
                            )}
                          </ListItem>
                        ))}
                      </List>
                    </AccordionDetails>
                  </Accordion>
                )}

                {updateInfo.regular_list.length > 0 && (
                  <Accordion>
                    <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                      <Typography>
                        Regular Updates ({updateInfo.regular_list.length})
                      </Typography>
                    </AccordionSummary>
                    <AccordionDetails>
                      <List dense>
                        {updateInfo.regular_list.map((pkg) => (
                          <ListItem key={pkg.package}>
                            <ListItemIcon>
                              <UpdateIcon fontSize="small" />
                            </ListItemIcon>
                            <ListItemText
                              primary={pkg.package}
                              secondary={`Version: ${pkg.version}`}
                            />
                            <IconButton
                              size="small"
                              onClick={() => addBlockedPackage(pkg.package)}
                              title="Block this package from updates"
                            >
                              <BlockIcon fontSize="small" />
                            </IconButton>
                          </ListItem>
                        ))}
                      </List>
                    </AccordionDetails>
                  </Accordion>
                )}
              </Box>
            )}

            {/* Install Buttons */}
            {updateInfo.available && (
              <Box sx={{ mt: 3, display: 'flex', gap: 2 }}>
                {updateInfo.security_updates > 0 && (
                  <Button
                    variant="contained"
                    color="error"
                    startIcon={installing ? <CircularProgress size={20} /> : <DownloadIcon />}
                    onClick={() => setConfirmDialog(true)}
                    disabled={installing}
                  >
                    Install Security Updates
                  </Button>
                )}
                <Button
                  variant="outlined"
                  startIcon={installing ? <CircularProgress size={20} /> : <DownloadIcon />}
                  onClick={() => installUpdates(false)}
                  disabled={installing || config.security_only}
                >
                  Install All Updates
                </Button>
              </Box>
            )}

            {installing && (
              <Box sx={{ mt: 2 }}>
                <Typography variant="body2" gutterBottom>
                  Installing updates... This may take several minutes.
                </Typography>
                <LinearProgress variant="determinate" value={installProgress} />
              </Box>
            )}
          </Box>
        )}
      </Paper>

      {/* Automatic Update Settings */}
      <Paper sx={{ p: 3 }}>
        <Typography variant="h6" gutterBottom sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <ScheduleIcon />
          Automatic Update Settings
        </Typography>

        <Grid container spacing={3}>
          <Grid item xs={12}>
            <FormControlLabel
              control={
                <Switch
                  checked={config.auto_update}
                  onChange={(e) => setConfig({ ...config, auto_update: e.target.checked })}
                />
              }
              label="Enable Automatic Updates"
            />
          </Grid>

          <Grid item xs={12} md={4}>
            <FormControl fullWidth disabled={!config.auto_update}>
              <InputLabel>Update Frequency</InputLabel>
              <Select
                value={config.update_frequency}
                onChange={(e) => setConfig({ ...config, update_frequency: e.target.value as any })}
                label="Update Frequency"
              >
                <MenuItem value="daily">Daily</MenuItem>
                <MenuItem value="weekly">Weekly (Monday)</MenuItem>
                <MenuItem value="monthly">Monthly (1st)</MenuItem>
              </Select>
            </FormControl>
          </Grid>

          <Grid item xs={12} md={4}>
            <TextField
              fullWidth
              type="time"
              label="Update Time"
              value={config.auto_update_time}
              onChange={(e) => setConfig({ ...config, auto_update_time: e.target.value })}
              disabled={!config.auto_update}
              InputLabelProps={{ shrink: true }}
            />
          </Grid>

          <Grid item xs={12} md={4}>
            {updateInfo?.next_scheduled && (
              <Alert severity="info">
                Next update: {format(new Date(updateInfo.next_scheduled), 'MMM dd, HH:mm')}
              </Alert>
            )}
          </Grid>

          <Grid item xs={12}>
            <FormControlLabel
              control={
                <Switch
                  checked={config.security_only}
                  onChange={(e) => setConfig({ ...config, security_only: e.target.checked })}
                />
              }
              label="Security Updates Only"
              disabled={!config.auto_update}
            />
          </Grid>

          <Grid item xs={12}>
            <FormControlLabel
              control={
                <Switch
                  checked={config.reboot_after_update}
                  onChange={(e) => setConfig({ ...config, reboot_after_update: e.target.checked })}
                />
              }
              label="Reboot After Updates (if required)"
              disabled={!config.auto_update}
            />
          </Grid>

          <Grid item xs={12}>
            <Button
              variant="contained"
              onClick={saveConfig}
              disabled={loading}
            >
              Save Settings
            </Button>
          </Grid>
        </Grid>

        {/* Blocked Packages */}
        {config.blocked_packages.length > 0 && (
          <Box sx={{ mt: 3 }}>
            <Typography variant="subtitle1" gutterBottom>
              Blocked Packages
            </Typography>
            <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
              {config.blocked_packages.map((pkg) => (
                <Chip
                  key={pkg}
                  label={pkg}
                  onDelete={() => removeBlockedPackage(pkg)}
                  color="default"
                  variant="outlined"
                />
              ))}
            </Box>
          </Box>
        )}
      </Paper>

      {/* Notifications */}
      {error && (
        <Alert severity="error" sx={{ mt: 2 }} onClose={() => setError('')}>
          {error}
        </Alert>
      )}
      {success && (
        <Alert severity="success" sx={{ mt: 2 }} onClose={() => setSuccess('')}>
          {success}
        </Alert>
      )}

      {/* Confirmation Dialog */}
      <Dialog open={confirmDialog} onClose={() => setConfirmDialog(false)}>
        <DialogTitle>Install Security Updates?</DialogTitle>
        <DialogContent>
          <Typography>
            This will install {updateInfo?.security_updates} security updates. 
            The music player will be temporarily paused during the update process.
          </Typography>
          <Alert severity="info" sx={{ mt: 2 }}>
            Updates will be installed with safe defaults. Critical services will be restarted automatically.
          </Alert>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirmDialog(false)}>Cancel</Button>
          <Button 
            variant="contained" 
            color="primary" 
            onClick={() => installUpdates(true)}
          >
            Install Updates
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default SystemUpdates;