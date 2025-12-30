#!/bin/bash

# CardiacID Build Fix Script
# Run this script to fix all build issues

echo "🚀 CardiacID Build Fix Script"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
PROJECT_PATH="/Users/jimlocke/Desktop/ARGOS - Project HeartID"
WORKING_FOLDER="/Users/jimlocke/Desktop/Working_folder/CardiacID"

echo -e "${BLUE}📁 Project Path: ${PROJECT_PATH}${NC}"
echo -e "${BLUE}📁 Working Folder: ${WORKING_FOLDER}${NC}"

# Step 1: Clean all build artifacts
echo -e "\n${YELLOW}🧹 Step 1: Cleaning build artifacts...${NC}"

if [ -d "$PROJECT_PATH" ]; then
    cd "$PROJECT_PATH"
    echo "✅ Changed to project directory"
else
    echo -e "${RED}❌ Project directory not found${NC}"
    exit 1
fi

# Remove build artifacts
echo "🗑️ Removing DerivedData..."
rm -rf DerivedData
rm -rf Build
rm -rf /Users/jimlocke/Desktop/Build

# Clean Xcode derived data
echo "🗑️ Cleaning Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-*

# Clean Swift Package Manager cache
echo "🗑️ Cleaning Swift Package Manager cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf ~/Library/org.swift.swiftpm/

# Clean module cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

echo -e "${GREEN}✅ Build artifacts cleaned${NC}"

# Step 2: Create missing files in working folder
echo -e "\n${YELLOW}🔧 Step 2: Ensuring all required files exist...${NC}"

# Create working folder if it doesn't exist
if [ ! -d "$WORKING_FOLDER" ]; then
    echo "📁 Creating working folder..."
    mkdir -p "$WORKING_FOLDER"
fi

# Check if SecureCredentialManager.swift exists in working folder
if [ ! -f "$WORKING_FOLDER/SecureCredentialManager.swift" ]; then
    echo -e "${RED}❌ SecureCredentialManager.swift not found in working folder${NC}"
    echo -e "${BLUE}💡 Please copy SecureCredentialManager.swift to: ${WORKING_FOLDER}${NC}"
else
    echo -e "${GREEN}✅ SecureCredentialManager.swift found${NC}"
fi

# Step 3: Verify file permissions
echo -e "\n${YELLOW}🔒 Step 3: Setting correct file permissions...${NC}"
if [ -d "$WORKING_FOLDER" ]; then
    chmod -R 755 "$WORKING_FOLDER"
    echo -e "${GREEN}✅ File permissions set${NC}"
fi

# Step 4: Reset simulators
echo -e "\n${YELLOW}📱 Step 4: Resetting simulators...${NC}"
xcrun simctl shutdown all
xcrun simctl erase all
echo -e "${GREEN}✅ Simulators reset${NC}"

# Step 5: Provide manual steps
echo -e "\n${BLUE}📋 MANUAL STEPS TO COMPLETE IN XCODE:${NC}"
echo "=================================="

cat << EOF

${YELLOW}1. Open Xcode and your CardiacID project${NC}

${YELLOW}2. Clean Build Folder:${NC}
   • Product → Clean Build Folder (⌘+Shift+K)

${YELLOW}3. Reset Package Caches:${NC}
   • File → Packages → Reset Package Caches

${YELLOW}4. Fix File References:${NC}
   a) Look for red files in Project Navigator
   b) If SecureCredentialManager.swift is red/missing:
      • Right-click → Delete → "Remove Reference"
      • Right-click on project → "Add Files to CardiacID"
      • Navigate to: ${WORKING_FOLDER}
      • Select SecureCredentialManager.swift
      • ✅ Check "Copy items if needed"
      • ✅ Select both iOS and watchOS targets
      • Click "Add"

${YELLOW}5. Verify Target Membership:${NC}
   a) Select SecureCredentialManager.swift in Project Navigator
   b) Check File Inspector (right panel)
   c) Under "Target Membership":
      • ✅ CardiacID (iOS target)
      • ✅ CardiacID WatchKit Extension (watchOS target)
      • Make sure it's checked ONLY ONCE for each target

${YELLOW}6. Verify Package Dependencies:${NC}
   a) Project Settings → Package Dependencies
   b) MSAL should be listed
   c) Click on MSAL → Check "Add to Target"
   d) ✅ iOS target should be checked
   e) ❌ watchOS target should be UNCHECKED

${YELLOW}7. Check App Groups:${NC}
   iOS Target:
   • Signing & Capabilities → App Groups
   • ✅ group.com.argos.cardiacid
   
   watchOS Target:
   • Signing & Capabilities → App Groups
   • ✅ group.com.argos.cardiacid

${YELLOW}8. Build Order:${NC}
   a) Select iOS target and build (⌘+B)
   b) If successful, select watchOS target and build (⌘+B)

${GREEN}9. Success Indicators:${NC}
   • No red files in Project Navigator
   • No build errors
   • Both targets build successfully

EOF

echo -e "\n${GREEN}🎯 Quick Build Test Commands:${NC}"
echo "============================="
echo "After completing the manual steps above, test with:"
echo ""
echo "iOS Build:"
echo "  xcodebuild -scheme CardiacID -destination 'platform=iOS Simulator,name=iPhone 15' build"
echo ""
echo "watchOS Build:"
echo "  xcodebuild -scheme 'CardiacID WatchKit App' -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build"

echo -e "\n${YELLOW}⚠️  IMPORTANT NOTES:${NC}"
echo "==================="
echo "• NEVER add MSAL to watchOS target - it's not supported"
echo "• Always clean build folder after making changes"
echo "• If you see duplicate file errors, remove duplicate references"
echo "• Use the SimpleAuthView.swift for reliable cross-platform UI"

echo -e "\n${GREEN}✨ Script completed! Follow the manual steps above to fix your build.${NC}"

# Check if we can provide more specific help
echo -e "\n${BLUE}🔍 Current Status Check:${NC}"

if command -v xcodebuild &> /dev/null; then
    echo "✅ Xcode command line tools available"
    
    # Try to find the project file
    if ls *.xcodeproj &> /dev/null; then
        PROJECT_FILE=$(ls *.xcodeproj | head -1)
        echo "✅ Found project file: $PROJECT_FILE"
        
        echo -e "\n${BLUE}📋 Available schemes:${NC}"
        xcodebuild -list -project "$PROJECT_FILE" 2>/dev/null | grep -A 100 "Schemes:" | tail -n +2 | head -10
    else
        echo -e "${YELLOW}⚠️  No .xcodeproj file found in current directory${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Xcode command line tools not available${NC}"
fi

echo -e "\n${GREEN}🏁 Ready to build! Open Xcode and follow the manual steps.${NC}"