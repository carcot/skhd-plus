#!/bin/sh
set -u

delay=${1:-0}
log=${2:-/private/tmp/skhd-permanent-rollback.log}
case "$delay" in
    ''|*[!0-9]*) exit 2 ;;
esac
if [ "$delay" -gt 900 ] || [ "$(/usr/bin/id -u)" -ne 0 ]; then
    exit 2
fi

/bin/sleep "$delay"
/bin/date -u >> "$log"
/bin/launchctl disable system/com.jackielii.skhd.grabber >> "$log" 2>&1
/bin/launchctl disable gui/501/com.jackielii.skhd.remap-agent >> "$log" 2>&1
/usr/bin/killall -KILL skhd-grabber >> "$log" 2>&1 || :
/bin/launchctl bootout system/com.jackielii.skhd.grabber >> "$log" 2>&1 || :
/usr/bin/killall -KILL skhd-grabber >> "$log" 2>&1 || :
/bin/launchctl bootout gui/501/com.jackielii.skhd.remap-agent >> "$log" 2>&1 || :
if /usr/bin/pgrep -x skhd-grabber >> "$log" 2>&1; then
    echo 'ROLLBACK_FAILED: skhd-grabber still running' >> "$log"
    exit 1
fi

/bin/launchctl enable gui/501/org.pqrs.service.agent.Karabiner-Core-Service-rev2 >> "$log" 2>&1
/bin/launchctl enable gui/501/org.pqrs.service.agent.Karabiner-Console-User-Server >> "$log" 2>&1
agent='/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents v2.app/Contents/MacOS/Karabiner-Elements Non-Privileged Agents v2'
/bin/launchctl asuser 501 /usr/bin/sudo -n -u carlcotner "$agent" register-core-agents >> "$log" 2>&1
result=$?
echo "RESTORE_EXIT=$result" >> "$log"
/bin/date -u >> "$log"
exit "$result"
