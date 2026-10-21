# Telefon Entegrasyonu ve Tailscale Ağı (Phone & Tailscale)

[English](phone-tailscale.md) | **Türkçe**

Atom Shell, Android akıllı telefonunuz ile masaüstünüz arasında hem ev ağında hem de dışarıdayken kesintisiz ve güvenli bir çift yönlü bağlantı köprüsü kurar.

---

## 📱 Hibrit Bağlantı Mimarisi

Telefon entegrasyonu hem **KDE Connect** protokolünü hem de **Kablolu / Kablosuz ADB** kanallarını birlikte kullanır:

- **Canlı Durum Göstergesi:** Üst çubukta (`bar/components/Phone.qml`) ve Kontrol Panelinde (`dashboard/Phone.qml`) telefonun pil seviyesi, şarj durumu ve aktif bağlantı türü (USB, Yerel Wi-Fi, Tailscale veya Bluetooth) anlık olarak gösterilir.
- **Sürükle-Bırak Dosya Aktarımı:** Kontrol paneli telefon sekmesine herhangi bir dosyayı sürükleyip bırakarak kablosuz olarak telefonunuza gönderebilirsiniz.
- **Medya ve Ses Kontrolü:** Telefonunuzda çalan medyayı bilgisayardan duraklatabilir, sonraki parçaya geçebilir ve telefon sesini kısıp artırabilirsiniz.

---

## 🛠️ Yerleşik Komutlar (`config/bin/`)

| Komut | Açıklama |
|---|---|
| `phone-control` | Telefon durumu, medya kontrolleri ve eylemler için birleşik CLI arabirimi. |
| `phone-mirror` | `scrcpy` kullanarak telefon ekranını bilgisayarda gecikmesiz ve yüksek çözünürlükle açar. |
| `phone-answer` | Bilgisayar başındayken gelen telefon aramasını doğrudan masaüstünden yanıtlar. |
| `phone-ring` | Telefon sessizde olsa dahi alarm çaldırarak cihazı bulmayı sağlar. |
| `phone-wifi` | Telefonu yerel ağ üzerinden kablosuz ADB ile otomatik eşleştirir ve bağlar. |
| `phone-clipboard-image` | Wayland panosuna kopyalanan resimleri anında telefon panosuna aktarır. |

---

## 🌐 Tailscale ile Kesintisiz Uzaktan Erişim

Ev ağı dışındayken bile tüm bu özelliklerin kesintisiz çalışması için Tailscale mesh ağı kullanılır:

1. **Otomatik IP Keşfi (`config/bin/kdeconnect-tailscale-start`):** Açılışta `tailscale status --json` çıktısını tarayarak ağdaki Android cihazın Tailscale IP adresini otomatik tespit eder ve KDE Connect yapılandırmasına (`~/.config/kdeconnect/config`) `customDevices` olarak ekler.
2. **Systemd Servisi (`kdeconnect-tailscale.service`):** Masaüstü başladığında Tailscale bağlantısını bekler ve eşleşmeyi yeniler.
3. **Hyprland Entegrasyonu:** `config/hypr/hyprland/execs.lua` içinde oturum açıldığında otomatik çalıştırılır:
   ```lua
   hl.exec_cmd("systemctl --user start kdeconnect-tailscale.service")
   ```

---

## 🔒 Güvenli Otomasyon ve Pano Senkronizasyonu

- **Görsel Pano Senkronizasyonu (`phone-clipboard-image.service`):** `wl-paste` ile ekran görüntüsü veya kopyalanan resimleri izler, telefon üzerindeki eşlikçi uygulamaya ileterek Android panosuna yazar.
- **İzole SSH Sunucusu (`phone-automation-sshd.service`):** Port 8022 üzerinde sadece SSH anahtarı ile çalışan güvenli bir servis başlatır. Tasker, Termux veya diğer Android otomasyon araçları ile bilgisayarda güvenle uzaktan komut çalıştırabilirsiniz.
