#!/bin/zsh
# Builds Grab as a native macOS app bundle at MacRun/.build/Grab.app
set -e
cd "${0:A:h}"
swift build -c ${1:-debug}
BIN="$(swift build -c ${1:-debug} --show-bin-path)/Grab"
APP=.build/Grab.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$BIN" $APP/Contents/MacOS/Grab
cp ../Grab/Resources/Supabase.plist $APP/Contents/Resources/
codesign --force --sign - $APP
echo "Built $PWD/$APP"
