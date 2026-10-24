#!/bin/zsh
# Builds the optional Dart macOS development harness at MacRun/.build/Dart.app
set -e
cd "${0:A:h}"
swift build -c ${1:-debug}
BIN="$(swift build -c ${1:-debug} --show-bin-path)/Dart"
APP=.build/Dart.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$BIN" $APP/Contents/MacOS/Dart
cp ../Dart/Resources/Supabase.plist $APP/Contents/Resources/
codesign --force --sign - $APP
echo "Built $PWD/$APP"
