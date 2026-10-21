#!/bin/bash
# USB Notification Handler — udev'den FIFO pipe ile haberleşir

USER_NAME="${USER:-$(id -un)}"
MEDIA_DIR="/run/media/$USER_NAME"
PIPE="/run/user/$(id -u)/usb-event"
mkdir -p "$MEDIA_DIR"

# FIFO pipe oluştur (sadece yoksa, her seferinde silme — udev yarışmasın)
if [ ! -p "$PIPE" ]; then
    mkfifo "$PIPE" 2>/dev/null
    chmod 666 "$PIPE" 2>/dev/null
fi

# ─── FIFO okuyucu (<> ile aç = read-write, asla EOF gelmez) ───────────
while read -r line; do
    [ -z "$line" ] && continue

    ACTION=$(echo "$line" | cut -d'|' -f1)
    LABEL=$(echo "$line" | cut -d'|' -f2)
    DEV=$(echo "$line" | cut -d'|' -f3)

    if [ "$ACTION" = "add" ]; then
        (
            HANDLED=$(notify-send -u low \
                -A "open=Klasörde aç" \
                -i media-removable -a "USB" \
                -t 8000 \
                "💾 Bağlandı" "$LABEL ($DEV)" --wait 2>/tmp/usb-notify-err.log)

            if [ "$HANDLED" = "open" ]; then
                # Mount noktasını lsblk ile bul (partition'larda olabilir, disk'te değil)
                MOUNT=""
                for i in 1 2 3 4 5 6 7 8; do
                    MOUNT=$(lsblk -no MOUNTPOINT "/dev/$DEV" 2>/dev/null | grep -v '^$' | head -n1)
                    [ -n "$MOUNT" ] && break
                    sleep 1
                done

                if [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
                    xdg-open "$MOUNT"
                else
                    notify-send -u critical -a "USB" \
                        "⚠️ Mount bulunamadı" "$DEV henüz bağlanmamış"
                fi
            fi
        ) &

    elif [ "$ACTION" = "remove" ]; then
        notify-send -u low -a "USB" -i media-removable \
            "🔌 Bağlantı Kesildi" "$LABEL ($DEV)"
    fi
done <> "$PIPE"
# ^^^ <> = read-write mode. Shell FIFO'yu yazmaya da açar,
#     böylece writer kapanınca EOF gelmez. Sürekli açık kalır.
