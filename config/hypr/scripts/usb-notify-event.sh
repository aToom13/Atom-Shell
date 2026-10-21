#!/bin/bash
# USB physical plug/unplug - udev trigger script
# Called by udev when USB block device is added/removed
# Forwards the event to the user's systemd service via a FIFO pipe

ACTION_TYPE="$1"
DEVNAME="${DEVNAME:-}"
ID_FS_LABEL="${ID_FS_LABEL:-}"
ID_MODEL="${ID_MODEL:-}"

# Short device name
DEV=$(basename "$DEVNAME")

# Determine label
if [ -n "$ID_FS_LABEL" ]; then
    LABEL="$ID_FS_LABEL"
elif [ -n "$ID_MODEL" ]; then
    LABEL="$ID_MODEL"
else
    LABEL="$DEV"
fi

USER_NAME="${USER:-$(id -un)}"
USER_ID="1000"
PIPE="/run/user/$USER_ID/usb-event"

# Write event to pipe for the user service to read
if [ -p "$PIPE" ]; then
    echo "$ACTION_TYPE|$LABEL|$DEV" > "$PIPE" 2>/dev/null
fi
