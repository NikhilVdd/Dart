#!/bin/zsh
# Builds the macOS harness and opens it against the Supabase project in
# Configuration/Development.xcconfig, so you can sign in and register with real accounts.
#
# Usage: DartApp/MacRun/run-live.sh [--fresh] [--as NAME]
#   --fresh    sign that window out first
#   --as NAME  open another window with its own login (e.g. --as darter), so a requester and a
#              darter can be signed in side by side
set -e
cd "${0:A:h}"
profile=default fresh=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --fresh) fresh=1 ;;
    --as) profile=$2; shift ;;
  esac
  shift
done

CONFIG=../Configuration/Development.xcconfig
url=$(grep '^SUPABASE_URL' $CONFIG | sed 's/^[^=]*= *//; s#:/\$()/#://#')
key=$(grep '^SUPABASE_ANON_KEY' $CONFIG | sed 's/^[^=]*= *//')
if [[ -z "$url" || -z "$key" ]]; then echo "Fill in SUPABASE_URL and SUPABASE_ANON_KEY in $CONFIG"; exit 1; fi

APP=.build/Dart.app
# Only rebuild for the first window, so a second window doesn't restart the first one.
if [[ $profile == default ]]; then
  ./make-app.sh
  plutil -replace SUPABASE_URL -string "$url" $APP/Contents/Resources/Supabase.plist
  plutil -replace SUPABASE_ANON_KEY -string "$key" $APP/Contents/Resources/Supabase.plist
  codesign --force --sign - $APP
  pkill -f "MacRun/.build/Dart.app" || true
  sleep 1
fi

(( fresh )) && rm -rf "$HOME/Library/Application Support/DartDev/auth-$profile"
open -n --env DART_DEV_PROFILE=$profile $APP
echo "Opened Dart ($profile login) against $url"
