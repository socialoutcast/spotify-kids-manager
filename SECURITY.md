# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Spotify Kids Manager, please report it by:

1. **Email**: Send details to [security contact email]
2. **GitHub**: Open a security advisory in the Security tab

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Security Measures

This application implements multiple security layers:

### Application Security
- Session-based authentication with secure cookies
- Password hashing using Werkzeug security
- Input validation and sanitization
- CORS protection

### Container Security
- Runs with minimal required privileges
- Regular security updates via automated update manager
- Isolated Docker environment
- Network segmentation

### Dependencies
- Regular dependency updates
- Automated vulnerability scanning
- Pinned versions for reproducible builds

## Security Best Practices

When deploying Spotify Kids Manager:

1. **Change Default Credentials**: Always change the default admin/changeme credentials immediately after installation
2. **Use HTTPS**: Deploy behind a reverse proxy with SSL/TLS when exposed to the internet
3. **Network Security**: Limit access to port 8080 to trusted networks only
4. **Regular Updates**: Enable automatic security updates in the web interface
5. **Spotify Credentials**: Use a dedicated Spotify account with a strong, unique password
6. **Physical Security**: If using for children, ensure the device is physically secured

## Update Policy

Security updates are released as soon as vulnerabilities are discovered and patched. The application includes an automatic update manager that can be configured to install security updates automatically.