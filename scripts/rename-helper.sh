#!/bin/zsh
# Gives the Low Power Mode helper a new launchd name: com.batterystrip.BatteryStrip.Helper3 becomes Helper4.
#
# Signed ad hoc, the helper is approved by macOS as one exact file, and a different file under the same name won't
# start for anyone who approved the old one. So whenever the helper's code (or the Xcode that builds it) changes,
# it needs a new name. The app sets the renamed helper up the next time the switch is used, and macOS remembers
# that Battery Strip was allowed in the background. scripts/release.sh says when to run this.
set -euo pipefail
cd "$(dirname "$0")/.."

old=$(sed -n 's/.*machServiceName = "\(.*\)".*/\1/p' Shared/HelperProtocol.swift)
number=${old##*Helper}
new="${old%Helper*}Helper$(( ${number:-1} + 1 ))"
pattern=${old//./\\.}

git mv "LaunchDaemons/$old.plist" "LaunchDaemons/$new.plist"
sed -i '' "s/$pattern\([\".<]\)/$new\1/g" "LaunchDaemons/$new.plist" Shared/HelperProtocol.swift BatteryStrip.xcodeproj/project.pbxproj
echo "Renamed the helper from $old to $new."
