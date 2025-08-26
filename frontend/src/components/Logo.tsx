import React from 'react';
import { Box, SvgIcon, Typography } from '@mui/material';

interface LogoProps {
  size?: 'small' | 'medium' | 'large';
  showText?: boolean;
  color?: 'primary' | 'white' | 'gradient';
}

const Logo: React.FC<LogoProps> = ({ 
  size = 'medium', 
  showText = true, 
  color = 'primary' 
}) => {
  const sizes = {
    small: { icon: 32, text: 'h6' as const },
    medium: { icon: 48, text: 'h5' as const },
    large: { icon: 64, text: 'h4' as const }
  };

  const currentSize = sizes[size];

  const getColor = () => {
    switch(color) {
      case 'white':
        return '#ffffff';
      case 'gradient':
        return 'url(#gradient)';
      default:
        return '#1DB954';
    }
  };

  return (
    <Box 
      sx={{ 
        display: 'flex', 
        alignItems: 'center', 
        gap: 2,
        userSelect: 'none'
      }}
    >
      <SvgIcon 
        sx={{ 
          fontSize: currentSize.icon,
          color: color === 'gradient' ? 'transparent' : getColor()
        }}
        viewBox="0 0 100 100"
      >
        <defs>
          <linearGradient id="gradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style={{ stopColor: '#1DB954', stopOpacity: 1 }} />
            <stop offset="100%" style={{ stopColor: '#1ed760', stopOpacity: 1 }} />
          </linearGradient>
          <linearGradient id="shield-gradient" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style={{ stopColor: '#667eea', stopOpacity: 1 }} />
            <stop offset="100%" style={{ stopColor: '#764ba2', stopOpacity: 1 }} />
          </linearGradient>
        </defs>
        
        {/* Shield shape for security */}
        <path
          d="M50 5 L80 20 L80 55 C80 70 65 85 50 90 C35 85 20 70 20 55 L20 20 Z"
          fill="url(#shield-gradient)"
          opacity="0.9"
        />
        
        {/* Music note in center */}
        <g transform="translate(50, 45)">
          {/* Note stem */}
          <rect x="-2" y="-25" width="4" height="30" fill="#ffffff" />
          
          {/* Note flag */}
          <path
            d="M2 -25 Q15 -20 12 -10"
            stroke="#ffffff"
            strokeWidth="3"
            fill="none"
          />
          
          {/* Note head */}
          <ellipse cx="-5" cy="5" rx="7" ry="5" fill="#ffffff" transform="rotate(-20)" />
        </g>
        
        {/* Kids icon - small smiley */}
        <circle cx="50" cy="65" r="8" fill="#FFD700" />
        <circle cx="46" cy="63" r="1.5" fill="#333" />
        <circle cx="54" cy="63" r="1.5" fill="#333" />
        <path
          d="M45 67 Q50 70 55 67"
          stroke="#333"
          strokeWidth="1.5"
          fill="none"
          strokeLinecap="round"
        />
      </SvgIcon>

      {showText && (
        <Box>
          <Typography 
            variant={currentSize.text}
            sx={{
              fontWeight: 700,
              background: color === 'gradient' 
                ? 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)'
                : getColor(),
              backgroundClip: color === 'gradient' ? 'text' : 'unset',
              textFillColor: color === 'gradient' ? 'transparent' : 'unset',
              WebkitBackgroundClip: color === 'gradient' ? 'text' : 'unset',
              WebkitTextFillColor: color === 'gradient' ? 'transparent' : 'unset',
              color: color === 'gradient' ? 'transparent' : getColor(),
              letterSpacing: '-0.5px'
            }}
          >
            Spotify Kids
          </Typography>
          <Typography 
            variant="caption"
            sx={{
              fontWeight: 500,
              color: color === 'white' ? 'rgba(255,255,255,0.8)' : 'text.secondary',
              letterSpacing: '1px',
              textTransform: 'uppercase',
              fontSize: size === 'small' ? '0.6rem' : size === 'medium' ? '0.7rem' : '0.8rem'
            }}
          >
            Manager
          </Typography>
        </Box>
      )}
    </Box>
  );
};

export default Logo;