# Nexus Ayarlar Merkezi (Nexus Control Center)

[English](nexus.md) | **Türkçe**

Nexus (`modules/nexus/`), Atom Shell masaüstünün tüm görsel, donanımsal ve davranışsal özelliklerini tek bir çatı altında yöneten yerleşik grafiksel kontrol merkezidir.

## 🚀 Açılış ve Kısayollar

- **Klavye Kısayolu:** `Super + I`
- **Komut Satırı (CLI):** `atomshell nexus` veya `quickshell ipc call nexus open`
- **Üst Panel:** Saat veya durum simgeleri üzerinden doğrudan erişim

---

## 📑 Nexus Kontrol Sayfaları

Nexus bünyesinde 15 adet uzmanlaşmış ayar sayfası yer almaktadır:

| No | Sayfa | İkon | Kategori | Açıklama ve Özellikler |
|:---:|---|---|---|---|
| **0** | **Wallpaper & style** | `palette` | Görünüm | **Duvar Kağıdı ve Renk Şeması:** Aktif duvar kağıdını seçme, Material You (M3) algoritmasıyla duvar kağıdından otomatik açık/koyu renk paleti türetme, bulanıklık (blur) ve şeffaflık katman ayarları (`services/Colours.qml`). |
| **1** | **Display** | `monitor` | Bağlantı | **Monitör ve Çözünürlük:** Çıkışlar, çözünürlük, yenileme hızı (Hz), ölçekleme ve sürükle-bırak monitör dizilimi. Yapılan değişiklikler onaylanmazsa 15 saniye içinde güvenli geri alma (`display_settings.py`, `monitor-overrides.tsv`). |
| **2** | **Network** | `wifi` | Bağlantı | **Ağ Yönetimi:** Wi-Fi ağlarını tarama, parola girme, statik IP/DNS, Ethernet durumu, WireGuard/Tailscale VPN profilleri, ağ güvenlik kontrolü ve bağlı olunan Wi-Fi ağını QR kod ile paylaşma (`network-security.sh`, `wifi-qr.sh`). |
| **3** | **Connected devices** | `devices_other` | Bağlantı | **Bağlı Aygıtlar:** Bluetooth cihaz eşleştirme, güvenilir cihazlar, pil seviyesi izleme, KDE Connect durumu ve bağlı USB çevre birimlerinin yönetimi (`modules/nexus/pages/BluetoothPage.qml`). |
| **4** | **Audio** | `volume_up` | Bağlantı | **Ses Mikseri:** Varsayılan giriş/çıkış ses kartları seçimi, uygulama bazlı bağımsız ses seviyesi sürgüleri ve PipeWire / WirePlumber yönlendirmeleri (`services/Audio.qml`). |
| **5** | **Power & lock** | `lock_clock` | Sistem | **Güç ve Kilit Ekranı:** Ekran kilitlenme süresi, boşta kalma (idle) davranışları, askıya alma/hazırda bekletme profilleri ve Akıllı Hazırda Bekletme (Graceful Hibernation) tetikleme eşikleri (`modules/nexus/pages/PowerAndLockPage.qml`). |
| **6** | **Updates** | `system_update` | Sistem | **Sistem Güncellemeleri:** Pacman, AUR (yay/paru) ve Flatpak güncellemelerini tek bir yerden tarama, paket detaylarını inceleme, canlı güncelleme terminali ve güncelleme planı (`services/UpdateRunner.qml`). |
| **7** | **Plugins** | `extension` | Sistem | **Hyprland Eklentileri:** `hyprpm` entegrasyonuyla Hyprland eklentilerini kurma, etkinleştirme, derleme ve çalışma zamanı parametrelerini ayarlama (`config/hypr/scripts/manage-plugin-settings.sh`). |
| **8** | **Keyboard shortcuts** | `keyboard` | Sistem | **Kısayol Düzenleyici:** Pencere, iş alanı ve kabuk kısayollarını arama, filtreleme, çakışma tespiti ve grafiksel arayüzden yeni kısayol atama (`utils/builtin_shortcuts.py`, `config/hypr/shortcuts.txt`). |
| **9** | **Panels** | `dock_to_bottom` | Kabuk | **Panel Özelleştirme:** Üst/yan panel modülleri, launcher klasörleme (`launcher-folders.json`), popout davranışları ve kompakt mod seçenekleri (`modules/nexus/pages/PanelsPage.qml`). |
| **10** | **Apps** | `apps` | Kabuk | **Uygulama Yönetimi:** Varsayılan tarayıcı, terminal, dosya yöneticisi MIME ilişkilendirmeleri (`utils/default_apps.py`), oturum başlangıcında otomatik başlayan uygulamalar (`utils/autostart.py`) ve gizlenen uygulamalar. |
| **11** | **Services** | `build` | Kabuk | **Arka Plan Servisleri:** Servis sorgulama aralıkları, hava durumu API ve konum koordinatları, şarkı sözü sağlayıcı önceliği (LRCLIB/NetEase) ve telefon otomatik bağlantı kuralları (`config/caelestia/shell.json`). |
| **12** | **Language & region** | `globe` | Kabuk | **Dil ve Bölge:** Arayüz dili (Türkçe / English), saat formatı (12h/24h), hava durumu birimleri (°C/°F), klavye düzenleri ve sayı biçimleri (`utils/region.py`, `services/I18n.qml`). |
| **13** | **Game Mode** | `gamepad` | Kabuk | **Oyun Modu Yapılandırması:** Sistem güç profili, CPU governor seçimi, kompozitör animasyon/bulanıklık iptalleri, Rahatsız Etmeyin otomasyonu ve oyun profili eşleştirmeleri (`services/GameMode.qml`, `utils/game_mode.py`). |
| **14** | **About** | `info` | Bilgi | **Sistem Bilgisi:** Dağıtım adı, Linux çekirdek sürümü, Hyprland ve Quickshell sürümleri, donanım özellikleri (`modules/nexus/pages/AboutPage.qml`). |

---

## 🛠️ Mimari ve Veri Akışı

1. **Çift Yönlü Yapılandırma:** Nexus üzerinden yapılan her değişiklik, anında ilgili JSON yapılandırma dosyasına (`~/.config/caelestia/`) yazılır ve QML sinyal-yuva mekanizmasıyla kabukta anında canlı olarak güncellenir.
2. **Güvenli Geri Alma (Safe Rollback):** Ekran çözünürlüğü gibi kritik ayarlarda, kullanıcının onaylamaması durumunda 15 saniyelik zaman aşımı ile eski kararlı ayarlara otomatik dönülür.
3. **Modüler Sayfa Kaydı:** Sayfalar `modules/nexus/PageRegistry.qml` üzerinden dinamik yüklenir; bu sayede bellek kullanımı optimize edilir.
