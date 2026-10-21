# Oyun Modu, Kare Üretimi ve Performans Optimizasyonu (Game Mode)

[English](game-mode.md) | **Türkçe**

Atom Shell, Linux üzerinde oyun oynarken en yüksek kare hızı (FPS), en düşük giriş gecikmesi ve kusursuz kare senkronizasyonu sunmak için çok katmanlı bir **Oyun Modu (Game Mode)** mimarisi içerir.

---

## 🎮 İki Aşamalı Kontrol Mimarisi

### 1. Hızlı Oyun Modu ve Kare Üretimi Paneli (`modules/utilities/cards/GameModePanel.qml`)
Hızlı Araçlar (Utilities Drawer - `Super + U`) içinden doğrudan erişilen kontrol panelidir:
- **Kare Üretimi (Frame Generation):** Kapalı, Otomatik, 2x ve 3x modları arasında anında geçiş.
- **Aktif Uygulama / Oyun Seçimi:** Çalışan Vulkan/OpenGL/Wine pencerelerini algılar ve optimizasyonu hedeflenen oyuna kilitler.
- **3D Test Küpü:** Ek donanım veya oyun yüklemeden kare üretimi ve gecikme ayarlarını anında test etmek için tek tıkla 3D sahnesi açar (`vkcube` tabanlı).
- **Canlı Oyun İçi HUD (Game HUD):** Gerçek oyun FPS değeri, CPU kullanımı, RAM kullanımı ve CPU sıcaklığını ekranda gösterir. HUD pozisyonu (sağ üst, sol üst vb.), marjlar ve yazı boyutu özelleştirilebilir.

### 2. Nexus Sistem Yapılandırması (`modules/nexus/pages/services/GameModePage.qml`)
Nexus Ayarlar Merkezi içindeki derinlemesine optimizasyon katmanıdır:
- **Hyprland Efekt İptali:** Pencere animasyonları, köşe yuvarlatmaları, şeffaflık ve bulanıklık (blur) otomatik kapatılır; tam ekran oyunlar doğrudan tarama moduna (direct scanout) geçer.
- **Donanım Profili:** Sistem güç profili ve CPU governor otomatik olarak `performance` moduna alınır.
- **Rahatsız Etmeyin (DND):** Oyun sırasında masaüstü bildirimleri ve sesli uyarılar susturulur.
- **Oyun Profilleri (`config/caelestia/game-profiles.json`):** Steam, Lutris veya yerel oyunlar başladığında oyuna özel başlatma parametreleri ve render kuralları devreye girer.

---

## 🚀 Kare Üretimi (Frame Generation) Mantığı

Kare üretimi, ekran yenileme hızı (Hz) oyunun sunduğu FPS'in üzerinde olduğunda akıcılığı katlamak için tasarlanmıştır:
- Oyun zaten ekran yenileme hızına eşit veya yüksek FPS veriyorsa, ek gecikme yaratmamak için kare üretimi otomatik beklemede (standby) kalır.
- Oyun FPS'si düştüğünde akıllı hareket enterpolasyonu ile eksik kareler tamamlanır ve ekrana gönderilir.

---

## 🔧 Yapılandırma Dosyaları

- **Oyun Modu Kuralları:** `~/.config/caelestia/game-mode.json`
- **Kayıtlı Profiller:** `~/.config/caelestia/game-profiles.json`
- **Arka Plan Motoru:** `utils/game_mode.py`, `utils/game_profiles.py` ve `services/GameProfiles.qml`
- **Steam Entegrasyonu:** `config/bin/steam-sw`
