#!/bin/bash

# Resolve Swift Package Dependencies
# This script opens the project in Xcode, which will automatically resolve packages

PROJECT_DIR="/Users/jimlocke/Desktop/ARGOS - Project HeartID/HeartID Apps/HeartID_folder/HeartID Mobile Nov 4 - No Tech Menu (Backup Sep 17 1130)/Cardiac ID/CardiacID"

echo "Opening CardiacID project in Xcode..."
echo "Xcode will automatically resolve the following packages:"
echo "  - Supabase Swift SDK v2.37.0+"
echo "  - MSAL (Microsoft Authentication Library) v2.5.1+"
echo "  - Swift Algorithms v1.2.1+"
echo ""
echo "This may take 1-2 minutes..."
echo ""

# Open the project
open "$PROJECT_DIR/CardiacID.xcodeproj"

echo "✅ Project opened in Xcode"
echo ""
echo "Next steps in Xcode:"
echo "1. Wait for package resolution to complete (watch the status bar)"
echo "2. If prompted, click 'Resolve Package Versions'"
echo "3. Once resolved, clean build folder (Shift+Cmd+K)"
echo "4. Build the project (Cmd+B)"
echo ""
echo "The import errors should now be fixed!"
