#!/bin/bash

# Quick test for overlay visibility
# This script will build and run the app to test

cd "/Users/steveyeh/projects/PDFviewer/PDFViewer"

echo "Building PDFViewer for macOS..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme PDFViewer \
    -destination 'platform=macOS' \
    -configuration Debug \
    build

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded!"
    echo ""
    echo "Testing instructions:"
    echo "1. Open a PDF file"  
    echo "2. Look at the LEFT and RIGHT edges - you should see faint chevron icons"
    echo "3. Hover over them - they should get brighter"
    echo "4. Press LEFT/RIGHT arrow keys - should navigate pages"
    echo ""
    echo "If overlay is NOT visible:"
    echo "- The overlay might be transparent/invisible"
    echo "- Check if currentPage and totalPages have correct values"
    echo ""
    echo "If arrow keys don't work:"
    echo "- Click inside the PDF view first to give it focus"
    echo "- Make sure you're testing on macOS (iPad doesn't have arrow keys)"
else
    echo "❌ Build failed"
    exit 1
fi
