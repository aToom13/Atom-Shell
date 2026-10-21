// ponytail: literal token/phrase search; add typo tolerance only if needed.
function normalize(value) {
    return String(value).toLowerCase().replace(/ı/g, "i").normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/\b(windows|win|meta)\b/g, "super")
        .replace(/\b(control|kontrol)\b/g, "ctrl")
        .replace(/\b(bosluk|spacebar)\b/g, "space")
        .replace(/\besc\b/g, "escape")
        .replace(/\benter\b/g, "return")
        .replace(/\bequal\b/g, "=").replace(/\bminus\b/g, "-")
        .replace(/←/g, "left").replace(/→/g, "right")
        .replace(/↑/g, "up").replace(/↓/g, "down")
        .replace(/\s*\+\s*/g, "+").replace(/\s+/g, " ").trim();
}

function matches(entry, category, query) {
    const keys = normalize(entry[0] + " " + (entry[4] || []).map(binding => binding.original).join(" "));
    const keyTokens = keys.replace(/0–9/g, "0 1 2 3 4 5 6 7 8 9")
        .replace(/\barrows\b/g, "arrows left right up down").split(/[\s+/]+/);
    const haystack = normalize([entry[0], entry[1], (entry[2] || []).join(" "), category.title, category.keywords || ""].join(" "));
    const terms = expandQuery(query).match(/"[^"]*"|[^\s+]+/g) || [];
    return terms.every(term => {
        if (term.startsWith('"') && term.endsWith('"') && term.length > 1)
            return haystack.includes(normalize(term.slice(1, -1)));
        const token = normalize(term.replace(/"/g, ""));
        if (/^(super|ctrl|alt|shift|space|tab|escape|return|backslash|left|right|up|down|comma|period)$/.test(token) || /^[a-z0-9=,.-]$/.test(token))
            return keyTokens.includes(token);
        return haystack.includes(token);
    });
}

function expandQuery(query) {
    return normalize(query)
        .replace(/\b(ekrani ikiye bol[a-z]*|ekrani bol[a-z]*|yan yana ac[a-z]*)\b/g, "tiling")
        .replace(/\b(hep ustte [a-z ]*|tum masaust[a-z]* gor[a-z]*)\b/g, "pin")
        .replace(/\btum pencer[a-z]* goster[a-z]*\b/g, "overview")
        .replace(/\bpencere[a-z]* arasinda gec[a-z]*\b/g, "focus")
        .replace(/\bsessize al[a-z]*\b/g, "ses sustur")
        .replace(/\bpencere[a-z]*\b/g, "pencere")
        .replace(/\bsekme[a-z]*\b/g, "sekme")
        .replace(/\bfareyle\b/g, "fare")
        .replace(/\bmasaust[a-z]*\b/g, "masaustu")
        .replace(/\bkucul[a-z]*\b/g, "kucult")
        .replace(/\bbuyut[a-z]*\b/g, "buyut")
        .replace(/\btasi[a-z]*\b/g, "tasi")
        .replace(/\bses(i|ini)\b/g, "ses")
        .replace(/\bortala[a-z]*\b/g, "ortala")
        .replace(/\btarayici[a-z]*\b/g, "tarayici")
        .replace(/\bdegistir[a-z]*\b/g, "gecis")
        .replace(/\bkopyaladi[a-z]*\b/g, "pano gecmis")
        .replace(/\bgecmis[a-z]*\b/g, "gecmis")
        .replace(/\b(bana|nasil|bir|baska|istiyorum|isterim|icin|almak|al|yapmak|yap|lutfen|acmak|ac|ile|gormek)\b/g, "");
}

function canonicalKey(keys) {
    const parts = normalize(keys).split("+");
    const names = { "=": "equal", "-": "minus", ",": "comma", ".": "period", "\\": "backslash" };
    const key = parts.pop().trim().replace(/page (up|down)/g, "page_$1").replace(/left drag/g, "mouse:272").replace(/right drag/g, "mouse:273");
    return parts.map(part => part.trim()).sort().concat(names[key] || key).join("+");
}

function bindingCandidates(entry, bindings, canonicalBindings) {
    const hardware = {
        "F7 · Monitör": "XF86Display",
        "F9 · Bildirim": "XF86NotificationCenter",
        "F10 · Konuşmadan yazıya": "XF86PickupPhone",
        "F11 · Ekrandan yazı kopyala": "XF86HangupPhone",
        "F12 · Yıldız": "XF86Favorites"
    };
    let label = hardware[entry[0]] || entry[0];
    if (label.startsWith("Capture:") || label.includes("finger") || !label.includes("+") && label !== "Super" && !label.startsWith("XF86"))
        return [];
    const media = {
        "XF86 Audio Play / Pause": "XF86AudioPlay / XF86AudioPause",
        "XF86 Audio Next / Ctrl + Super + Page Down": "XF86AudioNext / Ctrl + Super + Page_Down",
        "XF86 Audio Previous / Ctrl + Super + Page Up": "XF86AudioPrev / Ctrl + Super + Page_Up",
        "XF86 Audio Stop": "XF86AudioStop",
        "XF86 Volume Up / Down": "XF86AudioRaiseVolume / XF86AudioLowerVolume",
        "XF86 Audio Mute / Super + Shift + M": "XF86AudioMute / Super + Shift + M",
        "XF86 Mic Mute": "XF86AudioMicMute",
        "XF86 Brightness Up / Down": "XF86MonBrightnessUp / XF86MonBrightnessDown"
    };
    label = media[label] || (label === "Super" ? "SUPER + SUPER_L" : label);
    let prefix = "";
    let page = false;
    const keys = [];
    label.split(" / ").forEach(part => {
        if (part.includes("+")) {
            prefix = part.slice(0, part.lastIndexOf("+") + 1);
            page = /Page Up/.test(part);
        } else if (prefix) {
            part = prefix + (page ? " Page " : " ") + part;
        }
        if (part.includes("wheel")) {
            ["mouse_down", "mouse_up"].forEach(key => keys.push(canonicalKey(part.replace("wheel", key))));
        } else if (part.includes("arrows")) {
            ["left", "right", "up", "down"].forEach(key => keys.push(canonicalKey(part.replace("arrows", key))));
        } else if (part.includes("0–9")) {
            for (let i = 0; i < 10; i++) keys.push(canonicalKey(part.replace("0–9", i)));
        } else {
            keys.push(canonicalKey(part));
        }
    });
    return bindings.filter((binding, index) => keys.includes(canonicalBindings ? canonicalBindings[index] : canonicalKey(binding.original)));
}

function withBindings(group, bindings) {
    const canonicalBindings = bindings.map(binding => canonicalKey(binding.original));
    return { id: group.id, title: group.title, icon: group.icon, keywords: group.keywords,
        entries: group.entries.map(entry => {
            const candidates = bindingCandidates(entry, bindings, canonicalBindings);
            const changed = candidates.some(binding => binding.changed);
            return [changed ? candidates.map(binding => binding.key).join(" / ") : entry[0], entry[1], entry[2] || [], null, candidates];
        }) };
}

function filterGroups(groups, query, category) {
    return groups.filter(group => !category || group.id === category).map(group => ({
        id: group.id, title: group.title, icon: group.icon,
        entries: group.entries.filter(entry => matches(entry, group, query))
    })).filter(group => group.entries.length > 0);
}

function catalog() {
    return [
        {
            id: "basics", keywords: "temel baslangic kilavuz rehber",
            title: qsTr("Basics"), icon: "lightbulb", entries: [
                ["Tiling vs floating", qsTr("Windows are tiled (auto-arranged) by default. Press Super + Alt + Space to switch the active window between tiled and free-floating mode."), ["tiling", "floating", "tile", "float", "serbest", "yüzen", "yuzen", "pencere modu", "mod", "mod değiştir", "mod degistir", "toggle floating", "resize", "boyut"]],
                ["Resize & move windows", qsTr("Resize the active window with Super + Alt + arrows, move it with Super + Shift + arrows. Dragging with Super + left / right mouse button also works."), ["resize", "boyutlandırma", "boyut", "büyüt", "küçült", "kucult", "move", "taşı", "tasi", "ok tuşları"]],
                ["Workspaces & groups", qsTr("Ctrl + Super + left/right switches workspaces; Ctrl + Super + wheel jumps by ten. Super + arrows changes the focused window. Number key 0 selects the tenth workspace in the current set."), ["workspace", "grup", "group", "masaüstü", "masaustu", "çalışma alanı", "calisma alani"]]
            ]
        },
        {
            id: "apps", keywords: "uygulama kabuk shell apps",
            title: qsTr("Applications & shell"), icon: "apps", entries: [
                ["Super", qsTr("Application launcher"), ["launcher", "başlatıcı", "baslatici", "uygulama", "arama", "menu", "menü"]],
                ["Super + W", qsTr("Web browser"), ["Zen", "tarayici"]],
                ["Super + T", qsTr("Terminal"), ["Kitty", "ucbirim"]],
                ["Super + C", qsTr("Code editor"), ["Antigravity", "IDE", "kod", "editor"]],
                ["Super + E", qsTr("File manager"), ["Thunar", "dosya yoneticisi"]],
                ["Ctrl + Alt + V", qsTr("Advanced audio settings"), ["ses ayarlari mikser pavucontrol"]],
                ["Super + N", qsTr("Notification sidebar"), ["bildirim yan kenar paneli"]],
                ["Ctrl + Alt + C", qsTr("Clear notifications"), ["bildirim temizle sil"]],
                ["Super + K", qsTr("Toggle launcher, dashboard and utilities"), ["baslatici gosterge paneli araclar"]],
                ["Ctrl + Alt + Delete / Alt + F4", qsTr("Session and power menu"), ["oturum guc kapat yeniden baslat alt f4"]],
                ["Super + L", qsTr("Lock screen"), ["kilit ekran kilitle"]],
                ["Super + Alt + L", qsTr("Restore shell and lock"), ["kabuk kurtar geri getir kilitle"]],
                ["Super + Shift + H", qsTr("Keyboard shortcut guide"), ["klavye kisayol rehber yardim arama"]],
                ["Ctrl + Super + Shift + R", qsTr("Stop Atom Shell"), ["kabuk durdur kapat"]],
                ["Ctrl + Super + Alt + R", qsTr("Restart Atom Shell"), ["kabuk yeniden baslat"]]
            ]
        },
        {
            id: "hardware", keywords: "thinkpad donanim simgeli fn klavye",
            title: qsTr("ThinkPad keys"), icon: "keyboard", entries: [
                ["F7 · Monitör", qsTr("Ekran ayarları: bağlı monitörler, çözünürlük ve ölçek"), ["monitor display ekran ayarlari cozunurluk olcek bagli harici"]],
                ["F8 · Uçak", qsTr("Uçak modunu aç/kapat (donanım işlevi)"), ["ucak modu airplane rfkill wifi bluetooth"]],
                ["F9 · Bildirim", qsTr("Bildirim panelini aç/kapat"), ["bildirim panel sidebar notifications"]],
                ["F10 · Konuşmadan yazıya", qsTr("Türkçe dikte: ilk basış kaydı başlatır, ikinci basış bitirir; sonuç aynı penceredeki yazı alanına yapıştırılır"), ["dikte stt whisper mikrofon ses konusma yazdir transkripsiyon telefon ac"]],
                ["F11 · Ekrandan yazı kopyala", qsTr("Alan seç; Türkçe ve İngilizce yazıları okuyup panoya kopyala"), ["ocr tesseract resim fotograf ekran metin yazi kopyala telefon kapat"]],
                ["F12 · Yıldız", qsTr("Kısayol rehberini ve düzenleyicisini aç/kapat"), ["kisayol rehber yardim yildiz favorites shortcuts"]]
            ]
        },
        {
            id: "windows", keywords: "pencere windows",
            title: qsTr("Windows"), icon: "select_window", entries: [
                ["Super + Q", qsTr("Close active window"), ["close", "kapat", "pencere"]],
                ["Super + F", qsTr("Fullscreen"), ["fullscreen", "tam ekran", "tamekran", "ekran"]],
                ["Super + Alt + F", qsTr("Maximise with borders"), ["maximize", "maximise", "büyüt", "buyut", "kenarlık"]],
                ["Super + Alt + Space", qsTr("Toggle floating — switch the active window between tiled and free-floating mode"), ["floating", "float", "tiling", "tile", "serbest", "yüzen", "yuzen", "serbest mod", "pencere modu", "toggle", "mod", "sabit", "kaplama"]],
                ["Super + P", qsTr("Show floating window on all workspaces (toggle)"), ["pin", "sabitle", "pinle", "tum masaustleri", "floating"]],
                ["Super + Alt + P", qsTr("Shrink to bottom-right and pin across workspaces"), ["pip", "picture-in-picture", "resim içinde", "küçük pencere", "sag alt"]],
                ["Super + arrows", qsTr("Move focus by direction"), ["focus", "odak", "ok", "yön", "yon", "geçiş", "gecis"]],
                ["Super + Shift + arrows", qsTr("Move window by direction"), ["move", "taşı", "tasi", "ok", "yön", "pencere taşı"]],
                ["Super + Alt + arrows", qsTr("Resize: left/right changes width; up/down changes height"), ["resize", "boyutlandırma", "boyut", "ok tuşları", "serbest", "floating", "büyüt", "küçült", "kucult", "genislik", "yukseklik"]],
                ["Ctrl + Super + O", qsTr("Centre floating window"), ["center", "centre", "ortala", "merkez", "pencere"]],
                ["Ctrl + Super + Alt + O", qsTr("Resize floating window to 55×70% and centre"), ["resize", "center", "ortala", "boyut", "boyutlandır"]],
                ["Super + Z / Super + left drag", qsTr("Move window with pointer"), ["move", "drag", "taşı", "sürükle", "surukle", "fare"]],
                ["Super + X / Super + right drag", qsTr("Resize window with pointer"), ["resize", "drag", "boyutlandır", "sürükle", "surukle", "fare"]],
                ["Alt + Tab", qsTr("Next window in current workspace"), ["sonraki pencere gecis focus"]],
                ["Shift + Alt + Tab", qsTr("Previous window in current workspace"), ["onceki pencere gecis focus"]],
                ["Super + Tab", qsTr("Window overview across workspaces"), ["overview", "genel bakış", "expose", "pencere listesi"]]
            ]
        },
        {
            id: "workspaces", keywords: "workspace calisma alani masaustu",
            title: qsTr("Workspaces"), icon: "grid_view", entries: [
                ["Super + 0–9", qsTr("Open workspace 1–10"), ["masaustu calisma alani git 0 onuncu"]],
                ["Super + Alt + 0–9", qsTr("Move window to workspace 1–10"), ["pencere masaustu calisma alani tasi 0 onuncu"]],
                ["Ctrl + Super + 0–9", qsTr("Open workspace group 1–10"), ["masaustu calisma alani onlu grup git"]],
                ["Ctrl + Super + Alt + 0–9", qsTr("Move window to workspace group 1–10"), ["pencere masaustu onlu grup tasi"]],
                ["Ctrl + Super + ← / →", qsTr("Previous / next workspace"), ["onceki sonraki masaustu calisma alani gecis"]],
                ["Super + Page Up / Down", qsTr("Previous / next workspace"), ["onceki sonraki masaustu calisma alani gecis"]],
                ["Super + wheel", qsTr("Previous / next workspace"), ["onceki sonraki masaustu calisma alani gecis"]],
                ["Ctrl + Super + wheel", qsTr("Previous / next workspace group"), ["onceki sonraki onlu grup masaustu"]],
                ["Super + Alt + Page Up / Down", qsTr("Move window to adjacent workspace"), ["pencere komsu onceki sonraki masaustu tasi"]],
                ["Super + Alt + wheel", qsTr("Move window to adjacent workspace"), ["pencere komsu onceki sonraki masaustu tasi"]],
                ["Ctrl + Super + Shift + ← / →", qsTr("Move window to adjacent workspace"), ["pencere komsu onceki sonraki masaustu tasi"]],
                ["Ctrl + Super + Shift + ↑", qsTr("Move window to scratch workspace"), ["pencere gecici gizle sakla scratch tasi"]],
                ["Ctrl + Super + Shift + ↓", qsTr("Move window back to current workspace"), ["pencere gecici alandan geri getir"]],
                ["Super + Alt + S", qsTr("Move window to scratch workspace"), ["pencere gecici gizle sakla scratch tasi"]]
            ]
        },
        {
            id: "groups", keywords: "sekme grup tab pencere gruplama",
            title: qsTr("Window groups"), icon: "tab", entries: [
                ["Ctrl + Alt + Tab", qsTr("Next group tab"), ["sonraki grup sekme"]],
                ["Ctrl + Shift + Alt + Tab", qsTr("Previous group tab"), ["onceki grup sekme"]],
                ["Super + B", qsTr("Create or dissolve window group"), ["pencere grup sekme olustur dagit birlestir"]],
                ["Super + U", qsTr("Remove window from group"), ["pencere gruptan ayir cikar"]],
                ["Super + Shift + B", qsTr("Lock active group"), ["aktif grup kilitle kilit ac"]]
            ]
        },
        {
            id: "special", keywords: "ozel gizli alan",
            title: qsTr("Special workspaces"), icon: "view_carousel", entries: [
                ["Super + S", qsTr("Scratch workspace"), ["gecici alan gizle sakla"]],
                ["Super + D", qsTr("Communication — Equibop / Discord"), ["iletisim sohbet"]],
                ["Super + M", qsTr("Music — Spotify"), ["muzik"]],
                ["Super + G", qsTr("Games — Steam"), ["oyun"]],
                ["Super + R", qsTr("Todo workspace"), ["gorev yapilacak isler todoist"]],
                ["Ctrl + Shift + Esc", qsTr("System monitor workspace"), ["sistem monitor islemci bellek btop"]]
            ]
        },
        {
            id: "utilities", keywords: "arac yardimci utilities",
            title: qsTr("Capture & utilities"), icon: "construction", entries: [
                ["Super + Shift + S", qsTr("Fotoğraf / video: alan, pencere veya uygulama; kayıt kontrolleri"), ["ekran goruntusu yakalama ekran kaydi video fotograf screenshot kaydet"]],
                ["Capture: Super + Alt + arrows", qsTr("Resize selection while the capture tool is open"), ["yakalama secim alan boyut ekran goruntusu video"]],
                ["Capture: Super + Shift + arrows", qsTr("Move selection while the capture tool is open"), ["yakalama secim alan tasi ekran goruntusu video"]],
                ["Super + Shift + C", qsTr("Colour picker and copy"), ["renk secici kopyala"]],
                ["Super + V", qsTr("Clipboard history"), ["pano gecmisi kopyala yapistir"]],
                ["Super + Alt + V", qsTr("Clipboard history with delete mode"), ["pano gecmisi kayit sil temizle"]],
                ["Ctrl + Shift + Alt + V", qsTr("Type most recent clipboard entry"), ["pano son kayit yazarak yapistir"]],
                ["Super + .", qsTr("Emoji and glyph picker"), ["emoji simge secici"]],
                ["Super + Shift + L", qsTr("Suspend then hibernate"), ["uyku hazirda beklet"]],
                ["Super + Alt + F12", qsTr("Send test notification"), ["deneme test bildirimi"]]
            ]
        },
        {
            id: "media", keywords: "medya media",
            title: qsTr("Media, sound & brightness"), icon: "tune", entries: [
                ["XF86 Audio Play / Pause", qsTr("Play or pause media"), ["muzik medya oynat duraklat"]],
                ["Ctrl + Super + Space", qsTr("Play or pause media"), ["muzik medya oynat duraklat"]],
                ["XF86 Audio Next / Ctrl + Super + Page Down", qsTr("Next track"), ["muzik sonraki parca sarki"]],
                ["XF86 Audio Previous / Ctrl + Super + Page Up", qsTr("Previous track"), ["muzik onceki parca sarki"]],
                ["XF86 Audio Stop", qsTr("Stop media"), ["muzik medya durdur"]],
                ["XF86 Volume Up / Down", qsTr("Change output volume"), ["ses ac kis seviye"]],
                ["XF86 Audio Mute / Super + Shift + M", qsTr("Mute output"), ["ses kapat sustur sessiz"]],
                ["XF86 Mic Mute", qsTr("Mute microphone"), ["mikrofon kapat sustur"]],
                ["XF86 Brightness Up / Down", qsTr("Change display brightness"), ["ekran parlaklik arttir azalt"]]
            ]
        },
        {
            id: "gestures", keywords: "dokunmatik touchpad parmak hareket kaydirma jest",
            title: qsTr("Touchpad gestures"), icon: "gesture", entries: [
                ["4-finger horizontal swipe", qsTr("Switch workspace"), ["masaustu calisma alani degistir"]],
                ["3-finger swipe up", qsTr("Open scratch workspace"), ["gecici alan ac"]],
                ["3-finger swipe down", qsTr("Toggle scratch workspace"), ["gecici alan ac kapat"]],
                ["4-finger swipe down", qsTr("Suspend then hibernate"), ["uyku hazirda beklet"]]
            ]
        }
    ];
}
