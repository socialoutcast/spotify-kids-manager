import React, { useState, useEffect } from 'react';
import {
  Box,
  Container,
  Grid,
  Paper,
  Typography,
  IconButton,
  Button,
  Card,
  CardContent,
  CardActions,
  Chip,
  LinearProgress,
  AppBar,
  Toolbar,
  Drawer,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  ListItemButton,
  Divider,
  Avatar,
  Badge,
  Tooltip
} from '@mui/material';
import {
  PlayArrow as PlayIcon,
  Pause as PauseIcon,
  SkipNext as NextIcon,
  SkipPrevious as PrevIcon,
  VolumeUp as VolumeIcon,
  Block as BlockIcon,
  Dashboard as DashboardIcon,
  Security as SecurityIcon,
  Schedule as ScheduleIcon,
  Assessment as StatsIcon,
  Settings as SettingsIcon,
  ExitToApp as LogoutIcon,
  Menu as MenuIcon,
  MusicNote as MusicIcon,
  Update as UpdateIcon,
  CheckCircle as CheckIcon,
  Warning as WarningIcon,
  Shield as ShieldIcon
} from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';
import axios from 'axios';

// Import components
import Logo from './Logo';
import ParentalControls from './ParentalControls';
import SystemUpdates from './SystemUpdates';

const Dashboard: React.FC = () => {
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [currentView, setCurrentView] = useState('overview');
  const [playing, setPlaying] = useState(false);
  const [volume, setVolume] = useState(50);
  const [currentTrack, setCurrentTrack] = useState('No track playing');
  const [spotifyBlocked, setSpotifyBlocked] = useState(false);
  const [stats, setStats] = useState<any>(null);
  const [systemHealth, setSystemHealth] = useState<any>(null);
  const [updateBadge, setUpdateBadge] = useState(0);

  useEffect(() => {
    loadDashboardData();
    checkForUpdates();
    const interval = setInterval(loadDashboardData, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  const loadDashboardData = async () => {
    try {
      // Get usage stats
      const statsResponse = await axios.get('/api/stats/usage', {
        withCredentials: true
      });
      setStats(statsResponse.data);

      // Get system health
      const healthResponse = await axios.get('/api/updates/health', {
        withCredentials: true
      });
      setSystemHealth(healthResponse.data);
    } catch (error) {
      console.error('Failed to load dashboard data:', error);
    }
  };

  const checkForUpdates = async () => {
    try {
      const response = await axios.get('/api/updates/check', {
        withCredentials: true
      });
      setUpdateBadge(response.data.security_updates || 0);
    } catch (error) {
      console.error('Failed to check updates:', error);
    }
  };

  const handlePlaybackControl = async (action: string) => {
    try {
      await axios.post('/api/control/playback', { action }, {
        withCredentials: true
      });
      
      if (action === 'play' || action === 'pause') {
        setPlaying(!playing);
      }
    } catch (error) {
      console.error('Playback control failed:', error);
    }
  };

  const handleBlockSpotify = async () => {
    try {
      await axios.post('/api/control/block-spotify', {
        block: !spotifyBlocked
      }, {
        withCredentials: true
      });
      setSpotifyBlocked(!spotifyBlocked);
    } catch (error) {
      console.error('Failed to block/unblock Spotify:', error);
    }
  };

  const handleLogout = async () => {
    try {
      await axios.post('/api/logout', {}, {
        withCredentials: true
      });
      navigate('/login');
    } catch (error) {
      console.error('Logout failed:', error);
    }
  };

  const menuItems = [
    { id: 'overview', label: 'Overview', icon: <DashboardIcon /> },
    { id: 'controls', label: 'Parental Controls', icon: <SecurityIcon /> },
    { id: 'updates', label: 'System Updates', icon: <UpdateIcon />, badge: updateBadge },
    { id: 'schedule', label: 'Schedule', icon: <ScheduleIcon /> },
    { id: 'stats', label: 'Statistics', icon: <StatsIcon /> },
    { id: 'settings', label: 'Settings', icon: <SettingsIcon /> }
  ];

  const renderContent = () => {
    switch (currentView) {
      case 'controls':
        return <ParentalControls />;
      case 'updates':
        return <SystemUpdates />;
      case 'overview':
      default:
        return (
          <Grid container spacing={3}>
            {/* System Status */}
            <Grid item xs={12}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    System Status
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} md={3}>
                      <Box sx={{ textAlign: 'center' }}>
                        <ShieldIcon 
                          sx={{ 
                            fontSize: 48, 
                            color: systemHealth?.healthy ? 'success.main' : 'warning.main' 
                          }} 
                        />
                        <Typography variant="body2">
                          Security: {systemHealth?.healthy ? 'Protected' : 'Check Required'}
                        </Typography>
                      </Box>
                    </Grid>
                    <Grid item xs={12} md={3}>
                      <Box sx={{ textAlign: 'center' }}>
                        <MusicIcon 
                          sx={{ 
                            fontSize: 48, 
                            color: playing ? 'primary.main' : 'action.disabled' 
                          }} 
                        />
                        <Typography variant="body2">
                          Music: {playing ? 'Playing' : 'Paused'}
                        </Typography>
                      </Box>
                    </Grid>
                    <Grid item xs={12} md={3}>
                      <Box sx={{ textAlign: 'center' }}>
                        <Badge badgeContent={updateBadge} color="error">
                          <UpdateIcon sx={{ fontSize: 48, color: 'info.main' }} />
                        </Badge>
                        <Typography variant="body2">
                          Updates: {updateBadge > 0 ? `${updateBadge} Available` : 'Up to Date'}
                        </Typography>
                      </Box>
                    </Grid>
                    <Grid item xs={12} md={3}>
                      <Box sx={{ textAlign: 'center' }}>
                        {spotifyBlocked ? (
                          <BlockIcon sx={{ fontSize: 48, color: 'error.main' }} />
                        ) : (
                          <CheckIcon sx={{ fontSize: 48, color: 'success.main' }} />
                        )}
                        <Typography variant="body2">
                          Spotify: {spotifyBlocked ? 'Blocked' : 'Active'}
                        </Typography>
                      </Box>
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>
            </Grid>

            {/* Playback Controls */}
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Playback Controls
                  </Typography>
                  <Box sx={{ textAlign: 'center', py: 2 }}>
                    <Typography variant="body1" gutterBottom>
                      {currentTrack}
                    </Typography>
                    <Box sx={{ display: 'flex', justifyContent: 'center', gap: 1, mt: 2 }}>
                      <IconButton 
                        onClick={() => handlePlaybackControl('previous')}
                        size="large"
                      >
                        <PrevIcon />
                      </IconButton>
                      <IconButton 
                        onClick={() => handlePlaybackControl(playing ? 'pause' : 'play')}
                        size="large"
                        color="primary"
                      >
                        {playing ? <PauseIcon sx={{ fontSize: 40 }} /> : <PlayIcon sx={{ fontSize: 40 }} />}
                      </IconButton>
                      <IconButton 
                        onClick={() => handlePlaybackControl('next')}
                        size="large"
                      >
                        <NextIcon />
                      </IconButton>
                    </Box>
                  </Box>
                </CardContent>
                <CardActions>
                  <Button
                    fullWidth
                    variant={spotifyBlocked ? 'contained' : 'outlined'}
                    color={spotifyBlocked ? 'error' : 'primary'}
                    startIcon={<BlockIcon />}
                    onClick={handleBlockSpotify}
                  >
                    {spotifyBlocked ? 'Unblock Spotify' : 'Block Spotify'}
                  </Button>
                </CardActions>
              </Card>
            </Grid>

            {/* Usage Stats */}
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Today's Usage
                  </Typography>
                  {stats ? (
                    <Box>
                      <Box sx={{ mb: 2 }}>
                        <Typography variant="body2" color="text.secondary">
                          Total Playtime
                        </Typography>
                        <Typography variant="h4">
                          {stats.total_playtime || '0h 0m'}
                        </Typography>
                      </Box>
                      <Grid container spacing={2}>
                        <Grid item xs={6}>
                          <Typography variant="body2" color="text.secondary">
                            Songs Played
                          </Typography>
                          <Typography variant="h6">
                            {stats.songs_played || 0}
                          </Typography>
                        </Grid>
                        <Grid item xs={6}>
                          <Typography variant="body2" color="text.secondary">
                            Favorite Playlist
                          </Typography>
                          <Typography variant="h6">
                            {stats.favorite_playlist || 'None'}
                          </Typography>
                        </Grid>
                      </Grid>
                    </Box>
                  ) : (
                    <Typography>Loading stats...</Typography>
                  )}
                </CardContent>
              </Card>
            </Grid>

            {/* Quick Actions */}
            <Grid item xs={12}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Quick Actions
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={6} md={3}>
                      <Button
                        fullWidth
                        variant="outlined"
                        onClick={() => setCurrentView('schedule')}
                      >
                        Set Schedule
                      </Button>
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Button
                        fullWidth
                        variant="outlined"
                        onClick={() => setCurrentView('stats')}
                      >
                        View Full Stats
                      </Button>
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Button
                        fullWidth
                        variant="outlined"
                        onClick={() => setCurrentView('updates')}
                        color={updateBadge > 0 ? 'error' : 'primary'}
                      >
                        Check Updates {updateBadge > 0 && `(${updateBadge})`}
                      </Button>
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Button
                        fullWidth
                        variant="outlined"
                        onClick={() => setCurrentView('settings')}
                      >
                        Settings
                      </Button>
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>
            </Grid>
          </Grid>
        );
    }
  };

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      {/* App Bar */}
      <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}>
        <Toolbar>
          <IconButton
            color="inherit"
            edge="start"
            onClick={() => setDrawerOpen(!drawerOpen)}
            sx={{ mr: 2 }}
          >
            <MenuIcon />
          </IconButton>
          <Logo size="small" showText={true} color="white" />
          <Box sx={{ flexGrow: 1 }} />
          <Tooltip title="System Health">
            <IconButton color="inherit">
              {systemHealth?.healthy ? (
                <CheckIcon />
              ) : (
                <WarningIcon color="warning" />
              )}
            </IconButton>
          </Tooltip>
          <Tooltip title="Logout">
            <IconButton color="inherit" onClick={handleLogout}>
              <LogoutIcon />
            </IconButton>
          </Tooltip>
        </Toolbar>
      </AppBar>

      {/* Drawer */}
      <Drawer
        variant="temporary"
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        sx={{
          width: 240,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: 240,
            boxSizing: 'border-box',
            mt: 8
          },
        }}
      >
        <List>
          {menuItems.map((item) => (
            <ListItemButton
              key={item.id}
              selected={currentView === item.id}
              onClick={() => {
                setCurrentView(item.id);
                setDrawerOpen(false);
              }}
            >
              <ListItemIcon>
                {item.badge ? (
                  <Badge badgeContent={item.badge} color="error">
                    {item.icon}
                  </Badge>
                ) : (
                  item.icon
                )}
              </ListItemIcon>
              <ListItemText primary={item.label} />
            </ListItemButton>
          ))}
        </List>
        <Divider />
        <List>
          <ListItem>
            <ListItemIcon>
              <Avatar sx={{ width: 32, height: 32, bgcolor: 'primary.main' }}>
                A
              </Avatar>
            </ListItemIcon>
            <ListItemText 
              primary="Admin" 
              secondary="Administrator"
            />
          </ListItem>
        </List>
      </Drawer>

      {/* Main Content */}
      <Box component="main" sx={{ flexGrow: 1, p: 3, mt: 8 }}>
        <Container maxWidth="lg">
          {renderContent()}
        </Container>
      </Box>
    </Box>
  );
};

export default Dashboard;