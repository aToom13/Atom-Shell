#!/usr/bin/env bash
set -euo pipefail

active_device() {
    local device
    device=$(ip -o -4 route show default | awk 'NR==1 {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')
    [[ -n "$device" ]] || device=$(nmcli -t -f DEVICE,STATE device | awk -F: '$2 ~ /^connected/ {print $1; exit}')
    printf '%s' "$device"
}

field() {
    local device=$1 key=$2
    nmcli -t -f "$key" device show "$device" 2>/dev/null | sed -n '1s/^[^:]*://p'
}

status() {
    local device type connection address gateway dns mac mtu connectivity state wifi signal rate security channel
    device=$(active_device)
    connectivity=$(nmcli -t -f CONNECTIVITY general | sed 's/^CONNECTIVITY://')
    state=$(nmcli -t -f STATE general | sed 's/^STATE://')
    printf 'connectivity\t%s\nstate\t%s\n' "$connectivity" "$state"
    [[ -n "$device" ]] || exit 0

    type=$(field "$device" GENERAL.TYPE)
    connection=$(field "$device" GENERAL.CONNECTION)
    address=$(field "$device" IP4.ADDRESS)
    gateway=$(field "$device" IP4.GATEWAY)
    dns=$(nmcli -t -f IP4.DNS device show "$device" 2>/dev/null | sed 's/^[^:]*://' | paste -sd ', ' -)
    mac=$(field "$device" GENERAL.HWADDR)
    mtu=$(field "$device" GENERAL.MTU)
    signal=""; rate=""; security=""; channel=""
    if [[ "$type" == wifi ]]; then
        wifi=$(nmcli -t --escape no -f IN-USE,SSID,SIGNAL,RATE,SECURITY,CHAN device wifi list --rescan no 2>/dev/null | awk -F: '$1=="*" || $1=="yes" {print; exit}')
        IFS=: read -r _ _ signal rate security channel <<<"$wifi"
    fi

    printf 'device\t%s\ntype\t%s\nconnection\t%s\naddress\t%s\ngateway\t%s\ndns\t%s\nmac\t%s\nmtu\t%s\nsignal\t%s\nrate\t%s\nsecurity\t%s\nchannel\t%s\n' \
        "$device" "$type" "$connection" "$address" "$gateway" "$dns" "$mac" "$mtu" "$signal" "$rate" "$security" "$channel"
}

diagnose() {
    local device gateway dns_server latency
    device=$(active_device)
    [[ -n "$device" ]] || { printf 'No active network interface.\n'; exit 1; }
    gateway=$(field "$device" IP4.GATEWAY)
    dns_server=$(nmcli -t -f IP4.DNS device show "$device" 2>/dev/null | sed -n '1s/^[^:]*://p')
    printf 'Interface: %s\nConnection: %s\nAddress: %s\nGateway: %s\nDNS: %s\n\n' \
        "$device" "$(field "$device" GENERAL.CONNECTION)" "$(field "$device" IP4.ADDRESS)" "${gateway:-None}" "${dns_server:-None}"

    if [[ -n "$gateway" ]] && latency=$(ping -n -c 1 -W 2 "$gateway" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\) ms.*/\1 ms/p'); then
        printf 'Gateway: OK (%s)\n' "${latency:-reachable}"
    else
        printf 'Gateway: FAILED\n'
    fi
    if ping -n -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then printf 'Internet routing: OK\n'; else printf 'Internet routing: FAILED\n'; fi
    if timeout 4 getent ahostsv4 example.com >/dev/null 2>&1; then printf 'DNS resolution: OK\n'; else printf 'DNS resolution: FAILED\n'; fi
    if curl -Is --max-time 5 https://example.com/ >/dev/null 2>&1; then printf 'HTTPS access: OK\n'; else printf 'HTTPS access: FAILED\n'; fi
    printf 'NetworkManager: %s\n' "$(nmcli -t -f STATE general | sed 's/^STATE://')"
}

case "${1:-status}" in
    status) status ;;
    diagnose) diagnose ;;
    *) printf 'usage: %s {status|diagnose}\n' "$0" >&2; exit 2 ;;
esac
