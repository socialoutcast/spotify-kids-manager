#!/bin/bash
#
# Spotify Kids Manager - Bootsplash Setup
# Creates and installs a custom boot splash screen
#

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Setting up Spotify Kids Manager boot splash..."

# Install required packages
apt-get update
apt-get install -y plymouth plymouth-themes imagemagick

# Create theme directory
THEME_DIR="/usr/share/plymouth/themes/spotify-kids"
mkdir -p "$THEME_DIR"

# Create the SVG logo
cat > "$THEME_DIR/logo.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="256" height="256" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
  <!-- Background circle -->
  <circle cx="128" cy="128" r="120" fill="#1db954"/>
  
  <!-- Music note icon -->
  <g transform="translate(128,128)">
    <!-- Note stem -->
    <rect x="20" y="-60" width="8" height="80" fill="white"/>
    
    <!-- Note head 1 -->
    <ellipse cx="0" cy="20" rx="20" ry="15" fill="white"/>
    
    <!-- Note head 2 -->
    <ellipse cx="24" cy="0" rx="20" ry="15" fill="white"/>
    
    <!-- Note flag -->
    <path d="M 24,-60 Q 40,-50 35,-30 T 28,-10" 
          fill="none" stroke="white" stroke-width="6"/>
  </g>
  
  <!-- Kids text -->
  <text x="128" y="200" font-family="Arial, sans-serif" font-size="24" 
        font-weight="bold" fill="white" text-anchor="middle">KIDS</text>
</svg>
EOF

# Convert SVG to PNG in various sizes
convert "$THEME_DIR/logo.svg" -resize 256x256 "$THEME_DIR/logo.png"
convert "$THEME_DIR/logo.svg" -resize 128x128 "$THEME_DIR/logo-128.png"
convert "$THEME_DIR/logo.svg" -resize 64x64 "$THEME_DIR/logo-64.png"

# Create spinner animation frames
for i in {0..11}; do
    angle=$((i * 30))
    cat > "$THEME_DIR/spinner-$i.svg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
  <g transform="rotate($angle 32 32)">
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="1"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.9" transform="rotate(30 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.8" transform="rotate(60 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.7" transform="rotate(90 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.6" transform="rotate(120 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.5" transform="rotate(150 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.4" transform="rotate(180 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.3" transform="rotate(210 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.2" transform="rotate(240 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.1" transform="rotate(270 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.1" transform="rotate(300 32 32)"/>
    <circle cx="32" cy="8" r="4" fill="#1db954" opacity="0.1" transform="rotate(330 32 32)"/>
  </g>
</svg>
EOF
    convert "$THEME_DIR/spinner-$i.svg" -resize 64x64 "$THEME_DIR/spinner-$(printf "%02d" $i).png"
done

# Create progress bar background
convert -size 400x20 xc:'#333333' "$THEME_DIR/progress-bar-bg.png"
convert -size 400x20 xc:'#1db954' "$THEME_DIR/progress-bar-fg.png"

# Create the Plymouth theme script
cat > "$THEME_DIR/spotify-kids.script" <<'EOF'
# Spotify Kids Manager Plymouth Theme

# Set background color (dark gray)
Window.SetBackgroundTopColor(0.1, 0.1, 0.1);
Window.SetBackgroundBottomColor(0.05, 0.05, 0.05);

# Load logo
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 50);

# Create spinner
spinner.count = 12;
for (i = 0; i < spinner.count; i++) {
    spinner[i].image = Image("spinner-" + i + ".png");
}
spinner.current = 0;
spinner.sprite = Sprite();
spinner.sprite.SetX(Window.GetWidth() / 2 - 32);
spinner.sprite.SetY(Window.GetHeight() / 2 + 100);

# Progress bar
progress_bar_bg.image = Image("progress-bar-bg.png");
progress_bar_bg.sprite = Sprite(progress_bar_bg.image);
progress_bar_bg.sprite.SetX(Window.GetWidth() / 2 - 200);
progress_bar_bg.sprite.SetY(Window.GetHeight() / 2 + 180);

progress_bar_fg.original = Image("progress-bar-fg.png");
progress_bar_fg.sprite = Sprite();
progress_bar_fg.sprite.SetX(Window.GetWidth() / 2 - 200);
progress_bar_fg.sprite.SetY(Window.GetHeight() / 2 + 180);

# Message
message_sprite = Sprite();
message_sprite.SetX(Window.GetWidth() / 2 - 100);
message_sprite.SetY(Window.GetHeight() / 2 + 220);

# Animation function
fun refresh_callback() {
    spinner.current++;
    if (spinner.current >= spinner.count) 
        spinner.current = 0;
    spinner.sprite.SetImage(spinner[spinner.current].image);
}

# Progress function
fun progress_callback(duration, progress) {
    if (progress_bar_fg.original) {
        progress_bar_fg.image = progress_bar_fg.original.Scale(400 * progress, 20);
        progress_bar_fg.sprite.SetImage(progress_bar_fg.image);
    }
}

# Message function
fun message_callback(text) {
    message_image = Image.Text(text, 1, 1, 1);
    message_sprite.SetImage(message_image);
}

# Set callbacks
Plymouth.SetRefreshFunction(refresh_callback);
Plymouth.SetBootProgressFunction(progress_callback);
Plymouth.SetUpdateStatusFunction(message_callback);
EOF

# Create the Plymouth theme file
cat > "$THEME_DIR/spotify-kids.plymouth" <<EOF
[Plymouth Theme]
Name=Spotify Kids Manager
Description=Boot splash for Spotify Kids Manager
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/spotify-kids
ScriptFile=/usr/share/plymouth/themes/spotify-kids/spotify-kids.script
EOF

# Install the theme
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
    /usr/share/plymouth/themes/spotify-kids/spotify-kids.plymouth 100

# Set as default theme
plymouth-set-default-theme -R spotify-kids

# Update initramfs to include the new theme
update-initramfs -u

# Enable Plymouth splash
# For Raspberry Pi, we need to modify cmdline.txt
CMDLINE="/boot/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    # Backup original
    cp "$CMDLINE" "${CMDLINE}.backup"
    
    # Check if plymouth is already configured
    if ! grep -q "splash" "$CMDLINE"; then
        # Add splash parameters
        sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles/' "$CMDLINE"
    fi
    
    # Remove any console=tty1 to hide boot messages
    sed -i 's/console=tty1/console=tty3/' "$CMDLINE"
fi

# For standard systems, modify GRUB
if [ -f /etc/default/grub ]; then
    # Backup original
    cp /etc/default/grub /etc/default/grub.backup
    
    # Add splash screen parameters
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    
    # Set resolution for better splash
    sed -i 's/#GRUB_GFXMODE=.*/GRUB_GFXMODE=1024x768/' /etc/default/grub
    
    # Update GRUB
    update-grub
fi

echo "============================================"
echo "Boot splash installation complete!"
echo ""
echo "The system will now show the Spotify Kids"
echo "logo during boot."
echo ""
echo "Note: A reboot is required for changes to"
echo "take effect."
echo "============================================"