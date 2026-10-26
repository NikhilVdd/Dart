#!/bin/zsh
# Builds the optional Dart macOS development harness at MacRun/.build/Dart.app
set -e
cd "${0:A:h}"
swift build -c ${1:-debug}
BIN="$(swift build -c ${1:-debug} --show-bin-path)/Dart"
APP=.build/Dart.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$BIN" $APP/Contents/MacOS/Dart
cp AppInfo.plist $APP/Contents/Info.plist
cp ../Dart/Resources/Supabase.plist $APP/Contents/Resources/
# Without Xcode there is no asset catalog compiler; ship the image sets as plain PNGs.
find ../Dart/Resources/Assets.xcassets -path "*.imageset/*.png" -exec cp {} $APP/Contents/Resources/ \;
codesign --force --sign - $APP
echo "Built $PWD/$APP"
