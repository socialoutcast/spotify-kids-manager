import React, { useState } from 'react';
import {
  Box,
  Stepper,
  Step,
  StepLabel,
  Button,
  Typography,
  Paper,
  TextField,
  Alert,
  CircularProgress,
  Checkbox,
  FormControlLabel,
  LinearProgress,
  Chip,
  Grid,
  Card,
  CardContent
} from '@mui/material';
import {
  Check as CheckIcon,
  Error as ErrorIcon,
  Person as PersonIcon,
  Security as SecurityIcon,
  MusicNote as MusicIcon,
  PlayArrow as PlayIcon,
  Settings as SettingsIcon
} from '@mui/icons-material';
import axios from 'axios';

const steps = [
  { label: 'System Check', icon: <SettingsIcon /> },
  { label: 'Create Kid User', icon: <PersonIcon /> },
  { label: 'Configure Spotify', icon: <MusicIcon /> },
  { label: 'Apply Security', icon: <SecurityIcon /> },
  { label: 'Enable Auto-Start', icon: <PlayIcon /> },
];

interface SetupWizardProps {
  setSetupComplete: (complete: boolean) => void;
}

const SetupWizard: React.FC<SetupWizardProps> = ({ setSetupComplete }) => {
  const [activeStep, setActiveStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  
  // Form states
  const [kidUsername, setKidUsername] = useState('kidmusic');
  const [spotifyUsername, setSpotifyUsername] = useState('');
  const [spotifyPassword, setSpotifyPassword] = useState('');
  const [systemChecks, setSystemChecks] = useState<any>({});
  const [securityOptions, setSecurityOptions] = useState({
    lockNetwork: true,
    disableTTY: true,
    immutableFiles: true,
    restrictCommands: true,
  });

  const handleNext = async () => {
    setError('');
    setSuccess('');
    setLoading(true);

    try {
      switch (activeStep) {
        case 0: // System Check
          const initResponse = await axios.post('/api/setup/initialize', {}, {
            withCredentials: true,
          });
          setSystemChecks(initResponse.data.checks);
          setSuccess('System checks completed');
          break;

        case 1: // Create Kid User
          const userResponse = await axios.post('/api/setup/create-user', {
            username: kidUsername,
          }, {
            withCredentials: true,
          });
          if (userResponse.data.success) {
            setSuccess('Kid user created successfully');
          }
          break;

        case 2: // Configure Spotify
          const spotifyResponse = await axios.post('/api/setup/configure-spotify', {
            spotify_username: spotifyUsername,
            spotify_password: spotifyPassword,
            kid_user: kidUsername,
          }, {
            withCredentials: true,
          });
          
          if (spotifyResponse.data.success) {
            // Test connection
            const testResponse = await axios.post('/api/setup/test-spotify', {}, {
              withCredentials: true,
            });
            
            if (testResponse.data.success) {
              setSuccess('Spotify configured and tested successfully');
            } else {
              throw new Error('Spotify test failed - check credentials');
            }
          }
          break;

        case 3: // Apply Security
          const securityResponse = await axios.post('/api/setup/apply-security', {
            kid_user: kidUsername,
            options: securityOptions,
          }, {
            withCredentials: true,
          });
          if (securityResponse.data.success) {
            setSuccess('Security measures applied');
          }
          break;

        case 4: // Enable Auto-Start
          const autostartResponse = await axios.post('/api/setup/enable-autostart', {
            kid_user: kidUsername,
          }, {
            withCredentials: true,
          });
          if (autostartResponse.data.success) {
            setSuccess('Auto-start enabled. Setup complete!');
            setTimeout(() => {
              setSetupComplete(true);
            }, 2000);
          }
          break;
      }

      if (activeStep < steps.length - 1) {
        setActiveStep((prevStep) => prevStep + 1);
      }
    } catch (err: any) {
      setError(err.response?.data?.error || err.message || 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  const handleBack = () => {
    setActiveStep((prevStep) => prevStep - 1);
    setError('');
    setSuccess('');
  };

  const renderStepContent = () => {
    switch (activeStep) {
      case 0: // System Check
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              System Requirements Check
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Verifying that all required components are installed and configured.
            </Typography>
            
            {Object.keys(systemChecks).length > 0 && (
              <Grid container spacing={2} sx={{ mt: 2 }}>
                {Object.entries(systemChecks).map(([check, passed]) => (
                  <Grid item xs={6} key={check}>
                    <Card variant="outlined">
                      <CardContent sx={{ display: 'flex', alignItems: 'center' }}>
                        {passed ? (
                          <CheckIcon color="success" sx={{ mr: 1 }} />
                        ) : (
                          <ErrorIcon color="error" sx={{ mr: 1 }} />
                        )}
                        <Typography>
                          {check.charAt(0).toUpperCase() + check.slice(1)}
                        </Typography>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>
            )}
          </Box>
        );

      case 1: // Create Kid User
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Create Restricted User Account
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              This user account will have limited permissions and can only run the music player.
            </Typography>
            
            <TextField
              fullWidth
              label="Username for Kid"
              value={kidUsername}
              onChange={(e) => setKidUsername(e.target.value)}
              margin="normal"
              helperText="This will be the auto-login user"
            />
            
            <Alert severity="info" sx={{ mt: 2 }}>
              The user will be created with:
              <ul>
                <li>No shell access</li>
                <li>No sudo privileges</li>
                <li>Audio group membership only</li>
                <li>Restricted to music playback</li>
              </ul>
            </Alert>
          </Box>
        );

      case 2: // Configure Spotify
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Configure Spotify Account
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Enter your child's Spotify account credentials. Premium account required.
            </Typography>
            
            <TextField
              fullWidth
              label="Spotify Username"
              value={spotifyUsername}
              onChange={(e) => setSpotifyUsername(e.target.value)}
              margin="normal"
              helperText="Not the email - find in Spotify account overview"
            />
            
            <TextField
              fullWidth
              type="password"
              label="Spotify Password"
              value={spotifyPassword}
              onChange={(e) => setSpotifyPassword(e.target.value)}
              margin="normal"
            />
            
            <Alert severity="warning" sx={{ mt: 2 }}>
              <strong>Important:</strong>
              <ul>
                <li>Use a Spotify Kids or restricted account</li>
                <li>Enable explicit content filter in Spotify settings</li>
                <li>Premium subscription required for playback control</li>
              </ul>
            </Alert>
          </Box>
        );

      case 3: // Apply Security
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Security Lockdown Options
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Select security measures to apply to the system.
            </Typography>
            
            <Box sx={{ mt: 2 }}>
              <FormControlLabel
                control={
                  <Checkbox
                    checked={securityOptions.lockNetwork}
                    onChange={(e) => setSecurityOptions({
                      ...securityOptions,
                      lockNetwork: e.target.checked
                    })}
                  />
                }
                label="Lock network configuration (prevent WiFi changes)"
              />
              
              <FormControlLabel
                control={
                  <Checkbox
                    checked={securityOptions.disableTTY}
                    onChange={(e) => setSecurityOptions({
                      ...securityOptions,
                      disableTTY: e.target.checked
                    })}
                  />
                }
                label="Disable TTY switching (prevent console access)"
              />
              
              <FormControlLabel
                control={
                  <Checkbox
                    checked={securityOptions.immutableFiles}
                    onChange={(e) => setSecurityOptions({
                      ...securityOptions,
                      immutableFiles: e.target.checked
                    })}
                  />
                }
                label="Make configuration files immutable"
              />
              
              <FormControlLabel
                control={
                  <Checkbox
                    checked={securityOptions.restrictCommands}
                    onChange={(e) => setSecurityOptions({
                      ...securityOptions,
                      restrictCommands: e.target.checked
                    })}
                  />
                }
                label="Restrict all system commands for kid user"
              />
            </Box>
            
            <Alert severity="info" sx={{ mt: 2 }}>
              These security measures ensure the device can only play music and cannot be modified.
            </Alert>
          </Box>
        );

      case 4: // Enable Auto-Start
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Enable Automatic Startup
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Configure the system to automatically start the music player on boot.
            </Typography>
            
            <Alert severity="success" sx={{ mt: 2 }}>
              <strong>Ready to complete setup!</strong>
              <br /><br />
              After this step:
              <ul>
                <li>The device will auto-login as {kidUsername}</li>
                <li>Spotify will start automatically</li>
                <li>The system will be locked down</li>
                <li>You can control playback from the web interface</li>
              </ul>
            </Alert>
            
            <Typography variant="body2" sx={{ mt: 3 }}>
              The device will reboot after applying these settings.
            </Typography>
          </Box>
        );

      default:
        return null;
    }
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        p: 3,
      }}
    >
      <Paper
        elevation={3}
        sx={{
          maxWidth: 900,
          width: '100%',
          p: 4,
          borderRadius: 2,
        }}
      >
        <Typography variant="h4" align="center" gutterBottom>
          🎵 Spotify Kids Setup Wizard
        </Typography>
        
        <Stepper activeStep={activeStep} sx={{ pt: 3, pb: 5 }}>
          {steps.map((step) => (
            <Step key={step.label}>
              <StepLabel>{step.label}</StepLabel>
            </Step>
          ))}
        </Stepper>

        {error && (
          <Alert severity="error" onClose={() => setError('')} sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}

        {success && (
          <Alert severity="success" onClose={() => setSuccess('')} sx={{ mb: 2 }}>
            {success}
          </Alert>
        )}

        <Box sx={{ minHeight: 300 }}>
          {renderStepContent()}
        </Box>

        <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 4 }}>
          <Button
            disabled={activeStep === 0}
            onClick={handleBack}
            sx={{ mr: 1 }}
          >
            Back
          </Button>
          
          <Button
            variant="contained"
            onClick={handleNext}
            disabled={loading}
            startIcon={loading && <CircularProgress size={20} />}
          >
            {activeStep === steps.length - 1 ? 'Complete Setup' : 'Next'}
          </Button>
        </Box>
      </Paper>
    </Box>
  );
};

export default SetupWizard;