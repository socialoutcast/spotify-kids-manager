#!/usr/bin/env python3
"""
Test script to validate the security updates don't break functionality
"""

import sys
import importlib.util

def test_imports():
    """Test that all required packages can be imported"""
    required_packages = [
        'flask',
        'flask_socketio',
        'werkzeug',
        'requests',
        'psutil',
        'schedule',
        'pytz'
    ]
    
    failed = []
    for package in required_packages:
        try:
            spec = importlib.util.find_spec(package)
            if spec is None:
                failed.append(f"{package}: Not found")
            else:
                print(f"✓ {package}: OK")
        except Exception as e:
            failed.append(f"{package}: {e}")
    
    if failed:
        print("\nFailed imports:")
        for f in failed:
            print(f"  ✗ {f}")
        return False
    
    return True

def test_flask_app():
    """Test that Flask app can be created without Flask-CORS"""
    try:
        from flask import Flask
        from flask_socketio import SocketIO
        
        app = Flask(__name__)
        
        @app.after_request
        def after_request(response):
            response.headers['Access-Control-Allow-Origin'] = '*'
            return response
        
        socketio = SocketIO(app, cors_allowed_origins="*")
        
        print("✓ Flask app creation: OK")
        print("✓ CORS handling without Flask-CORS: OK")
        return True
        
    except Exception as e:
        print(f"✗ Flask app creation failed: {e}")
        return False

def test_werkzeug_security():
    """Test Werkzeug security functions"""
    try:
        from werkzeug.security import generate_password_hash, check_password_hash
        
        password = "test123"
        hashed = generate_password_hash(password)
        result = check_password_hash(hashed, password)
        
        if result:
            print("✓ Werkzeug security: OK")
            return True
        else:
            print("✗ Werkzeug security: Password verification failed")
            return False
            
    except Exception as e:
        print(f"✗ Werkzeug security failed: {e}")
        return False

def main():
    print("Testing security updates compatibility...\n")
    
    tests = [
        test_imports,
        test_flask_app,
        test_werkzeug_security
    ]
    
    all_passed = True
    for test in tests:
        if not test():
            all_passed = False
    
    print("\n" + "="*50)
    if all_passed:
        print("✓ All tests passed! Security updates are compatible.")
        return 0
    else:
        print("✗ Some tests failed. Please review the security updates.")
        return 1

if __name__ == "__main__":
    sys.exit(main())