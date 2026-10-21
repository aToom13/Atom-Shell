#!/usr/bin/env bash
set -euo pipefail

active_interface() {
    nmcli -t --escape no -f DEVICE,TYPE,STATE device | awk -F: '$2 ~ /^(wifi|ethernet)$/ && $3 ~ /^connected/ {print $1; exit}'
}

validate_interface() {
    local iface=$1
    [[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ && -d "/sys/class/net/$iface" ]] || {
        printf 'Invalid network interface.\n' >&2
        exit 2
    }
}

status() {
    local iface type connection security pmf firewall listeners monitor_support iw_info address gateway dns neighbors public_listeners ip_forward promiscuous
    iface=$(active_interface)
    [[ -n "$iface" ]] || { printf 'state\tdisconnected\n'; exit 0; }
    type=$(nmcli -g GENERAL.TYPE device show "$iface" 2>/dev/null || true)
    connection=$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null || true)
    security=""
    pmf=""
    if [[ "$type" == wifi ]]; then
        security=$(nmcli -t --escape no -f IN-USE,SECURITY device wifi list ifname "$iface" --rescan no 2>/dev/null | awk -F: '$1 == "*" || $1 == "yes" {print $2; exit}')
        pmf=$(nmcli -g 802-11-wireless-security.pmf connection show id "$connection" 2>/dev/null || true)
    fi
    if systemctl is-active --quiet ufw || systemctl is-active --quiet firewalld; then
        firewall=active
    else
        firewall=inactive
    fi
    listeners=$(ss -H -lntu 2>/dev/null | wc -l)
    public_listeners=$(ss -H -lntu 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0|\[::\]):/ {count++} END {print count + 0}')
    address=$(nmcli -g IP4.ADDRESS device show "$iface" 2>/dev/null | head -n 1 || true)
    gateway=$(nmcli -g IP4.GATEWAY device show "$iface" 2>/dev/null | head -n 1 || true)
    dns=$(nmcli -g IP4.DNS device show "$iface" 2>/dev/null | paste -sd ', ' -)
    neighbors=$(ip neigh show dev "$iface" 2>/dev/null | awk '$NF != "FAILED" && $NF != "INCOMPLETE" {count++} END {print count + 0}')
    ip_forward=$(< /proc/sys/net/ipv4/ip_forward)
    promiscuous=no
    [[ $(ip -o link show dev "$iface" 2>/dev/null) == *PROMISC* ]] && promiscuous=yes
    iw_info=$(iw list 2>/dev/null || true)
    if command -v airmon-ng >/dev/null 2>&1 && [[ "$iw_info" == *"monitor"* ]]; then
        monitor_support=available
    else
        monitor_support=unavailable
    fi
    printf 'state\tconnected\ninterface\t%s\ntype\t%s\nconnection\t%s\naddress\t%s\ngateway\t%s\ndns\t%s\nsecurity\t%s\npmf\t%s\nfirewall\t%s\nlisteners\t%s\npublic_listeners\t%s\nneighbors\t%s\nip_forward\t%s\npromiscuous\t%s\nmonitor\t%s\n' \
        "$iface" "$type" "$connection" "$address" "$gateway" "$dns" "$security" "$pmf" "$firewall" "$listeners" "$public_listeners" "$neighbors" "$ip_forward" "$promiscuous" "$monitor_support"
}

listeners() {
    ss -H -lntup 2>/dev/null | awk '{ process="system"; if (match($0, /users:\(\("[^"]+/)) { process=substr($0, RSTART + 9, RLENGTH - 9) } printf "%s\t%s\t%s\n", $1, $5, process }' | head -n 40
}

disconnect_network() {
    local iface=${1:-}
    validate_interface "$iface"
    nmcli device disconnect "$iface"
}

reconnect_network() {
    local iface=${1:-} connection=${2:-}
    validate_interface "$iface"
    [[ -n "$connection" ]] || { printf 'Missing connection profile.\n' >&2; exit 2; }
    nmcli connection up id "$connection" ifname "$iface"
}

capture() {
    local iface=${1:-}
    validate_interface "$iface"
    if (( EUID != 0 )); then
        exec pkexec "$0" capture "$iface"
    fi
    timeout --signal=INT 15 tcpdump -i "$iface" -nn -tttt -q -l -c 100 -s 96 2>/dev/null | awk -v OFS='\t' '
        $3 == "IP" || $3 == "IP6" {
            protocol = $0 ~ / UDP,/ ? "UDP" : $0 ~ / tcp / ? "TCP" : $0 ~ / ICMP/ ? "ICMP" : $3
            destination = $6; sub(/:$/, "", destination)
            bytes = ""; if (match($0, /length [0-9]+/)) bytes = substr($0, RSTART + 7, RLENGTH - 7); else if (match($0, /tcp [0-9]+/)) bytes = substr($0, RSTART + 4, RLENGTH - 4)
            summary = $0; sub(/^.*: /, "", summary)
            print $1 " " $2, protocol, $4, destination, bytes, summary
            next
        }
        $3 == "ARP," {
            summary = $0; sub(/^.*ARP, /, "", summary)
            print $1 " " $2, "ARP", "", "", "", summary
        }
    ' || true
}

case "${1:-status}" in
    status) status ;;
    listeners) listeners ;;
    disconnect) disconnect_network "${2:-}" ;;
    reconnect) reconnect_network "${2:-}" "${3:-}" ;;
    capture) capture "${2:-}" ;;
    *) printf 'usage: %s {status|listeners|disconnect IFACE|reconnect IFACE CONNECTION|capture IFACE}\n' "$0" >&2; exit 2 ;;
esac
