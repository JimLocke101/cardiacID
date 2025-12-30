#!/bin/bash
# clean_build.sh - Complete Xcode project cleanup script

echo "🧹 Starting complete Xcode project cleanup..."

# Navigate to project directory
PROJECT_DIR="$1"
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(pwd)"
fi

echo "📁 Working directory: $PROJECT_DIR"

# Clean Xcode derived data
echo "🗑️ Cleaning Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-*
rm -rf "$PROJECT_DIR/DerivedData"

# Clean build folders
echo "🗑️ Cleaning build folders..."
rm -rf "$PROJECT_DIR/Build"
rm -rf "$PROJECT_DIR/build"

# Clean module cache
echo "🗑️ Cleaning module cache..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# Clean archives
echo "🗑️ Cleaning archives..."
rm -rf ~/Library/Developer/Xcode/Archives/CardiacID-*

# Clean simulator data (optional)
echo "🗑️ Resetting simulator..."
xcrun simctl shutdown all
xcrun simctl erase all

# Clean SPM cache
echo "🗑️ Cleaning Swift Package Manager cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf ~/Library/org.swift.swiftpm/

echo "✅ Cleanup complete! Now rebuild your project."

# Instructions for manual steps
echo ""
echo "🔧 Next steps in Xcode:"
echo "1. Product → Clean Build Folder (⌘+Shift+K)"
echo "2. File → Packages → Reset Package Caches"
echo "3. Remove duplicate file references"
echo "4. Rebuild project"