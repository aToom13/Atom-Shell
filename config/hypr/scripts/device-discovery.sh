#!/usr/bin/env bash
set -euo pipefail

clean_field() {
    tr '\t\n' '  ' <<<"$1" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

network_context() {
    local route iface own cidr gateway
    route=$(ip -o -4 route show default | head -n 1)
    iface=$(awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' <<<"$route")
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
    local ip=$1 tmp port label result
    tmp=$(mktemp)
    for item in '22 ssh' '53 dns' '80 http' '139 netbios' '443 https' '445 smb' '1716 kde-connect' '9100 printer'; do
        port=${item%% *}; label=${item#* }
        (nc -z -w 1 "$ip" "$port" >/dev/null 2>&1 && printf '%s\n' "$label" >> "$tmp") &
    done
    # One closed port must not cancel all results under `set -e`.
    wait || true
    result=$(sort -u "$tmp" | paste -sd ',' -)
    rm -f -- "$tmp"
    printf '%s' "$result"
}

lan_scan() {
    local context iface own cidr gateway network mac state hostname vendor
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
    printf 'Scanning %s on %s…\n' "$network" "$iface" >&2
    # shellcheck disable=SC2016 # $1 belongs to the inner sh invoked by xargs.
    python3 - "$network" "$own" <<'PY' | xargs -r -P 64 -n 1 sh -c 'ping -n -c 1 -W 1 "$1" >/dev/null 2>&1 || true' sh
import ipaddress, sys
net = ipaddress.ip_network(sys.argv[1], strict=False)
own = sys.argv[2]
for address in net.hosts():
    if str(address) != own:
        print(address)
PY

    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$own" "$(hostnamectl --static 2>/dev/null || hostname)" "$mac" "$(mac_vendor "$mac")" "this-device" "$(quick_services "$own")"

    output=$(mktemp)
    while read -r ip rest; do
        [[ "$ip" =~ ^[0-9]+(\.[0-9]+){3}$ && "$ip" != "$own" ]] || continue
        mac=$(awk '{for (i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' <<<"$rest")
        state=$(awk '{print $NF}' <<<"$rest")
        [[ -n "$mac" && "$state" != FAILED && "$state" != INCOMPLETE ]] || continue
        (
            hostname=$(resolve_name "$ip")
            vendor=$(mac_vendor "$mac")
            if [[ "$ip" == "$gateway" ]]; then
                hostname="${hostname/Unknown device/Router / gateway}"
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ip" "$(clean_field "$hostname")" "$mac" "$(clean_field "$vendor")" "${state,,}" "$(quick_services "$ip")" >> "$output"
        ) &
    done < <(ip neigh show dev "$iface" | sort -V -k1,1)
    # Individual devices may disappear during a scan. Keep the results from
    # the devices that did answer instead of failing the complete discovery.
    wait || true
    sort -V -k1,1 "$output"
    rm -f -- "$output"
}

lan_detail() {
    local ip=${1:-} context iface own cidr gateway rest mac state name vendor latency open_tmp
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

    printf '\nOpen common TCP services:\n'
    open_tmp=$(mktemp)
    for item in '22 SSH' '53 DNS' '80 HTTP' '139 NetBIOS' '443 HTTPS' '445 SMB' '1716 KDE-Connect' '3000 Web-app' '3389 RDP' '5000 Web-app' '8000 HTTP-alt' '8080 HTTP-proxy' '9100 Printer'; do
        port=${item%% *}; label=${item#* }
        (nc -z -w 2 "$ip" "$port" >/dev/null 2>&1 && printf '%s/tcp  %s\n' "$port" "$label" >> "$open_tmp") &
    done
    wait || true
    if [[ -s "$open_tmp" ]]; then sort -n "$open_tmp"; else printf 'None of the checked common ports responded.\n'; fi
    rm -f -- "$open_tmp"
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
