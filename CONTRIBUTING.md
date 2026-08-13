# Katkı ve upstream güncelleme

Değişiklikten önce `./tests/smoke.sh` çalıştırın. Native geliştirme ortamında ayrıca CMake derlemesi ve çalışan Hyprland oturumunda `atomshell restart` testi beklenir.

Kod biçimi upstream Caelestia Shell stilini izler. İç `Caelestia.*` ad alanlarını sırf marka değişikliği için yeniden adlandırmayın; bu, upstream birleştirmelerini gereksiz yere zorlaştırır.

## Upstream v2.x birleştirme

```bash
git fetch upstream --tags
git switch main
git merge --no-ff v2.3.0
./tests/smoke.sh
./install.sh --dry-run --no-packages
```

Çakışmalarda Atom Shell’in ek Nexus sayfalarını koruyun; upstream yapılandırma API’si değişmişse özel sayfaları yeni API’ye taşıyın. Özellikle `ConfigList` alanları QML’de `.values`, `.count`, `.at()`, `.insert()`, `.move()` ve `.remove()` ile kullanılır.

Birleştirmeden sonra native runtime’ı baştan derleyin. Ağ, ses, kilit, görev çubuğu, launcher, bildirim ve aygıt sayfalarını görsel olarak test edin.
