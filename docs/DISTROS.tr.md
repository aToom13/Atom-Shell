# Dağıtım notları

[English](DISTROS.md) | **Türkçe**

## Arch Linux ve CachyOS

Birincil ve yerel hedef budur. Kurucu Qt, Quickshell, Caelestia CLI, derleme araçları ve masaüstü entegrasyonlarını pacman ile; gerekirse `paru`/`yay` ile kurar. C++ eklentileri mevcut Qt sürümüne karşı derlendiği için büyük Qt güncellemelerinden sonra `atomshell update` veya `./install.sh --no-packages` çalıştırılmalıdır.

## Debian 13/14

Host servisleri apt ile, modern Qt/Quickshell/Caelestia runtime’ı Nix ile kurulur. Debian’ın Hyprland paketi 0.55 veya yeniyse kullanılabilir; değilse kurucunun profile eklediği Nix Hyprland kullanılmalıdır.

## Ubuntu ve Linux Mint

Ubuntu/Mint’in Qt ve Hyprland paketleri sürüme göre Atom Shell gereksinimlerinin gerisinde kalabilir. Bu nedenle kurucu Nix runtime’ını varsayar ve Nix Hyprland’ı profile ekler. Display manager eski `/usr/bin/Hyprland` oturumunu açıyorsa `~/.nix-profile/bin/Hyprland` kullanan bir Wayland session girdisi oluşturmak gerekebilir.

Bu hedef “deneysel” olarak işaretlidir çünkü portal, ekran paylaşımı ve polkit agent paket adları dağıtım sürümleri arasında değişir. `atomshell doctor` eksikleri gösterir.

## Asgari sürümler

- Hyprland 0.55 (Lua config desteği)
- Qt 6.9 (Atom Shell v2.3 plugin CMake gereksinimi)
- Quickshell 0.3 veya güncel git sürümü
- CMake 3.19; modern Ninja ve C++20 derleyici

## Paket grupları

Temel: NetworkManager, PipeWire/WirePlumber, notification daemon istemcileri, jq, rsync, ripgrep ve Git.

Tam profil: Bluetooth/Blueman, KDE Connect/SSHFS, udiskie, inotify-tools, ekran görüntüsü araçları, parlaklık/DDC, clipboard history, polkit agent, keyring, Geoclue/Gammastep ve tanılama yardımcıları.

Kurucu dağıtımda bulunmayan isteğe bağlı apt paketlerini atlar; `atomshell doctor` işlev bazında uyarır.
