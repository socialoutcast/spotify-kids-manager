import React, { useState, useEffect } from 'react';
import {
  ThemeProvider,
  createTheme,
  CssBaseline,
  Box,
  Container
} from '@mui/material';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import io from 'socket.io-client';

// Import components
import Login from './components/Login';
import SetupWizard from './components/SetupWizard';
import Dashboard from './components/Dashboard';
import ParentalControls from './components/ParentalControls';

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1DB954', // Spotify green
    },
    secondary: {
      main: '#191414',
    },
    background: {
      default: '#f5f5f5',
    },
  },
  typography: {
    fontFamily: 'Roboto, Arial, sans-serif',
    h1: {
      fontSize: '2.5rem',
      fontWeight: 600,
    },
  },
  shape: {
    borderRadius: 12,
  },
});

const socket = io();

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [setupComplete, setSetupComplete] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check authentication status
    checkAuthStatus();
    
    // Socket listeners
    socket.on('connect', () => {
      console.log('Connected to server');
    });

    socket.on('setup_status', (status: any) => {
      setSetupComplete(status.steps_completed.length >= 5);
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  const checkAuthStatus = async () => {
    try {
      const response = await fetch('/api/setup/status', {
        credentials: 'include',
      });
      
      if (response.ok) {
        setIsAuthenticated(true);
        const status = await response.json();
        setSetupComplete(status.steps_completed?.length >= 5);
      }
    } catch (error) {
      console.error('Auth check failed:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          minHeight: '100vh',
          background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        }}
      >
        <Box sx={{ color: 'white', fontSize: '1.5rem' }}>Loading...</Box>
      </Box>
    );
  }

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Router>
        <Routes>
          <Route
            path="/login"
            element={
              isAuthenticated ? (
                <Navigate to={setupComplete ? "/dashboard" : "/setup"} />
              ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
              )
            }
          />
          <Route
            path="/setup"
            element={
              isAuthenticated ? (
                <SetupWizard setSetupComplete={setSetupComplete} />
              ) : (
                <Navigate to="/login" />
              )
            }
          />
          <Route
            path="/dashboard"
            element={
              isAuthenticated && setupComplete ? (
                <Dashboard />
              ) : (
                <Navigate to={isAuthenticated ? "/setup" : "/login"} />
              )
            }
          />
          <Route
            path="/controls"
            element={
              isAuthenticated && setupComplete ? (
                <ParentalControls />
              ) : (
                <Navigate to={isAuthenticated ? "/setup" : "/login"} />
              )
            }
          />
          <Route
            path="/"
            element={
              <Navigate to={isAuthenticated ? (setupComplete ? "/dashboard" : "/setup") : "/login"} />
            }
          />
        </Routes>
      </Router>
    </ThemeProvider>
  );
}

export default App;