# Mimari

Atom Shell üç katmanı birbirinden ayırır:

1. `~/.config/quickshell/caelestia`: Canlı QML shell kaynağı. Dizin adı, Caelestia CLI’nin `qs -c caelestia` IPC çağrılarıyla uyumluluk için sabittir.
2. `~/.local/share/atomshell/runtime`: Yerel C++/QML eklentileri ve yardımcı kütüphaneler. Sistem paketleriyle dosya çakışması yoktur.
3. `~/.config/caelestia` ve `~/.config/hypr`: Kullanıcı verisi. Güncellemede varsayılan olarak yalnızca eksik dosyalar eklenir.

`~/.local/bin/atomshell` gerekli `QML_IMPORT_PATH` ve `CAELESTIA_LIB_DIR` değişkenlerini ayarlar. Yerel kurulumda sistemdeki `qs`, Nix kurulumunda `atomshell-runtime` çalıştırılır. Her iki yol da shell’i `caelestia` adlı Quickshell yapılandırması olarak açar.

Bu başlatıcı aynı config’in eski `quickshell -d` gözetmenini PID üzerinden tamamen kapatır; yalnızca onun çocuk sürecini öldürüp v2.2 runtime ile yeniden doğmasına izin vermez. Hyprland başlangıç ve yeniden başlatma kısayolları bu nedenle doğrudan `atomshell` kullanır.

Bu ayrım sayesinde `caelestia-shell` sistem paketi kurulu kalabilir. Paket `/etc/xdg` altında güncellense bile kullanıcı kopyası önceliklidir. Atom Shell hiçbir paket dosyasını yamalamaz.

## Kurulum işlemi

- Dağıtım ve runtime seçilir.
- İsteğe bağlı sistem entegrasyon paketleri kurulur.
- Native modda plugin/extras/m3shapes CMake ile kullanıcı prefix’ine derlenir; Nix modunda flake profile eklenir.
- Eski canlı shell yedeklenir, kaynak dizinleri kontrollü `rsync --delete` ile yenilenir.
- Kullanıcı ayarları `merge`, `replace` veya `skip` politikasına göre ele alınır.
- Merge sırasında v2.2 `bar.status` değerleri kayıpsız `bar.statusIcons` listesine, eski Hyprland shell komutları `atomshell` komutlarına taşınır; migration öncesi tam dizin yedeği alınır.
- Manifest kaynak depo yolunu ve runtime türünü kaydeder.

## Yapılandırma sahipliği

Shell kaynak dizini Atom Shell tarafından yönetilir. Elle değiştirilebilir, fakat güncellemeden önce değişikliklerin Git deposuna taşınması önerilir. Canlı shell her kurulumdan önce bütünüyle yedeklendiğinden yerel değişiklikler geri alınabilir.

`~/.config/caelestia` ve `~/.config/hypr` kullanıcıya aittir. `merge` bunları ezmez. `replace` yalnızca açıkça istendiğinde ve yedekten sonra kullanılır.
