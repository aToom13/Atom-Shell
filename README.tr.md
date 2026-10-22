# Atom Shell

[English](README.md) | **Türkçe**

Atom Shell, [Hyprland](https://hyprland.org) için QML ve [Quickshell](https://github.com/outfoxxed/quickshell) ile geliştirilmiş, [Caelestia Shell](https://github.com/caelestia-dots/shell) mimarisini temel alan özelleştirilebilir bir masaüstü kabuğudur.

Üst panel, uygulama başlatıcı, medya kontrolleri, cihaz yönetimi ve Nexus ayarlar merkezini tek arayüzde toplar. Kurulum ve yönetim betikleri bağımlılıkları, yapılandırma yedeklerini, güncellemeleri ve geri alma işlemlerini yönetir. Birincil yerel hedefler Arch Linux ve CachyOS’tur.

---

## Ekran Görüntüleri ve Arayüz Bileşenleri

Aşağıdaki görüntüler, temiz bir kurulumdan doğrudan 1080p olarak yakalanmıştır.

| Masaüstü ve Üst Panel | Uygulama Başlatıcı (Launcher) |
|:---:|:---:|
| ![Masaüstü ve Panel](assets/screenshots/01-desktop-bar.png) | ![Başlatıcı](assets/screenshots/02-launcher.png) |

| Kontrol Paneli Genel Bakış | Kontrol Paneli Medya ve Şarkı Sözleri |
|:---:|:---:|
| ![Genel Bakış](assets/screenshots/03-dashboard-overview.png) | ![Medya](assets/screenshots/04-dashboard-media.png) |

| Telefon Entegrasyonu | Performans Gösterge Paneli |
|:---:|:---:|
| ![Telefon](assets/screenshots/05-dashboard-phone.png) | ![Performans](assets/screenshots/06-dashboard-performance.png) |

| Nexus Ayarlar Merkezi | Oyun Modu ve Kare Üretimi Paneli |
|:---:|:---:|
| ![Nexus](assets/screenshots/11-nexus-settings.png) | ![Oyun Modu](assets/screenshots/15-game-mode-panel.png) |

---

## Öne Çıkan Özellikler

- **Kapsamlı Çift Dilli Arayüz:** Tüm QML modüllerinde tam Türkçe ve İngilizce desteği (`qsTr()` katalogları ve Nexus üzerinden anında canlı dil değişimi).
- **Material You Dinamik Renk Şeması:** Duvar kağıdından otomatik açık/koyu renk paleti türetme, bulanıklık ve şeffaflık kontrolleri.
- **Nexus Ayarlar Merkezi:** Ekran, ağ, Bluetooth, ses, güç, güncellemeler, eklentiler, kısayollar ve uygulamaları yöneten 15 modüler ayar sayfası.
- **Oyun Modu ve Kare Üretimi:** Canlı FPS göstergesi (HUD), kompozitör bypass (direct scanout), GPU/CPU performans profili ve 3D test küpü.
- **Telefon ve Tailscale Entegrasyonu:** Canlı pil durumu, sürükle-bırak dosya transferi, scrcpy ile ekran yansıtma, uzaktan arama yanıtlama ve otomatik cihaz keşfi.
- **Akıllı Hazırda Bekletme (Graceful Hibernation):** Pil kritik eşiğe indiğinde geri sayımlı uyarı ve güvenli disk kaydı.
- **Ergonomik Klavye Kısayolları:** Anında filtrelenebilir kısayol HUD arayıcısı (`F12` / `Super + Shift + H`) ve Hyprland Lua tuş atamaları.
- **Güvenli Kurulum ve Geri Alma:** Etkileşimli kurulum, tarih damgalı yedekler, yapılandırma birleştirme (`merge`) ve geri alma araçları.

---

## Desteklenen Dağıtımlar

| Dağıtım | Runtime | Durum |
|---|---|---|
| **Arch Linux** | Yerel Qt 6.9+, Quickshell | 1. Seviye (Tam Yerel) |
| **CachyOS** | Yerel Qt 6.9+, Quickshell | 1. Seviye (Tam Yerel) |
| **Debian 13/14** | Nix runtime + apt entegrasyonu | Desteklenir |
| **Ubuntu / Linux Mint** | Nix runtime + apt entegrasyonu | Deneysel (Hyprland 0.55+ gerekir) |

Dağıtıma özel ayrıntılar ve paket listeleri için [Dağıtım Kılavuzuna](docs/DISTROS.tr.md) bakabilirsiniz.

---

## Hızlı Başlangıç ve Kurulum

Gereksinimler: Hyprland 0.55+, Qt 6.9+ ve Quickshell 0.3 veya güncel Git sürümü. Kurulum betiği dağıtıma özel bağımlılıkları yönetir; başlamadan önce [Dağıtım Kılavuzunu](docs/DISTROS.tr.md) inceleyin.

Depoyu klonlayıp etkileşimli kurulum sihirbazını başlatın:

```bash
git clone https://github.com/aToom13/Atom-Shell.git
cd Atom-Shell

# Etkileşimli kurulum sihirbazı
./setup.sh
```

Alternatif olarak, `./install.sh` betiğini parametrelerle çalıştırabilirsiniz:

```bash
# Sistem dosyalarını değiştirmeden yapılacakları önizle
./install.sh --dry-run

# Soruları atlayarak otomatik kur
./install.sh --non-interactive --config-mode merge
```

### Kurulum Sonrası Sağlık Denetimi

Bağımlılıkları kontrol etmek ve eksik entegrasyonları görmek için tanılama komutunu çalıştırın:

```bash
atomshell doctor
```

---

## Kabuk Yönetim Komutları

Yönetim komutu `~/.local/bin/atomshell` olarak kurulur:

```bash
atomshell start      # Kabuğu arka planda başlat
atomshell stop       # Aktif kabuğu güvenle durdur
atomshell restart    # Kabuk bileşenlerini yeniden yükle
atomshell nexus      # Nexus Ayarlar Merkezini aç
atomshell doctor     # Sistem bağımlılıklarını denetle
atomshell log        # Canlı quickshell günlüklerini izle
```

---

## Modüler Belgeler

Ayrıntılı teknik rehberler modüler dökümanlara ayrılmıştır:

- **[Nexus Ayarlar Merkezi Rehberi](docs/nexus.tr.md):** 15 kontrol sayfası ve yapılandırma durumu.
- **[Oyun Modu ve Kare Üretimi Rehberi](docs/game-mode.tr.md):** Frame Generation, oyun içi HUD, VRR ve test küpü.
- **[Telefon ve Tailscale Rehberi](docs/phone-tailscale.tr.md):** KDE Connect, kablosuz ADB, pano senkronizasyonu ve SSH otomasyonu.
- **[Klavye Kısayolları Rehberi](docs/shortcuts.tr.md):** Pencere yönetimi, özel alanlar ve kısayol arama HUD'ı.
- **[Mimari ve Çalışma Mantığı](docs/ARCHITECTURE.tr.md):** Quickshell yaşam döngüsü, IPC çağrıları ve yapılandırma katmanları.
- **[Dağıtım Notları](docs/DISTROS.tr.md):** Platform gereksinimleri, paket listeleri ve Nix runtime ayrıntıları.

## Lisans ve temel alınan proje

Genel Kamu Lisansı v3.0 (GPL-3.0) altında lisanslanmıştır. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakabilirsiniz. Upstream Caelestia Shell mimarisi ve katkıcılarına ait telif hakları saklıdır.
