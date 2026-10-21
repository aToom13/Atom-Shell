#!/bin/bash
# USB Notification Setup Script (v2)
# Çalıştır: sudo bash ~/.config/hypr/scripts/usb-notify-setup.sh
set -e

echo "=== USB Bildirim Sistemi Kurulumu v2 ==="
echo ""

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")

# ─── 1) udev tetikleyici script (DEVTYPE=disk) ─────────────────────────
echo "[1/6] udev tetikleyici script..."

cat > /usr/local/bin/usb-notify-udev.sh <<UDEV
#!/bin/bash
# Udev trigger — USB disk takılınca/çıkarılınca FIFO pipe'a yazar
ACTION_TYPE="\$1"
[ -z "\$ACTION_TYPE" ] && exit 1

DEVNAME="\${DEVNAME:-}"
ID_MODEL="\${ID_MODEL:-}"

DEV=\$(basename "\$DEVNAME")
LABEL=\$(echo "\$ID_MODEL" | tr '_' ' ')
[ -z "\$LABEL" ] && LABEL="\$DEV"

# Non-blocking write to FIFO (timeout 1sn, arkaplan)
PIPE="/run/user/${TARGET_UID}/usb-event"
if [ -p "\$PIPE" ]; then
    timeout 1 bash -c "echo '\${ACTION_TYPE}|\${LABEL}|\${DEV}' > '\$PIPE'" 2>/dev/null &
fi
UDEV
chmod +x /usr/local/bin/usb-notify-udev.sh
echo "  ✅ /usr/local/bin/usb-notify-udev.sh"

# ─── 2) udev kuralı (DEVTYPE=disk) ─────────────────────────────────────
echo "[2/6] udev kuralı (DEVTYPE=disk)..."

cat > /etc/udev/rules.d/99-usb-notify.rules <<'RULE'
# USB disk takılınca
ACTION=="add",    SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="disk", RUN+="/usr/local/bin/usb-notify-udev.sh add"
# USB disk çıkarılınca
ACTION=="remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="disk", RUN+="/usr/local/bin/usb-notify-udev.sh remove"
RULE
echo "  ✅ /etc/udev/rules.d/99-usb-notify.rules (DEVTYPE=disk)"

# ─── 3) udiskie (otomatik mount) ───────────────────────────────────────
echo "[3/6] udiskie kontrol..."
if pacman -Q udiskie &>/dev/null; then
    echo "  ✅ udiskie zaten kurulu"
else
    pacman -S --noconfirm udiskie 2>&1 | tail -1
    echo "  ✅ udiskie kuruldu"
fi

# ─── 4) Handler script (lsblk mount + stderr fix) ──────────────────────
echo "[4/6] Handler script güncelleniyor..."

mkdir -p "$TARGET_HOME/.config/hypr/scripts"
cat > "$TARGET_HOME/.config/hypr/scripts/usb-notify-handler.sh" <<HANDLER
#!/bin/bash
# USB Notification Handler — udev'den FIFO pipe ile haberleşir
USER_NAME="\${USER:-\$(id -un)}"
USER_ID=\$(id -u "\$USER_NAME")
PIPE="/run/user/\$USER_ID/usb-event"

# Pipe oluştur
rm -f "\$PIPE"
mkfifo -m 600 "\$PIPE"

# D-Bus & Wayland ortamını hazırla
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$USER_ID/bus"
WAYLAND_SOCK=\$(ls -t /run/user/\$USER_ID/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
if [ -n "\$WAYLAND_SOCK" ]; then
    export WAYLAND_DISPLAY=\$(basename "\$WAYLAND_SOCK")
fi

while true; do
    if ! IFS='|' read -r ACTION LABEL DEV; then
        sleep 0.5
        continue
    fi

    [ -z "\$ACTION" ] && continue

    if [ "\$ACTION" = "add" ]; then
        SIZE=\$(lsblk -bno SIZE "/dev/\$DEV" 2>/dev/null | head -1 | awk '{printf "%.1f GB", \$1/1073741824}' || echo "")
        
        sleep 2
        
        MOUNT_PATHS=\$(lsblk -no MOUNTPOINT "/dev/\$DEV"* 2>/dev/null | grep -v '^$' | tr '\n' ' ' | sed 's/ \$//')
        
        if [ -n "\$MOUNT_PATHS" ]; then
            BODY="Boyut: \${SIZE}\nBağlandı: \${MOUNT_PATHS}"
        else
            BODY="Boyut: \${SIZE}\nAygıt: /dev/\${DEV}"
        fi

        notify-send -u normal -a "USB" -i drive-removable-media \
            "💾 USB Bellek Takıldı" "\$LABEL\n\$BODY"

    elif [ "\$ACTION" = "remove" ]; then
        notify-send -u low -a "USB" -i media-removable-symbolic \
            "🔌 Bağlantı Kesildi" "\$LABEL (\$DEV)"
    fi
done < "\$PIPE"
HANDLER
chmod +x "$TARGET_HOME/.config/hypr/scripts/usb-notify-handler.sh"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/hypr/scripts/usb-notify-handler.sh"
echo "  ✅ $TARGET_HOME/.config/hypr/scripts/usb-notify-handler.sh"

# ─── 5) Servis (default.target) ────────────────────────────────────────
echo "[5/6] systemd service (default.target)..."

mkdir -p "$TARGET_HOME/.config/systemd/user"
cat > "$TARGET_HOME/.config/systemd/user/usb-notify.service" <<'SERVICE'
[Unit]
Description=USB Notification Handler
Documentation=man:notify-send(1)
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.config/hypr/scripts/usb-notify-handler.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SERVICE
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/systemd/user/usb-notify.service"
echo "  ✅ $TARGET_HOME/.config/systemd/user/usb-notify.service (default.target)"

# ─── 6) execs.lua güncelle (udiskie + servis) ──────────────────────────
echo "[6/6] execs.lua güncelleniyor..."

su - "$TARGET_USER" -s /bin/bash <<LUA
    SCRIPT="\$HOME/.config/hypr/hyprland/execs.lua"
    if [ -f "\$SCRIPT" ]; then
        if ! grep -q "udiskie" "\$SCRIPT" 2>/dev/null; then
            sed -i '/-- Start shell/i\\    -- USB automount\\n    hl.exec_cmd("udiskie --no-notify")' "\$SCRIPT"
        fi
        sed -i '/usb-notify\\.sh/d' "\$SCRIPT"
        echo "  ✅ execs.lua güncellendi"
    else
        echo "  ⚠️ execs.lua bulunamadı"
    fi
LUA

# ─── Reload + başlat ──────────────────────────────────────────────────────
echo ""
echo "=== Kurallar yükleniyor ==="
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=block
echo "  ✅ udev reload"

su - "$TARGET_USER" -c 'systemctl --user daemon-reload 2>&1'
su - "$TARGET_USER" -c 'systemctl --user disable usb-notify.service 2>&1' || true
su - "$TARGET_USER" -c 'systemctl --user enable --now usb-notify.service 2>&1'
echo "  ✅ usb-notify.service active + enabled (default.target)"
