# Security

## Kurucu güvenlik modeli

- `install.sh` root olarak çalışmayı reddeder.
- Sistem değişiklikleri yalnızca dağıtım paketlerinin kurulumu ve isteğe bağlı resmî Nix kurulumudur; gerektiğinde `sudo` görünür biçimde çağrılır.
- `--dry-run` dosya veya paket değiştirmeden komutları gösterir.
- Değiştirilecek kullanıcı dosyaları önce `~/.local/state/atomshell/backups` altına kopyalanır.
- Kaldırıcı sistem paketlerini otomatik silmez.
- Eski root/udev tabanlı USB bildirim kurulumu kullanılmaz. Bildirim servisi kullanıcı oturumunda çalışır.

Nix kurucusu kullanılacaksa betik yalnızca `https://nixos.org/nix/install` adresinden TLS zorlamasıyla indirilir ve kullanıcı `--install-nix` ile ya da etkileşimli onayla izin verir.

## Güvenlik açığı bildirimi

Komut enjeksiyonu, ayrıcalık yükseltme veya hassas veri sızıntısı bulursanız herkese açık issue açmadan önce depo sahibine özel GitHub güvenlik bildirimi gönderin. Bildirimde etkilenen commit, çoğaltma adımları ve olası etkiyi belirtin.
