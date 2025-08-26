import React, { useState } from 'react';
import {
  Box,
  Paper,
  Typography,
  Switch,
  FormControlLabel,
  Button,
  Grid,
  TextField,
  Alert,
  Card,
  CardContent,
  Divider
} from '@mui/material';
import {
  Block as BlockIcon,
  Schedule as ScheduleIcon,
  Timer as TimerIcon,
  VolumeOff as MuteIcon
} from '@mui/icons-material';
import axios from 'axios';

const ParentalControls: React.FC = () => {
  const [spotifyBlocked, setSpotifyBlocked] = useState(false);
  const [schedule, setSchedule] = useState({
    enabled: false,
    startTime: '07:00',
    endTime: '20:00'
  });
  const [dailyLimit, setDailyLimit] = useState({
    enabled: false,
    hours: 2
  });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  const handleBlockSpotify = async () => {
    setLoading(true);
    try {
      const response = await axios.post('/api/control/block-spotify', {
        block: !spotifyBlocked
      }, {
        withCredentials: true
      });
      
      setSpotifyBlocked(!spotifyBlocked);
      setMessage(spotifyBlocked ? 'Spotify unblocked' : 'Spotify blocked');
    } catch (error) {
      setMessage('Failed to change Spotify status');
    } finally {
      setLoading(false);
    }
  };

  const saveSchedule = async () => {
    setLoading(true);
    try {
      await axios.post('/api/control/schedule', schedule, {
        withCredentials: true
      });
      setMessage('Schedule saved successfully');
    } catch (error) {
      setMessage('Failed to save schedule');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box>
      <Typography variant="h5" gutterBottom>
        Parental Controls
      </Typography>

      {message && (
        <Alert severity="info" onClose={() => setMessage('')} sx={{ mb: 2 }}>
          {message}
        </Alert>
      )}

      <Grid container spacing={3}>
        {/* Spotify Blocking */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <BlockIcon color="error" sx={{ mr: 1 }} />
                <Typography variant="h6">
                  Spotify Access Control
                </Typography>
              </Box>
              
              <Typography variant="body2" color="text.secondary" paragraph>
                Immediately block or allow Spotify access
              </Typography>
              
              <Button
                fullWidth
                variant="contained"
                color={spotifyBlocked ? 'error' : 'success'}
                onClick={handleBlockSpotify}
                disabled={loading}
                size="large"
              >
                {spotifyBlocked ? 'Spotify is BLOCKED' : 'Spotify is ALLOWED'}
              </Button>
            </CardContent>
          </Card>
        </Grid>

        {/* Time Schedule */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <ScheduleIcon color="primary" sx={{ mr: 1 }} />
                <Typography variant="h6">
                  Daily Schedule
                </Typography>
              </Box>
              
              <FormControlLabel
                control={
                  <Switch
                    checked={schedule.enabled}
                    onChange={(e) => setSchedule({
                      ...schedule,
                      enabled: e.target.checked
                    })}
                  />
                }
                label="Enable scheduled access"
              />
              
              <Box sx={{ mt: 2, display: 'flex', gap: 2 }}>
                <TextField
                  type="time"
                  label="Start Time"
                  value={schedule.startTime}
                  onChange={(e) => setSchedule({
                    ...schedule,
                    startTime: e.target.value
                  })}
                  disabled={!schedule.enabled}
                  fullWidth
                />
                <TextField
                  type="time"
                  label="End Time"
                  value={schedule.endTime}
                  onChange={(e) => setSchedule({
                    ...schedule,
                    endTime: e.target.value
                  })}
                  disabled={!schedule.enabled}
                  fullWidth
                />
              </Box>
              
              <Button
                variant="outlined"
                onClick={saveSchedule}
                sx={{ mt: 2 }}
                disabled={!schedule.enabled || loading}
              >
                Save Schedule
              </Button>
            </CardContent>
          </Card>
        </Grid>

        {/* Daily Limit */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <TimerIcon color="primary" sx={{ mr: 1 }} />
                <Typography variant="h6">
                  Daily Time Limit
                </Typography>
              </Box>
              
              <FormControlLabel
                control={
                  <Switch
                    checked={dailyLimit.enabled}
                    onChange={(e) => setDailyLimit({
                      ...dailyLimit,
                      enabled: e.target.checked
                    })}
                  />
                }
                label="Enable daily limit"
              />
              
              <TextField
                type="number"
                label="Hours per day"
                value={dailyLimit.hours}
                onChange={(e) => setDailyLimit({
                  ...dailyLimit,
                  hours: parseInt(e.target.value) || 0
                })}
                disabled={!dailyLimit.enabled}
                fullWidth
                sx={{ mt: 2 }}
                inputProps={{ min: 1, max: 24 }}
              />
            </CardContent>
          </Card>
        </Grid>

        {/* Quick Mute */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <MuteIcon color="primary" sx={{ mr: 1 }} />
                <Typography variant="h6">
                  Quick Actions
                </Typography>
              </Box>
              
              <Grid container spacing={2}>
                <Grid item xs={6}>
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={() => handleBlockSpotify()}
                  >
                    Pause 15 Min
                  </Button>
                </Grid>
                <Grid item xs={6}>
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={() => handleBlockSpotify()}
                  >
                    Pause 1 Hour
                  </Button>
                </Grid>
                <Grid item xs={6}>
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={() => handleBlockSpotify()}
                  >
                    Mute Now
                  </Button>
                </Grid>
                <Grid item xs={6}>
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={() => handleBlockSpotify()}
                  >
                    Skip Song
                  </Button>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default ParentalControls;