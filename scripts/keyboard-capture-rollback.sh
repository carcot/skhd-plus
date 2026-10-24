#!/bin/sh
set -u

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo 'usage: keyboard-capture-rollback.sh DELAY_SECONDS LOG_PATH [TEST_AGENT_LABEL]' >&2
    exit 2
fi

delay=$1
log=$2
test_agent=${3:-}
case "$delay" in
    ''|*[!0-9]*) echo 'delay must be an integer number of seconds' >&2; exit 2 ;;
esac
case "$test_agent" in
    ''|gui/501/com.jackielii.skhd.hour-trial-agent) ;;
    *) echo 'unsupported test agent label' >&2; exit 2 ;;
esac
if [ "$delay" -lt 1 ] || [ "$delay" -gt 3700 ] || [ "$(/usr/bin/id -u)" -ne 0 ]; then
    echo 'requires root and a delay between 1 and 3700 seconds' >&2
    exit 2
fi

/bin/sleep "$delay"
/bin/date -u >> "$log"
/usr/bin/killall -KILL skhd-grabber >> "$log" 2>&1 || :
/bin/launchctl bootout system/com.jackielii.skhd.grabber >> "$log" 2>&1 || :
/usr/bin/killall -KILL skhd-grabber >> "$log" 2>&1 || :
if /usr/bin/pgrep -x skhd-grabber >> "$log" 2>&1; then
    echo 'ROLLBACK_FAILED: skhd-grabber still running' >> "$log"
    exit 1
fi

agent='/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents v2.app/Contents/MacOS/Karabiner-Elements Non-Privileged Agents v2'
/bin/launchctl asuser 501 /usr/bin/sudo -n -u carlcotner "$agent" register-core-agents >> "$log" 2>&1
result=$?
echo "RESTORE_EXIT=$result" >> "$log"
if [ -n "$test_agent" ]; then
    /bin/launchctl bootout "$test_agent" >> "$log" 2>&1
    echo "TEST_AGENT_BOOTOUT_EXIT=$?" >> "$log"
fi
/bin/date -u >> "$log"
exit "$result"
