#!/bin/zsh
# Rebuild, reinstall to /Applications and relaunch. Usage: scripts/run.sh [Debug|Release] [app arguments...]
set -e
cd "$(dirname "$0")/.."
CONFIG=${1:-Release}
xcodebuild -project BatteryStrip.xcodeproj -scheme "Battery Strip" -configuration $CONFIG -derivedDataPath build/DerivedData build > build/log.txt 2>&1 || { grep -E "error:" build/log.txt | sort -u; exit 1; }
grep -E "warning:" build/log.txt | grep -v appintents | sort -u || true
pkill -f "MacOS/Battery Strip" || true
rm -rf /Applications/"Battery Strip.app"
ditto build/DerivedData/Build/Products/$CONFIG/"Battery Strip.app" /Applications/"Battery Strip.app"
open /Applications/"Battery Strip.app" --args "${@:2}"
echo "relaunched $CONFIG build"
