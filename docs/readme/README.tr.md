<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop uygulama simgesi — dört çizgili yıldız işareti">

# Hop

**macOS menü çubuğu için minik bir yol arkadaşı: zamanlayıcı, zaman
takibi, yapılacaklar, uyku engelleme, sistem monitörü, pano geçmişi,
dosya dönüştürücü, pencere yöneticisi ve hafif bir torrent istemcisi —
simgedeki en fazla dört sekmeye dağılmış. Tek tık — ihtiyacınız olan
her şey elinizin altında.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · **Türkçe** · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/overview.png" width="360" alt="Hop paneli — nokta matrisli ekran, hazır ayarlar ve çalışma-mola döngüleriyle menü çubuğu zamanlayıcısı">

</div>

Hop, Mac'inizin menü çubuğunda yaşar ve bir avuç küçük aracın yerini
alır: Pomodoro tarzı bir zamanlayıcı, yapılacaklar listeli bir zaman
takibi, caffeinate benzeri bir uyku engelleyici, sistem monitörü, pano
yöneticisi, sürükle-bırak dosya dönüştürücü, pencere yerleştirici ve
hafif bir torrent istemcisi — tek bir hafif, yerel uygulama; kullandığınız
modüller simgedeki en fazla dört sekmeye dağılmış.

## İndir

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — açın ve `Hop.app`'i Uygulamalar klasörüne sürükleyin (önerilen)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — aynı uygulamanın düz arşiv hâli (yerleşik güncelleyici bunu kullanır); bkz. [en son sürüm](https://github.com/antonyshakirov/hop/releases/latest)
- Hızlı yansı: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

macOS 15 veya daha yenisinde ilk açılış: Hop'u bir kez açmayı deneyin,
ardından **Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç** yoluna
gidip **Aç** seçeneğini onaylayın. Yazarın Apple Developer Program
üyeliğine erişimi olmadığı için Hop noter onaylı değildir. Kaynak kodu
herkese açıktır ve yerleşik güncellemeler Ed25519 ile doğrulanır. macOS 14
veya daha yenisi gerekir.

## Özellikler

### Alanlar

Simge en fazla dört sekme tutar ve her modülü istediğiniz sekmeye
sürüklersiniz: zamanlayıcı birinde, monitör diğerinde, seyrek açtıklarınız
bir kenarda. Bir «pasif» raf, kenara ayırdıklarınızı silmeden saklar.

### Zamanlayıcı ve döngüler

Tek hareketle kurduğunuz nokta matrisli geri sayım: rakamları sürükleyin,
süreyi mikrodalgadaki gibi yazın ya da bir hazır ayar seçin.
Çalışma-mola döngüleri (25/5 Pomodoro, 52/17, 90/15 — ya da kendi
döngünüz), kronometre, başka bir zamanlayıcı denerken çalışan sayacı
saklayan bir cep ve medyanızı da duraklatabilen bitiş uyarısı. Geri sayım
bitince tek bir ses çalar ve sıfırlayana kadar rakamlar yanıp söner.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/timer.png" width="420" alt="Hop — Zamanlayıcı ve döngüler">
</div>

### Zaman takibi ve görevler

Düz bir görev listesinde zamanı tutun: her satır bugünkü süreyi ve toplam
birikimi gösterir, bugünkü değeri elle düzeltebilirsiniz. Biri fazla uzun
sürerse, sekiz saatin sonunda bir bant hatırlatır. Yanında ayrı bir
yapılacaklar listesi durur; biten işler dibe iner.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/tracker.png" width="420" alt="Hop — Zaman takibi ve görevler">
</div>

### Uyku engelleme

Mac'i 15 dakika, 8 saat ya da süresiz uyanık tutun — tek tık, parola
yok. İsterseniz ekranı açık tutun ya da kapak kapalıyken çalışmaya devam
edin (indirmeler, uzun derlemeler ve harici ekranlar için birebir).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/awake.png" width="420" alt="Hop — Uyku engelleme">
</div>

### Sistem monitörü

CPU ve GPU yükü ile sıcaklığı, bellek ve swap, ağ, disk, pil sağlığı ve güç
tüketimi — sparkline grafikleriyle canlı değerler, kendi belirlediğiniz renk
eşikleri, °C/°F ve çalışma süresi satırı. Veriler doğrudan macOS'ten gelir ve
yalnızca sekme açıkken güncellenir. Bellek satırı, yalnızca macOS sıkışıklık
bildirdiğinde değil, belleğin çoğu diske indiğinde de uyarır.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="420" alt="Hop — Sistem monitörü">
</div>

### Pano geçmişi

Kopyaladığınız son 100 (300'e kadar) öğe — metin, görseller ve dosyalar —
tek tıkla yeniden kopyalayın ya da doğrudan önceki uygulamaya yapıştırın.
Kopyalanan dosyalar adıyla saklanır (birden fazlası «ad +N» olarak görünür)
ve yapıştırınca dosyanın kendisi geri gelir. Parolalar ve diğer gizli
girişler asla saklanmaz.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clipboard.png" width="420" alt="Hop — Pano geçmişi">
</div>

### Dosya dönüştürücü

Panele bir grup görsel, PDF, video ya da ses bırakın: çıktı olarak JPEG,
PNG, HEIC, AVIF ve WebP; PDF sıkıştırma; dönüştürmeden önce canlı ve
dürüst boyut tahminiyle HEVC video küçültme. Her şey yerel olarak
işlenir.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="480" alt="Hop — Dosya dönüştürücü">
</div>

### Pencere yöneticisi

Pencereleri yarımlara, çeyreklere, üçte birlere ve ortaya yerleştirin —
bölge simgesine tek tık ya da ⌃⌥ kısayolu yeter; ek bir uygulamaya gerek
yok.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/windows.png" width="420" alt="Hop — Pencere yöneticisi">
</div>

### Torrentler

Aynı panelde hafif bir BitTorrent istemcisi: bir .torrent dosyası
bırakın ya da bir magnet bağlantısı yapıştırın, tam olarak hangi
dosyaların indirileceğini seçin — indirmeden önce, hatta indirme
sırasında bile — duraklatın, sürdürün ve seed yapın; isterseniz 1.0
oranına ulaşınca otomatik dursun. Modül varsayılan olarak kapalıdır;
etkinleştirdiğinizde açık kaynaklı motor, Hop ile yalnızca yerel bir
port üzerinden konuşan küçük ve ayrı bir indirme (~26 MB, imzası
doğrulanmış) olarak alınır. Hop ayrıca .torrent dosyaları ve magnet
bağlantıları için varsayılan uygulama olabilir.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Hop torrentleri — menü çubuğu panelinde hafif BitTorrent istemcisi">
</div>

### Dosya arşivleri

Modülün satırı bir pencere açar ve bırakma işi o pencerede olur — ⌘V de çalışır,
birden çok dosyayla birlikte. Eklediklerin bir listede bekler, sen düğmeye
basınca çalışır: arşivler açılır, kalan her şey tek bir arşive girer. Sonuç
varsayılan olarak masaüstüne, istersen orijinalin yanına ya da seçtiğin bir
klasöre iner. zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz ve gz desteklenir; rar
ve 7z için ilk karşılaşmada imzası doğrulanan küçük bir yardımcı (~6 MB) iner.
Hop rar açar ama asla oluşturmaz — format tescillidir. Ayarlardaki «arşivler için varsayılan Hop»,
bir Apple uygulaması ilgilenmiyorsa yalnızca rar'ı sunar ve rar'ı üçüncü taraf
uygulamalardan geri alabilir; zip, 7z ve yerel biçimler Arşiv Yardımcısı'nda kalır.
Modül gizliyken de çalışır ve kart gerçek durumu gösterir. Finder'da bir arşive çift tıklamak onu dosyanın hemen yanında açar, kendi küçük ilerleme penceresinde, ve başarısız bir iş arkasında gizli hiçbir şey bırakmaz. Hop'un açtığı dosyalar üzerinde biçimi yazan kendi simgesini taşır, böylece bir klasör bir bakışta okunur.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/archives.png" width="480" alt="Hop — Dosya arşivleri">
</div>

### Belgeler

Dönüştürücü belgeleri öğrendi: markdown → PDF dizgisini Hop'un kendisi yapar,
Word dosyaları (.docx, .doc, .rtf) → PDF ya da markdown, ve bir PDF'in metni
markdown olarak çıkar — taranmış sayfayı Apple'ın Vision'ı okur. Hepsi yerel ve
çevrimdışı; paketlenmiş ofis takımı yok, indirilecek bir şey yok.

### Renk damlalığı

Sistem büyüteciyle ekrandaki her rengi alın: renk bir listede kalır, her satır
hex, rgb ve hsl'i kendi sütununda taşır ve tıkladığınız gösterim kopyalanır.
Sıra imlecin altında hiç değişmez, kaç renk saklanacağı ve kaç satır
görüneceği ayarlardadır, ekran kaydı izni de gerekmez: büyüteç tek bir renk
döndürür.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/colors.png" width="420" alt="Hop — Renk damlalığı">
</div>

### Metin tanıma

Ekranda bir alan seçin ya da pencereye bir görsel bırakın, ⌘V ile yapıştırın:
içindeki metin ve QR kodlar okunabilen, düzeltilebilen, kopyalanabilen bir
pencerede çıkar ve aynı anda pano geçmişine girer. Satır sonları korunur, tablo
okunur kalır. Tanıma Apple'ın Vision'ıdır, tamamen bu Mac'te çalışır.

Sonuçta bir web adresi varsa «bağlantıyı aç» düğmesi çıkar: faturadaki QR
kodun bağlantısı telefona uzanmadan doğrudan tarayıcıda açılır. Yalnızca web
adresleri: taranan kod dışarıdan gelen bir girdidir, bu yüzden telefon
numarası, Wi-Fi parolası ya da kartvizit düz metin olarak kalır.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/recognition.png" width="480" alt="Hop — Metin tanıma">
</div>

### Klavye kilidi

1, 5 ya da 15 dakikaya — veya ∞'a — dokunun, tüm klavye yanıt vermeyi bıraksın;
Mac'i kapatmadan, kapağı indirmeden silebilirsiniz. Tam ekran bir örtü ne
olduğunu anlatır, menü çubuğundaki simge klavyeye dönüşür. Dört çıkış yolu var:
örtüdeki düğme, paneldeki düğme, panelin açılması ya da esc + shift'i beş saniye basılı
tutmak. Güç tuşuna kısa basış da yutulur; basılı tutmak Mac'i yine de
kapatır, çünkü onu donanım yapar.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/keyboard.png" width="480" alt="Hop — Klavye kilidi">
</div>

### Ve gerisi

Menü çubuğu simgesindeki küçük durum göstergeleri — zaman, uyku engelleme,
uyarılar ve torrent etkinliği, renkli ya da tek renk —, yerleşik hız testi
(Apple'ın networkQuality aracı), film greni dokulu koyu ve açık temalar, genel
kısayollar, oturum açıldığında başlatma ve uygulamayı çökme döngüsünden
kurtaran güvenli mod. Hop'un kendi pencereleri — dönüştürücü, arşivler, metin
tanıma, ayarlar — açıkken dock'ta görünür; simgeye tıklamak paneli açmadan
pencereyi geri getirir ve son pencereyle birlikte simge de gider.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Hop sistem monitörü — CPU, GPU, bellek, ağ, disk ve pil grafikleri">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Hop dosya dönüştürücü — toplu görsel, PDF, video ve ses dönüştürme">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Hop ayarları — temalar, modüller, kısayollar, 22 dil">
</div>

## 22 dil

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — uygulama kurulumdan itibaren sistem
dilinize uyar.

## Projeye destek olun

Hop ücretsiz ve öyle kalacak. Menü çubuğunda bir yer hak ettiyse, gönüllü bir
katkı yeni özelliklerin çıkmasına ve mevcut olanların cilalanmasına yardım eder —
satın aldığı tek şey zaman.

**[→ Hop'a destek ol](https://web.tribute.tg/d/Nvk)**

## Gizlilik — ve izinleri neden gönül rahatlığıyla verebilirsin

**Hop hiçbir şey toplamaz. Ne şimdi ne sonra.** Kendi sunucusu yok, analitiği
yok, telemetrisi yok, hesabı yok, çökme raporu yok. Aşağıdaki her izni macOS
yalnızca ona ihtiyaç duyan özelliği gerçekten kullandığında sorar ve izin tam da
o özellik çalışsın diye vardır — yan yolda hiçbir şey toplanmaz. Buna inanmak
zorunda değilsin: uygulama açık kaynak, toplayacak kod zaten yok. Bu depoda bir
izleme SDK'sı ya da analitik çağrısı ara — bulamayacaksın.

Her şey yerel çalışır: sunucu yok, analitik yok, hesap yok. Uygulama
ağa yalnızca güncellemeleri denetlemek için, yerleşik hız testini
çalıştırdığınızda ve — torrent modülünü etkinleştirirseniz — motoru
bir kez indirmek ve torrent trafiğinin kendisini taşımak için çıkar.
Güncelleme denetimi yalnızca kullandığınız sürümü gönderir; sizi ya da
Mac'inizi tanımlayan hiçbir şey göndermez. Güncellemeler ve torrent motoru
imzalı arşivler olarak gelir ve kurulmadan önce Ed25519 imzasıyla doğrulanır.

## İzinler

Hop bir izni ancak onu gerektiren özelliği gerçekten kullandığında ister;
uygulamanın bilgi penceresi hepsini güncel durumlarıyla listeler:

- **ağ — antonshakirov.com** — güncelleme aramak ve indirmek, ayrıca iki isteğe
  bağlı yardımcı (torrent motoru ve 7-Zip arşivleyici)
- **ağ — torrentler, hız testi** — torrent modülü açıkken diğer eşlerle trafik;
  hız testi macOS'un networkQuality aracıyla Apple sunucularına yapılır
- **erişilebilirlik** — alttaki uygulamaya yapıştırmak, pencere yöneticisi ve
  klavye kilidi
- **ekran kaydı** — yalnızca metin tanıma modülü ve yalnızca bir alan seçerken;
  renk damlalığının buna ihtiyacı yok
- **bildirimler** — zamanlayıcı uyarısı ve tamamlanan torrent
- **yönetici parolası** — bir kez, kapak kapalı modu için (pmset yalnızca root)
- **girişte aç** — sen açana kadar kapalı

Açılışta hiçbir şey istenmez ve açmadığın bir modül için hiçbir şey sorulmaz.
Analiz yok, telemetri yok, hesap yok, çökme raporu yok: antonshakirov.com'a
yalnızca daha yeni bir sürüm olup olmadığını sormak için bağlanılır — ve kabul
edersen onu ya da iki isteğe bağlı yardımcıdan birini indirmek için. Geri kalan
her şey bu Mac'te kalır: pano geçmişi, tutulan süre, yapılacaklar listesi,
tanınan metin ve alınan renkler.

Yukarıdaki her izin, bir özellik çalışsın diye var — başka hiçbir şey için değil.
Buna inanmak zorunda değilsin: Hop açık kaynak, toplayacak kod zaten yok — bu
deposunda oku. Uygulamanın bilgi penceresinde «uygulama izinleri» sekmesi var:
aynı liste ve her iznin güncel durumu.

Web sitesi: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Ücretsiz, peki neden

Hop tamamen ücretsiz: deneme yok, pro sürüm yok, uygulama içi satın alma yok.
Reklam yok, veri toplama yok, hesap yok — para kazanılacak da satılacak da bir
şey yok. Bu kişisel bir proje: Hop'u kendim için yaptım, her gün kullanıyorum
ve sadece paylaşıyorum. İşine yararsa, sen de başkasına ilet. Ve katkıda
bulunmak istersen, artık Hop'a destek olmanın bir yolu var — tamamen bir
hediye, karşılığında hiçbir şey beklemeden.

## Kaynaktan derleme

Swift Package Manager, macOS 14+, harici bağımlılık yok:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Geliştirme akışı, sürüm hattı ve davranış spesifikasyonu
[docs/development.md](../development.md) ve [docs/spec.md](../spec.md)
dosyalarında.

## Projeye destek olun

Üç yol, hepsi makbul:

- **[Bir katkıyla Hop'a destek ol](https://web.tribute.tg/d/Nvk)** — doğrudan yeni
  özelliklere ve düzeltmelere gider. Gönüllü, ödülsüz, ücretli hiçbir şey yok:
  her modül herkes için aynı.
- **[Depoya yıldız ver](https://github.com/antonyshakirov/hop/stargazers)** —
  başkaları onu yıldızlarla buluyor.
- **[Issue aç](https://github.com/antonyshakirov/hop/issues)** — bir hata bildirimi
  ya da bir fikir de en az o kadar değerli.

## Yazar ve lisans

[Anton Shakirov](https://www.antonshakirov.com/en) tarafından yapıldı.
[MIT lisansı](../../LICENSE) ile yayımlandı: özgürce kullanın ve
değiştirin, telif hakkı bildirimini koruyun — uygulamayı kendi
çalışmanız gibi sunmak lisans ihlalidir.
