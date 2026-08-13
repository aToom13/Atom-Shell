# Atom Shell

Atom Shell, Caelestia Shell v2.3 tabanı üzerinde geliştirilen, kendi güncelleme ve yedekleme sistemine sahip kişisel bir Hyprland masaüstü katmanıdır. Proje; özel Nexus sayfalarını, gelişmiş ağ tanılamayı, aygıt yönetimini ve taşınabilir Hyprland yapılandırmasını tek depoda tutar.

> Atom Shell bağımsız bir fork’tur; Caelestia projesinin resmî sürümü değildir. İç QML ad alanları ve `~/.config/caelestia` şeması upstream uyumluluğu için korunur.

## Öne çıkanlar

- Nexus içinde ekran, güncelleme, eklenti, klavye kısayolu, güç/kilit ve ayrıntılı servis ayarları
- Wi‑Fi, Ethernet, kayıtlı ağlar, NetworkManager VPN profilleri ve v2.3 VPN sağlayıcı yönetimi
- Canlı bağlantı bilgisi, ağ/DNS/HTTPS tanılama, LAN/USB/KDE Connect keşfi
- Yapılandırılabilir görev çubuğu bileşenleri, durum simgeleri ve hızlı araçlar
- Tek komutla kurulum, güncelleme, doktor, kaldırma ve yedekten geri alma
- Mevcut kullanıcı dosyalarına dokunmadan önce tarih damgalı yedek
- Arch/CachyOS için yerel; Debian/Ubuntu/Mint için Nix tabanlı modern Qt/Quickshell runtime’ı

## Destek durumu

| Dağıtım | Runtime | Durum |
|---|---|---|
| Arch Linux | Yerel Qt 6.9+, Quickshell | Tam destek |
| CachyOS | Yerel Qt 6.9+, Quickshell | Tam destek |
| Debian 13/14 | Nix runtime + apt entegrasyon paketleri | Desteklenir |
| Ubuntu / Linux Mint | Nix runtime + apt entegrasyon paketleri | Deneysel; Hyprland 0.55+ zorunlu |

Hyprland Lua yapılandırması 0.55 ile geldiği için daha eski Hyprland sürümleri çalışmaz. Ubuntu/Mint depolarındaki Hyprland eskiyse kurucu Nix profilindeki güncel Hyprland’ı ekler; oturum yöneticisinin bu binary’yi kullandığını ayrıca doğrulamak gerekir. Ayrıntılar: [Dağıtım notları](docs/DISTROS.md).

## Kurulum

```bash
git clone https://github.com/aToom13/Atom-Shell.git
cd Atom-Shell
./install.sh --dry-run
./install.sh
```

Kurucu root olarak çalıştırılmaz. Sistem paketi gerektiğinde açıkça `sudo` çağırır.

Varsayılan `merge` modu mevcut `~/.config/caelestia` ve `~/.config/hypr` değerlerini korur; yalnızca eksik şablonları ekler. Bilinen eski v2.2 `bar.status` alanı ile eski Hyprland başlatma komutları, önce tam dizin yedeği alınarak v2.3/Atom Shell biçimine otomatik taşınır. Depodaki tam masaüstü ayarlarını uygulamak için:

```bash
./install.sh --config-mode replace
```

`replace`, önce iki dizini de yedekler. Diğer yararlı seçenekler:

```text
--dry-run                 Değişiklik yapmadan planı gösterir
--no-packages             Paket yöneticisine dokunmaz
--no-build                Qt/QML runtime’ını yeniden derlemez
--profile minimal|full    Temel veya bütün entegrasyonlar
--runtime auto|native|nix Runtime yöntemini seçer
--install-nix             Nix yoksa resmî kurucuyu çalıştırır
--config-mode merge|replace|skip
```

Debian/Ubuntu/Mint üzerinde otomatik kurulum için:

```bash
./install.sh --install-nix
```

## Kullanım

```bash
atomshell start
atomshell stop
atomshell restart
atomshell status
atomshell settings
atomshell doctor
```

`~/.local/bin` PATH içinde değilse shell profilinize şunu ekleyin:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Güncelleme güvenliği

Normal sistem güncellemesi Atom Shell kaynaklarını silmez:

- Shell kodu kullanıcıya ait `~/.config/quickshell/caelestia` dizinindedir.
- Yerel derlenmiş eklentiler `~/.local/share/atomshell/runtime` altında tutulur.
- `/usr/share` ve `/etc/xdg` içindeki `caelestia-shell` paket dosyaları değiştirilmez.
- Quickshell, kullanıcı dizinini sistemdeki `/etc/xdg/quickshell/caelestia` kopyasından önce seçer.

Qt veya Quickshell ABI değiştiğinde yerel eklentiyi yeniden derlemek gerekir. Bunu güvenli güncelleyici yapar:

```bash
atomshell update --check
atomshell update
```

Güncelleyici kirli Git çalışma ağacında ilerlemez, yalnızca fast-forward kabul eder, smoke testini çalıştırır ve kurulumu yedekleyerek yeniler.

Shell’i doğrudan `qs -c caelestia` veya `caelestia shell` ile açmayın: sistemde v2.2 paketi kalmışsa v2.3 ayarlarını eski plugin ile yükler ve `Unknown option bar.statusIcons` uyarısı verir. `atomshell start/restart` her zaman projeye ait doğru runtime’ı seçer.

## Yedek, geri alma ve kaldırma

Yedekler burada tutulur:

```text
~/.local/state/atomshell/backups/YYYYMMDD-HHMMSS[-N]/
```

Bir yedeği listelemek veya geri yüklemek için:

```bash
./rollback.sh
./rollback.sh ~/.local/state/atomshell/backups/20260813-150000
```

Kaldırma kullanıcı ayarlarını varsayılan olarak korur:

```bash
atomshell uninstall
atomshell uninstall --purge-config
```

Kurucunun yüklediği sistem paketleri otomatik kaldırılmaz; başka masaüstü bileşenleri de onları kullanabilir.

## Dizin yapısı

```text
assets/, components/, modules/, services/, utils/  Shell kaynakları
plugin/, extras/                                    Derlenen Caelestia uyumluluk modülleri
config/caelestia/                                   Taşınabilir shell ayar şablonları
config/hypr/                                        Hyprland Lua yapılandırması ve yardımcılar
scripts/                                            Kurulum altyapısı
docs/                                               Mimari ve dağıtım belgeleri
tests/                                              Statik ve dry-run testleri
```

Geliştirme ve upstream birleştirme: [CONTRIBUTING.md](CONTRIBUTING.md). Güvenlik modeli: [SECURITY.md](SECURITY.md).

## Kaynak ve lisans

Atom Shell, GPL-3.0-only lisanslı [Caelestia Shell](https://github.com/caelestia-dots/shell) projesinden türetilmiştir ve aynı lisansla dağıtılır. Orijinal proje ve katkıcılarının telif hakları korunur. Ayrıntı için [LICENSE](LICENSE) dosyasına bakın.

---

## English summary

Atom Shell is an independent, GPL-3.0-only desktop-shell fork based on Caelestia Shell v2.3. It keeps the shell source in the user configuration directory, isolates compiled plugins in a user-owned runtime, and provides safe install, update, backup, rollback and uninstall commands. Arch/CachyOS use a native runtime; Debian/Ubuntu/Mint use Nix for a consistent modern Qt/Quickshell stack. Existing Hyprland and Caelestia settings are preserved by default.
