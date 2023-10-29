#!/bin/sh

### BEGIN INIT INFO
# Provides:		its
# Required-Start:	$syslog
# Required-Stop:	$syslog
# Default-Start:	2 3 4 5
# Default-Stop:		0 1 6
# Short-Description:	Incompatible Timeharing System
### END INIT INFO

verbose=message

HOME="/its"
MCHN="$HOME"
TOOLS="$HOME/tools"
LOG="$HOME/automated.log"
PID="$HOME/its.pid"

action="$1"

message() {
    echo "$1" 1>&2
}

fail() {
    message "$1"
    exit 1
}

expect() {
    text="$1"
    timeout="${2:-10}"
    i=0
    while :; do
        grep -q "$text" "$LOG" && return 0
        i=`expr $i + 1`
        test $i -ge $timeout && return 1
        sleep 1
    done
}

status_screen() {
    screen -ls | grep -q its
}

status_emulator() {
    kill -CONT `cat "$PID"` 2>/dev/null
}

case "$action" in
    status)
        status_screen || fail "ITS is down."
        status_emulator || fail "ITS is down."
	message "ITS is up."
        ;;
    start)
        cd "$HOME"
        $verbose "Starting ITS screen."
        screen -c "$MCHN/its.screen" -dmS its
        $verbose "Starting DSKDMP."
        screen -S its -X logfile flush 1
        screen -S its -X select 0
        screen -S its -X title "SIMH control console"
        sleep 3
        screen -S its -X screen telnet localhost 1025
        rm -f "$LOG"
        screen -S its -X logfile "$LOG"
        screen -S its -X log on
        screen -S its -X title "KA10 console teletype"
        if expect "DSKDMP"; then
            $verbose "Starting ITS."
	    screen -S its -X stuff "ITS\r"
	    screen -S its -X stuff "\033G"
            if expect "IN OPERATION" 20; then
                $verbose "ITS in operation."
                screen -S its -X log off
                rm -f "$LOG"
                screen -S its -X log on
                screen -S its -X logfile "$HOME/ka10.log"
                exit 0
            else
                fail "ITS failed to start."
            fi
        else
            fail "DSKDMP not started."
        fi

        # Something failed, shut everything down.
        if status_emulator; then
            kill `cat "$PID"` 2>/dev/null; sleep 1
            status_emulator && kill -9 `cat $PID` 2>/dev/null
        fi
	screen -S its -X quit
        ;;
    stop)
        cd "$HOME"
        screen -S its -X log off
        rm -f "$LOG"
        screen -S its -X select 1
        screen -S its -X logfile "$LOG"
        screen -S its -X log on
        $verbose "Shutting down ITS."
        "$TOOLS/chaosnet-tools/shutdown" its
        expect "NOT IN OPERATION" || fail "ITS failed to shut down."
        $verbose "ITS not in operation."
        expect "SHUTDOWN COMPLETE" 60 || fail "ITS failed to shut down."
        $verbose "ITS shutdown complete."
        screen -S its -X log off
        rm -f "$LOG"
        $verbose "Quitting KA10 emulator."
        screen -S its -X select 0
	screen -S its -X stuff "\034"; sleep 1
	screen -S its -X stuff "quit\r"; sleep 1
        if status_emulator; then
            $verbose "Emulator still running; forcibly killing it."
            kill `cat "$PID"` 2>/dev/null; sleep 1
            status_emulator && kill -9 `cat $PID` 2>/dev/null
        fi
        rm -f "$PID"
        $verbose "Stopping ITS screen."
	screen -S its -X quit
        ;;
    restart)
        $MCHN/its.sh stop
        $MCHN/its.sh start
        ;;
    *)
        message "Unknown action: $action"
        ;;
esac
