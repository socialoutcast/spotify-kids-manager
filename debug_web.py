#!/usr/bin/env python3
"""
Debug script to find JavaScript issues in the web admin panel
Run this on the Pi: sudo python3 /opt/spotify-kids/debug_web.py
"""

import subprocess
import sys
import os

print("=" * 60)
print("SPOTIFY KIDS MANAGER - WEB DEBUG")
print("=" * 60)

# Check if web app is running
try:
    result = subprocess.run(['curl', '-s', 'http://localhost:8080'], capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        print("ERROR: Web server not responding on port 8080")
        print("Start it with: sudo python3 /opt/spotify-kids/web/app.py")
        sys.exit(1)
    
    html = result.stdout
    lines = html.split('\n')
    print(f"\n✓ Web server is running")
    print(f"✓ Page has {len(lines)} lines")
    
    # Check if we're seeing login page or admin page
    if "Admin Login" in html:
        print("\n⚠ Login page is shown (not logged in)")
        print("Attempting to login...")
        
        # Try to login
        login_result = subprocess.run([
            'curl', '-s', '-c', '/tmp/debug_cookies.txt',
            '-X', 'POST', 
            '-H', 'Content-Type: application/json',
            '-d', '{"username":"admin","password":"changeme"}',
            'http://localhost:8080/api/login'
        ], capture_output=True, text=True)
        
        # Get page again with cookies
        result = subprocess.run(['curl', '-s', '-b', '/tmp/debug_cookies.txt', 'http://localhost:8080'], 
                              capture_output=True, text=True)
        html = result.stdout
        lines = html.split('\n')
        
        if "Admin Panel" in html:
            print("✓ Successfully logged in")
        else:
            print("✗ Login failed - using login page for analysis")
    else:
        print("✓ Admin panel is shown")
    
    print("\n" + "=" * 60)
    print("CHECKING FOR JAVASCRIPT ISSUES")
    print("=" * 60)
    
    # Find script blocks
    in_script = False
    script_start = 0
    script_content = []
    script_blocks = []
    
    for i, line in enumerate(lines, 1):
        if '<script>' in line:
            in_script = True
            script_start = i
            script_content = []
        elif '</script>' in line:
            if in_script and script_content:
                script_blocks.append({
                    'start': script_start,
                    'end': i,
                    'content': '\n'.join(script_content)
                })
            in_script = False
        elif in_script:
            script_content.append(line)
    
    print(f"\nFound {len(script_blocks)} script blocks")
    
    # Check each script block
    for idx, block in enumerate(script_blocks, 1):
        print(f"\n--- Script Block {idx} (lines {block['start']}-{block['end']}) ---")
        
        content = block['content']
        
        # Check for syntax issues
        issues = []
        
        # Check for unmatched quotes
        double_quotes = content.count('"')
        single_quotes = content.count("'")
        if double_quotes % 2 != 0:
            issues.append(f"Unmatched double quotes (found {double_quotes})")
        if single_quotes % 2 != 0:
            issues.append(f"Unmatched single quotes (found {single_quotes})")
        
        # Check for template syntax in JS
        if '{{' in content and '}}' in content:
            template_count = content.count('{{')
            issues.append(f"Found {template_count} template variables in JavaScript")
            # Show the lines with templates
            for line_num, line in enumerate(content.split('\n'), block['start'] + 1):
                if '{{' in line:
                    print(f"  Line {line_num}: {line.strip()[:80]}")
        
        # Check for the functions we need
        required_functions = ['saveSpotifyConfig', 'testSpotifyConfig', 'restartServices', 
                            'connectBluetooth', 'disconnectBluetooth', 'removeBluetooth']
        
        for func in required_functions:
            if f'function {func}' in content:
                print(f"  ✓ {func} is defined")
            elif f'{func}(' in content:
                print(f"  ✗ {func} is CALLED but NOT DEFINED!")
                issues.append(f"{func} is called but not defined")
        
        if issues:
            print(f"\n  ⚠ ISSUES FOUND:")
            for issue in issues:
                print(f"    - {issue}")
        else:
            print("  ✓ No obvious issues")
    
    # Check around line 808 specifically
    print("\n" + "=" * 60)
    print("CHECKING LINE 808 (where browser reports error)")
    print("=" * 60)
    
    if len(lines) > 810:
        for i in range(max(0, 805), min(len(lines), 812)):
            prefix = ">>> " if i == 807 else "    "
            print(f"{prefix}Line {i+1}: {lines[i][:100]}")
    
    # Look for specific error patterns
    print("\n" + "=" * 60)
    print("SEARCHING FOR SPECIFIC PATTERNS")
    print("=" * 60)
    
    # Check if functions are in {% if logged_in %} block but being called outside
    if '{% if logged_in %}' in html:
        print("\n⚠ Found conditional template blocks")
        in_logged_in = False
        logged_in_functions = []
        
        for line in lines:
            if '{% if logged_in %}' in line:
                in_logged_in = True
            elif '{% else %}' in line or '{% endif %}' in line:
                in_logged_in = False
            elif in_logged_in and 'function ' in line:
                func_name = line.split('function ')[1].split('(')[0] if 'function ' in line else None
                if func_name:
                    logged_in_functions.append(func_name.strip())
        
        if logged_in_functions:
            print(f"Functions defined only when logged in: {', '.join(logged_in_functions)}")
    
    # Save the full page for manual inspection
    with open('/tmp/spotify_debug_page.html', 'w') as f:
        f.write(html)
    
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print("Full page saved to: /tmp/spotify_debug_page.html")
    print("\nTo manually check:")
    print("  cat /tmp/spotify_debug_page.html | grep -n 'function test'")
    print("  cat /tmp/spotify_debug_page.html | sed -n '800,820p'")
    print("\nTo see the raw file on the server:")
    print("  sudo cat /opt/spotify-kids/web/app.py | grep -n 'function test'")
    
except subprocess.TimeoutExpired:
    print("ERROR: Connection to web server timed out")
except Exception as e:
    print(f"ERROR: {e}")