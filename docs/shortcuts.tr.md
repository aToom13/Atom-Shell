# Klavye Kısayolları ve Pencere Yönetimi Rehberi (Shortcuts Guide)

[English](shortcuts.md) | **Türkçe**

Atom Shell, Hyprland v0.55+ Lua mimarisi üzerine kurulu akıcı, ergonomik ve çakışmasız bir klavye kısayol sistemi sunar (`config/hypr/hyprland/keybinds.lua`).

---

## ⚡ Hızlı Kısayol Arayıcı ve Rehber

- **Kısayol:** `F12` veya `Super + Shift + H`
- **İşlev:** Ekrana yarı saydam, anında filtrelenebilir bir kısayol arama HUD'ı getirir (`utils/builtin_shortcuts.py`). İstediğiniz eylemi yazarak tuş kombinasyonunu saniyeler içinde bulabilirsiniz.

---

## ⌨️ Temel Sistem Kısayolları

### Kabuk ve Masaüstü Gezinimi

| Kısayol | Eylem |
|---|---|
| `SUPER + SUPER_L` (Super tek basış) | Uygulama Başlatıcıyı Aç / Kapat |
| `SUPER + Tab` | Açık Pencereler Genel Görünümü (Exposé) |
| `SUPER + I` | Nexus Ayarlar Merkezini Aç |
| `F9` | Bildirim ve Kenar Çubuğunu Aç / Kapat |
| `SUPER + U` | Hızlı Araçlar ve Toggles Çekmecesini Aç |
| `SUPER + D` | Dashboard (Kontrol Paneli) Aç / Kapat |
| `ALT + F4` / `SUPER + Backspace` | Oturum ve Güç Menüsü (Kapat, Yeniden Başlat, Kilitle) |
| `SUPER + L` | Ekranı Kilitle |
| `SUPER + V` | Pano Geçmişi (Cliphist) Menüsü |

### Uygulama Başlatma

| Kısayol | Uygulama |
|---|---|
| `SUPER + T` / `SUPER + Enter` | Terminal (`foot` / `kitty`) |
| `SUPER + E` | Dosya Yöneticisi (`thunar`) |
| `SUPER + C` | Kod Düzenleyici (IDE / VS Code) |
| `F7` | Monitör ve Ekran Ayarları |

### Pencere Yönetimi ve Düzenleme

| Kısayol | Eylem |
|---|---|
| `SUPER + Q` | Aktif Pencereyi Kapat |
| `ALT + TAB` | Çalışma alanındaki pencereler arasında hızlı geçiş |
| `SUPER + F` | Tam Ekran (Fullscreen) |
| `SUPER + ALT + F` | Kenarlıklı Büyütülmüş Mod (Maximized) |
| `SUPER + ALT + Space` | Kayan Pencere (Floating) / Döşemeli (Tiled) Geçişi |
| `SUPER + B` | Pencereleri Sekmeli Grup Yap / Gruptan Çıkar |
| `SUPER + P` | Pencereyi Ekrana Sabitle (Pin - Tüm çalışma alanlarında görünür) |
| `SUPER + Sol/Sağ/Yukarı/Aşağı` | Pencereye Odaklan |
| `SUPER + SHIFT + Sol/Sağ/Yukarı/Aşağı` | Pencereyi Belirtilen Yöne Taşı |
| `SUPER + CTRL + Sol/Sağ/Yukarı/Aşağı` | Pencere Boyutunu Ayarla |

### Özel İş Alanları (Special Workspaces)

| Kısayol | İş Alanı |
|---|---|
| `SUPER + S` | Çizim / Genel Özel Alan |
| `SUPER + M` | Müzik Oynatıcı Alanı |
| `SUPER + G` | Oyunlar ve Performans Alanı |
| `SUPER + O` | İletişim / Sohbet Alanı |

### Araçlar ve Medya Kontrolleri

| Kısayol | Eylem |
|---|---|
| `PrtScr` / `SUPER + SHIFT + S` | Alan Seçerek Ekran Görüntüsü veya Video Kaydı Al |
| `F10` | Konuşmadan Metne Sesli Dikteyi Başlat / Bitir |
| `F11` | Ekrandaki Seçili Alanın Yazısını Kopyala (OCR) |
| `CTRL + SUPER + Space` | Medya Oynat / Duraklat |
| `CTRL + SUPER + Page Down` | Sonraki Şarkı |
| `CTRL + SUPER + Page Up` | Önceki Şarkı |
| `XF86AudioRaiseVolume` | Ses Düzeyini Artır |
| `XF86AudioLowerVolume` | Ses Düzeyini Azalt |
| `XF86AudioMute` | Sesi Sustur / Aç |
| `XF86MonBrightnessUp` | Ekran Parlaklığını Artır |
| `XF86MonBrightnessDown` | Ekran Parlaklığını Azalt |

---

## 🛠️ Özel Kısayol Tanımlama

Kişisel kısayollarınızı doğrudan Nexus > Keyboard shortcuts sayfasından ekleyebilir veya `~/.config/caelestia/keybind-overrides.lua` dosyasına yazabilirsiniz. Yapılan değişiklikler kabuk yeniden başlatılmadan hemen etkinleşir.
