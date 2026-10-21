#!/usr/bin/env bash
set -euo pipefail

clean_field() {
    tr '\t\n' '  ' <<<"$1" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

require_nmap() {
    command -v nmap >/dev/null 2>&1 || {
        printf 'nmap is required for local network discovery.\n' >&2
        exit 127
    }
}

network_context() {
    local route iface own cidr gateway wifi_iface
    wifi_iface=$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 == "connected" {print $1; exit}') || wifi_iface=
    route=
    # Keep Wi-Fi discovery on Wi-Fi when USB tethering carries internet traffic.
    if [[ -n "$wifi_iface" ]]; then
        route=$(ip -o -4 route show default dev "$wifi_iface" | awk 'NR==1 {print}')
    fi
    [[ -n "$route" ]] || route=$(ip -o -4 route show default | awk 'NR==1 {print}')
    iface=$(awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' <<<"$route")
    [[ -n "$iface" ]] || iface=$wifi_iface
    own=$(awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' <<<"$route")
    gateway=$(awk '{for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}' <<<"$route")
    [[ -n "$iface" ]] || return 1
    [[ -n "$own" ]] || own=$(ip -o -4 addr show dev "$iface" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')
    cidr=$(ip -o -4 route show dev "$iface" scope link | awk 'NR==1 {print $1}')
    printf '%s\t%s\t%s\t%s\n' "$iface" "$own" "$cidr" "$gateway"
}

mac_vendor() {
    local mac=${1^^} prefix
    [[ "$mac" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || return 0
    prefix=${mac:0:8}
    prefix=${prefix//:/-}
    awk -v prefix="$prefix" '$1 == prefix && $2 == "(hex)" { $1=""; $2=""; sub(/^[[:space:]]+/, ""); print; exit }' /usr/share/hwdata/oui.txt 2>/dev/null || true
}

usb_list() {
    while IFS= read -r line; do
        [[ "$line" =~ ^Bus\ ([0-9]+)\ Device\ ([0-9]+):\ ID\ ([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\ (.*)$ ]] || continue
        desc=${BASH_REMATCH[4]}
        [[ "$desc" == *"root hub"* ]] && continue
        printf '%s\t%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$(clean_field "$desc")"
    done < <(lsusb)
}

usb_detail() {
    local bus=${1:-} device=${2:-} node
    [[ "$bus" =~ ^[0-9]+$ && "$device" =~ ^[0-9]+$ ]] || { printf 'Invalid USB address.\n' >&2; exit 2; }
    node="/dev/bus/usb/$(printf '%03d' "$((10#$bus))")/$(printf '%03d' "$((10#$device))")"
    [[ -e "$node" ]] || { printf 'USB device is no longer connected.\n' >&2; exit 1; }
    printf 'USB device %s:%s\n\n' "$bus" "$device"
    udevadm info --query=property --name="$node" | awk -F= '
        /^(ID_VENDOR_FROM_DATABASE|ID_VENDOR|ID_MODEL|ID_SERIAL_SHORT|ID_REVISION|ID_USB_INTERFACES|ID_PATH|DRIVER)=/ {
            key=$1; sub(/^[^=]*=/, ""); gsub(/_/, " "); print key ": " $0
        }'
    printf '\nKernel descriptors:\n'
    lsusb -s "${bus}:${device}" -v 2>/dev/null | awk '
        /^[[:space:]]*(bDeviceClass|bDeviceSubClass|bDeviceProtocol|bMaxPacketSize0|idVendor|idProduct|bcdDevice|iManufacturer|iProduct|iSerial|bNumConfigurations)/ {
            sub(/^[[:space:]]+/, ""); print
        }' | head -n 30
}

network_info() {
    network_context
}

resolve_name() {
    local ip=$1 name
    name=$(timeout 1 kdeconnect-cli -a 2>/dev/null | sed -n "s/^- \(.*\): .* on ${ip//./\\.} via .*/\1/p" | head -n 1 || true)
    [[ -n "$name" ]] || name=$(timeout 1 getent hosts "$ip" 2>/dev/null | awk 'NR==1 {print $2}' || true)
    [[ -n "$name" ]] || name=$(timeout 1 avahi-resolve-address "$ip" 2>/dev/null | awk 'NR==1 {print $2}' || true)
    printf '%s' "${name:-Unknown device}"
}

quick_services() {
    local ip=$1
    nmap -n -Pn -sT --open -T4 --host-timeout 8s \
        -p 22,53,80,139,443,445,1716,3000,3389,5000,8000,8080,9100 \
        -oG - "$ip" 2>/dev/null | sed -n 's/.*Ports: //p' | tr ',' '\n' | awk -F/ '
            BEGIN { names[22]="ssh"; names[53]="dns"; names[80]="http"; names[139]="netbios"; names[443]="https"; names[445]="smb"; names[1716]="kde-connect"; names[3000]="web-app"; names[3389]="rdp"; names[5000]="web-app"; names[8000]="http-alt"; names[8080]="http-proxy"; names[9100]="printer" }
            $2 == "open" { port=$1 + 0; if (names[port] != "") { printf "%s%s", separator, names[port]; separator="," } }
            END { print "" }
        '
}

lan_scan() {
    local context iface own cidr gateway network scan_xml ip nmap_name nmap_mac nmap_vendor rest mac state hostname vendor output
    require_nmap
    context=$(network_context) || { printf 'No active IPv4 network.\n' >&2; exit 1; }
    IFS=$'\t' read -r iface own cidr gateway <<<"$context"
    network=$(python3 - "$own" "$cidr" <<'PY'
import ipaddress, sys
own = ipaddress.ip_address(sys.argv[1])
net = ipaddress.ip_network(sys.argv[2], strict=False)
if net.prefixlen < 24:
    net = ipaddress.ip_network(f"{own}/24", strict=False)
print(net)
PY
)
    printf 'Scanning %s on %s with nmap…\n' "$network" "$iface" >&2
    scan_xml=$(mktemp)
    nmap -sn -T4 -oX "$scan_xml" "$network" >/dev/null
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$own" "$(hostnamectl --static 2>/dev/null || hostname)" "$mac" "$(mac_vendor "$mac")" "this-device" "$(quick_services "$own")"

    output=$(mktemp)
    while IFS=$'\t' read -r ip nmap_name nmap_mac nmap_vendor; do
        [[ "$ip" != "$own" ]] || continue
        (
            rest=$(ip neigh show to "$ip" dev "$iface" | head -n 1)
            mac=${nmap_mac:-$(awk '{for (i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' <<<"$rest")}
            state=$(awk '{print $NF}' <<<"$rest")
            hostname=${nmap_name:-$(resolve_name "$ip")}
            vendor=${nmap_vendor:-$(mac_vendor "$mac")}
            if [[ "$ip" == "$gateway" ]]; then
                hostname="Router / gateway"
            elif [[ -z "$hostname" || "$hostname" == "Unknown device" ]]; then
                hostname=${vendor:-"Network device ${ip##*.}"}
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ip" "$(clean_field "$hostname")" "$mac" "$(clean_field "$vendor")" "${state,,}" "$(quick_services "$ip")" >> "$output"
        ) &
    done < <(python3 - "$scan_xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

for host in ET.parse(sys.argv[1]).getroot().findall("host"):
    if host.find("status").get("state") != "up":
        continue
    addresses = {item.get("addrtype"): item for item in host.findall("address")}
    ipv4 = addresses.get("ipv4")
    if ipv4 is None:
        continue
    mac = addresses.get("mac")
    hostname = host.find("hostnames/hostname")
    print("\t".join((
        ipv4.get("addr", ""),
        hostname.get("name", "") if hostname is not None else "",
        mac.get("addr", "") if mac is not None else "",
        mac.get("vendor", "") if mac is not None else "",
    )))
PY
)
    wait || true
    sort -V -k1,1 "$output"
    rm -f -- "$scan_xml" "$output"
}

lan_detail() {
    local ip=${1:-} context iface own cidr gateway rest mac state name vendor latency
    require_nmap
    [[ "$ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { printf 'Invalid IPv4 address.\n' >&2; exit 2; }
    context=$(network_context) || { printf 'No active IPv4 network.\n' >&2; exit 1; }
    IFS=$'\t' read -r iface own cidr gateway <<<"$context"
    python3 - "$ip" "$cidr" <<'PY'
import ipaddress, sys
if ipaddress.ip_address(sys.argv[1]) not in ipaddress.ip_network(sys.argv[2], strict=False):
    raise SystemExit("The selected address is outside the active local network.")
PY
    ping -n -c 1 -W 2 "$ip" >/dev/null 2>&1 || true
    rest=$(ip neigh show to "$ip" dev "$iface" | head -n 1)
    mac=$(awk '{for (i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' <<<"$rest")
    state=$(awk '{print $NF}' <<<"$rest")
    name=$(resolve_name "$ip")
    vendor=$(mac_vendor "$mac")
    latency=$(ping -n -c 2 -W 2 "$ip" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\) ms.*/\1 ms/p' | tail -n 1)

    printf 'Name: %s\nIP address: %s\nMAC address: %s\nVendor: %s\nNeighbour state: %s\nLatency: %s\n' \
        "$name" "$ip" "${mac:-Unknown}" "${vendor:-Unknown}" "${state:-Unknown}" "${latency:-No ping response}"
    [[ "$ip" == "$gateway" ]] && printf 'Role: Default gateway / router\n'

    printf '\nNmap service scan:\n'
    nmap -n -Pn -sT -sV --version-light --open -T4 --host-timeout 15s \
        -p 22,53,80,139,443,445,1716,3000,3389,5000,8000,8080,9100 "$ip" 2>/dev/null |
        sed -n '/^PORT[[:space:]]\+STATE[[:space:]]\+SERVICE/,$p' |
        sed '/^Nmap done:/d'
}

case "${1:-}" in
    usb) usb_list ;;
    usb-detail) usb_detail "${2:-}" "${3:-}" ;;
    network-info) network_info ;;
    lan-scan) lan_scan ;;
    lan-detail) lan_detail "${2:-}" ;;
    *)
        printf 'usage: %s {usb|usb-detail BUS DEVICE|network-info|lan-scan|lan-detail IP}\n' "$0" >&2
        exit 2
        ;;
esac
