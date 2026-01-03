#!/bin/bash
# CardiacID Clean Build Script
# This script resolves CodeSign failures caused by extended attributes
# Run this before building in Xcode if you encounter CodeSign errors

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/Users/jimlocke/Projects/Build"

echo "=== CardiacID Clean Build Script ==="
echo "Project: $PROJECT_DIR"
echo ""

# Step 1: Remove extended attributes from source files
echo "Step 1: Clearing extended attributes from source files..."
find "$PROJECT_DIR" -path "$PROJECT_DIR/.build" -prune -o -path "$PROJECT_DIR/.git" -prune -o -type f -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
find "$PROJECT_DIR" -path "$PROJECT_DIR/.build" -prune -o -path "$PROJECT_DIR/.git" -prune -o -type d -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
echo "   Done."

# Step 2: Clean build directory
echo "Step 2: Cleaning build directory..."
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    echo "   Removed $BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
echo "   Created fresh $BUILD_DIR"

# Step 3: Clear extended attributes from new build directory
echo "Step 3: Clearing attributes from build directory..."
xattr -c "$BUILD_DIR" 2>/dev/null || true
echo "   Done."

# Step 4: Clean DerivedData for this project
echo "Step 4: Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/CardiacID-* 2>/dev/null || true
echo "   Done."

# Step 5: Remove SPM build cache
echo "Step 5: Clearing SPM cache..."
if [ -d "$PROJECT_DIR/.build" ]; then
    rm -rf "$PROJECT_DIR/.build"
    echo "   Removed .build directory"
fi

# Step 6: Remove .DS_Store files
echo "Step 6: Removing .DS_Store files..."
find "$PROJECT_DIR" -name ".DS_Store" -delete 2>/dev/null || true
echo "   Done."

# Step 7: Run dot_clean
echo "Step 7: Running dot_clean..."
dot_clean -m "$PROJECT_DIR" 2>/dev/null || true
echo "   Done."

echo ""
echo "=== Clean completed successfully ==="
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. Wait for SPM packages to resolve"
echo "3. Product → Clean Build Folder (⇧⌘K)"
echo "4. Product → Build (⌘B)"
echo ""
echo "Project is now in ~/Projects/CardiacID - CodeSign issues should be resolved."
