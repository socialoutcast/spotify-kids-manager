#!/bin/bash
#
# Create Professional Logo for Spotify Kids Manager
#

echo "Creating professional logo designs..."
mkdir -p logos

# Design 1: Modern circular logo with play button
convert -size 512x512 xc:transparent \
    -fill '#0f0f0f' -draw "circle 256,256 256,16" \
    \( -size 480x480 radial-gradient:'#1ed760'-'#169c46' \
       -alpha set -channel A -evaluate multiply 0.95 \
    \) -geometry +16+16 -composite \
    \( -size 200x200 xc:transparent \
       -fill white \
       -draw "polygon 70,50 70,150 170,100" \
    \) -geometry +156+156 -composite \
    -font DejaVu-Sans-Bold -pointsize 42 -fill white \
    -gravity south -annotate +0+60 'SPOTIFY KIDS' \
    -resize 256x256 \
    logos/logo-modern.png

# Design 2: Shield logo with musical note
convert -size 512x512 xc:transparent \
    \( -size 400x480 xc:transparent \
       -fill '#1db954' \
       -draw "path 'M 200,40 Q 40,40 40,200 L 40,340 Q 40,440 200,480 Q 360,440 360,340 L 360,200 Q 360,40 200,40 Z'" \
    \) -geometry +56+16 -composite \
    \( -size 400x480 xc:transparent \
       -fill '#169c46' \
       -draw "path 'M 200,60 Q 60,60 60,200 L 60,330 Q 60,420 200,460 Q 340,420 340,330 L 340,200 Q 340,60 200,60 Z'" \
    \) -geometry +56+16 -composite \
    -fill white -stroke white -stroke-width 12 \
    -draw "path 'M 256,140 L 256,280 M 256,280 Q 226,260 196,260 T 166,280 Q 166,310 196,310 T 256,280'" \
    -font DejaVu-Sans-Bold -pointsize 36 -fill white \
    -gravity center -annotate +0+100 'KIDS' \
    -resize 256x256 \
    logos/logo-shield.png

# Design 3: Minimalist professional
convert -size 512x512 xc:transparent \
    \( -size 512x512 xc:'#0a0a0a' \) -composite \
    \( -size 120x120 xc:'#1ed760' \
       -draw "roundrectangle 10,10 110,110 20,20" \
    \) -geometry +196+150 -composite \
    -fill white -font DejaVu-Sans-Bold -pointsize 64 \
    -gravity center -annotate +0-20 'S' \
    -fill '#1ed760' -font DejaVu-Sans -pointsize 32 \
    -gravity center -annotate +0+80 'SPOTIFY' \
    -fill white -font DejaVu-Sans-Bold -pointsize 32 \
    -gravity center -annotate +0+120 'KIDS' \
    -resize 256x256 \
    logos/logo-minimal.png

# Design 4: Gradient orb with icon
convert -size 512x512 xc:transparent \
    \( -size 450x450 radial-gradient:'#2edf70'-'#117a37' \
       -alpha set -channel A -evaluate multiply 0.9 \
    \) -geometry +31+31 -composite \
    \( -size 450x450 xc:transparent \
       -stroke '#0a5a2a' -stroke-width 4 -fill none \
       -draw "circle 225,225 225,20" \
    \) -geometry +31+31 -composite \
    \( -size 300x300 xc:transparent \
       -fill white \
       -draw "roundrectangle 100,80 200,220 10,10" \
       -draw "circle 150,150 150,120" -compose DstOut -composite \
       -draw "polygon 130,140 130,160 170,150" \
    \) -geometry +106+106 -composite \
    -font DejaVu-Sans -pointsize 48 -fill white -stroke '#0a5a2a' -stroke-width 2 \
    -gravity south -annotate +0+40 'SpotifyKids' \
    -resize 256x256 \
    logos/logo-orb.png

# Design 5: Clean corporate style
convert -size 512x512 xc:transparent \
    -fill '#ffffff' -draw "roundrectangle 20,20 492,492 40,40" \
    -fill '#1db954' -draw "roundrectangle 30,30 482,482 35,35" \
    \( -size 200x200 xc:transparent \
       -fill white -stroke white -stroke-width 16 -stroke-linecap round \
       -draw "path 'M 100,60 L 100,140'" \
       -draw "ellipse 70,140 25,20 0,360" \
       -draw "ellipse 130,100 25,20 0,360" \
    \) -geometry +156+120 -composite \
    -font DejaVu-Sans-Bold -pointsize 56 -fill white \
    -gravity center -annotate +0+80 'SPOTIFY' \
    -font DejaVu-Sans -pointsize 42 -fill '#b3ffb3' \
    -gravity center -annotate +0+140 'KIDS MANAGER' \
    -resize 256x256 \
    logos/logo-corporate.png

echo "Created 5 professional logo designs in ./logos/"
echo ""
echo "To use a logo, copy it to the Plymouth theme:"
echo "sudo cp logos/logo-[design].png /usr/share/plymouth/themes/spotify-kids/logo.png"
echo ""
ls -la logos/