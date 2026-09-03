<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop uygulama simgesi — dört çizgili yıldız işareti">

# Hop

**macOS menü çubuğu için minik bir yol arkadaşı: zamanlayıcı, zaman takibi,
yapılacaklar, uyku engelleme, sistem monitörü, pano geçmişi, dosya
dönüştürücü, pencere yöneticisi ve hafif bir torrent istemcisi.
İhtiyacınız olanları açar, simgedeki en fazla dört sekmeye dağıtırsınız.
Tek tık — ihtiyacınız olan her şey elinizin altında.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · **Türkçe** · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://hop.tools/screens/en/overview.webp" width="360" alt="Hop paneli — nokta matrisli ekran, hazır ayarlar ve çalışma-mola döngüleriyle menü çubuğu zamanlayıcısı">

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

Hop bir Apple Developer ID ile imzalanmış ve Apple tarafından
noterlenmiştir, bu yüzden macOS onu diğer uygulamalar gibi açar. Kaynak kodu
herkese açıktır ve yerleşik güncellemeler Ed25519 ile doğrulanır. macOS 14
veya üzeri gerekir.

## Özellikler

### Alanlar

Simge en fazla dört sekme tutar ve her modülü istediğiniz sekmeye
sürüklersiniz: zamanlayıcı birinde, monitör diğerinde, seyrek açtıklarınız
bir kenarda. Modülün yanındaki göz, onu taşımadan ve silmeden gizler.

### Zamanlayıcı ve döngüler

Tek hareketle kurduğunuz nokta matrisli geri sayım: rakamları sürükleyin,
süreyi mikrodalgadaki gibi yazın ya da bir hazır ayar seçin.
Çalışma-mola döngüleri (25/5 Pomodoro, 52/17, 90/15 — ya da kendi
döngünüz), kronometre, başka bir zamanlayıcı denerken çalışan sayacı
saklayan bir cep ve medyanızı da duraklatabilen bitiş uyarısı. Geri sayım
bitince tek bir ses çalar ve sıfırlayana kadar rakamlar yanıp söner.

<div align="center">
<img src="https://hop.tools/screens/en/timer.webp" width="420" alt="Hop — Zamanlayıcı ve döngüler">
</div>

### Zaman takibi ve görevler

Görevler projelerde toplanabilir, her biri kendi toplamını taşır ve listenin
üstündeki anahtar bugünü, haftayı ya da tümünü gösterir. Süregelen bir görev,
içinde bulunduğun turu sıfırdan sayar; yanındaki ✓ turu kapatır ve satıra
dönemin toplamı geri gelir. Bir görevi aç, topladığı bütün süre parçaları
orada: süreyi ya da anı değiştir, kimsenin başlatmadığı bir oturumu ekle ya da
birini sil; elle yapılan düzeltmeler de aynı listede, böylece satırlar üstteki
toplamı verir. Biri fazla uzun sürerse, sekiz saatin sonunda bir bant
hatırlatır. Yanında ayrı bir yapılacaklar listesi durur; biten işler dibe
iner.

Bir göreve tıklayın, satır açılsın: ilk satırda tam metin, altında açıklama,
favoriler için bir yıldız. Bir yapılacak öğesi hatırlatma da taşıyabilir — gün,
saat ve tekrarlanacak günler — ve zamanı gelince Hop haber verir: «ertele» ve
«tamam» düğmeli bir bildirim, ses, menü çubuğunda bir işaret; her biri ayrı
açılır.

**Görevleri kendi yapay zekâ ajanınız da ekleyebilir.** Liste sıradan bir JSON
dosyasıdır ve Hop, çalışırken değişiklikleri alır. Hop ayrıca bir dosyadaki
komutları yürütür ve `hop://` bağlantılarını anlar: aynı ajan ya da o
bağlantılardan biriyle kurulmuş bir kısayol, bir sayaç başlatabilir, hatırlatmalı
bir görev ekleyebilir veya neyin çalıştığını okuyabilir. Bkz.
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://hop.tools/screens/en/tracker.webp" width="420" alt="Hop — Zaman takibi ve görevler">
</div>

### Uyku engelleme

Mac'i 15 dakika, 8 saat ya da süresiz uyanık tutun — tek tık, parola
yok. İsterseniz ekranı açık tutun ya da kapak kapalıyken çalışmaya devam
edin (indirmeler, uzun derlemeler ve harici ekranlar için birebir).

<div align="center">
<img src="https://hop.tools/screens/en/awake.webp" width="420" alt="Hop — Uyku engelleme">
</div>

### Sistem monitörü

CPU ve GPU yükü ile sıcaklığı, bellek ve swap, ağ, disk, pil sağlığı ve güç
tüketimi — sparkline grafikleriyle canlı değerler, kendi belirlediğiniz renk
eşikleri, °C/°F ve çalışma süresi satırı. Veriler doğrudan macOS'ten gelir ve
yalnızca sekme açıkken güncellenir. Bellek satırı, yalnızca macOS sıkışıklık
bildirdiğinde değil, belleğin çoğu diske indiğinde de uyarır.

<div align="center">
<img src="https://hop.tools/screens/en/system.webp" width="420" alt="Hop — Sistem monitörü">
</div>

### Pano geçmişi

Kopyaladığınız son 100 (300'e kadar) öğe — metin, görseller ve dosyalar —
tek tıkla yeniden kopyalayın ya da doğrudan önceki uygulamaya yapıştırın.
Kopyalanan dosyalar adıyla saklanır (birden fazlası «ad +N» olarak görünür)
ve yapıştırınca dosyanın kendisi geri gelir. Parolalar ve diğer gizli
girişler asla saklanmaz.

<div align="center">
<img src="https://hop.tools/screens/en/clipboard.webp" width="420" alt="Hop — Pano geçmişi">
</div>

### Dosya dönüştürücü

Panele bir grup görsel, PDF, video ya da ses bırakın: çıktı olarak JPEG, PNG,
HEIC, AVIF ve WebP; PDF sıkıştırma; dönüştürmeden önce canlı ve dürüst boyut
tahminiyle HEVC video küçültme. Her şey yerel olarak işlenir. Video
dönüştürülürken yeniden çerçevelenebilir — 9:16, 4:5, kare ya da 16:9;
kırpılarak, bantla ya da kendi bulanık kopyasının üzerinde — ve sıkıştırmanın
kendi seviyesi var, böylece önceden söylenen boyut çıkan boyut oluyor.

Tek düğme klibi gideceği yere göre ayarlar — reels, feed, tiktok, shorts ya da
youtube — kareyi, çözünürlüğü ve sıkıştırmayı platformun kendi önerisine göre
yazar ve ortaya çıkan bit hızını sürgünün yanında gösterir. MKV ve WebM önce
MP4'e yeniden paketlenir (macOS ikisini de açmaz); bunu bir kez inen küçük bir
yardımcı yapar. Pages, Numbers ve Keynote belgelerini toplu olarak
uygulamaların kendisi dışa aktarır: PDF ya da docx, xlsx ve pptx.

<div align="center">
<img src="https://hop.tools/screens/en/converter.webp" width="480" alt="Hop — Dosya dönüştürücü">
</div>

### Pencere yöneticisi

Pencereleri yarımlara, çeyreklere, üçte birlere ve ortaya yerleştirin —
bölge simgesine tek tık ya da ⌃⌥ kısayolu yeter; ek bir uygulamaya gerek
yok.

<div align="center">
<img src="https://hop.tools/screens/en/windows.webp" width="420" alt="Hop — Pencere yöneticisi">
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
<img src="https://hop.tools/screens/en/torrents.webp" width="420" alt="Hop torrentleri — menü çubuğu panelinde hafif BitTorrent istemcisi">
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
<img src="https://hop.tools/screens/en/archives.webp" width="480" alt="Hop — Dosya arşivleri">
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
<img src="https://hop.tools/screens/en/colors.webp" width="420" alt="Hop — Renk damlalığı">
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
<img src="https://hop.tools/screens/en/recognition.webp" width="480" alt="Hop — Metin tanıma">
</div>

### Klavye kilidi

1, 5 ya da 15 dakikaya — veya ∞'a — dokunun, tüm klavye yanıt vermeyi bıraksın;
Mac'i kapatmadan, kapağı indirmeden silebilirsiniz. Tam ekran bir örtü ne
olduğunu anlatır, menü çubuğundaki simge klavyeye dönüşür. Dört çıkış yolu var:
örtüdeki düğme, paneldeki düğme, panelin açılması ya da esc + shift'i beş saniye basılı
tutmak. Güç tuşuna kısa basış da yutulur; basılı tutmak Mac'i yine de
kapatır, çünkü onu donanım yapar.

<div align="center">
<img src="https://hop.tools/screens/en/keyboard.webp" width="480" alt="Hop — Klavye kilidi">
</div>

### Hız testi

Tek dokunuş, bağlantıyı macOS'un kendi networkQuality'siyle Apple sunucularına karşı ölçer — indirme, yükleme ve yanıt süresi; son sonuç satırda kalır.

<div align="center">
<img src="https://hop.tools/screens/en/speed.webp" width="420" alt="Hop — Hız testi">
</div>

### Menü çubuğu simgesi

Simgede küçük işaretler durur: akan süre, uyku engeli, çalmış bir anımsatıcı, bir VPN
açıkken nokta (hiçbir şey geçmiyorsa turuncu) ve torrentler akarken oklar — renkli ya
da tek renk, her biri kapatılabilir. Hop'un kendi pencereleri açıkken Dock'ta görünür,
böylece bir tık paneli açmadan pencereyi geri getirir; son pencereyle birlikte simge
de gider.

### Temalar, kısayollar ve güvenli mod

Film grenli dokuya sahip koyu ve açık temalar, genel kısayollar, oturum açılışında başlatma ve uygulamayı çökme döngüsünden çıkaran bir güvenli mod — hepsi tek bir ayarlar penceresinde.

<div align="center">
<img src="https://hop.tools/screens/en/settings.webp" width="480" alt="Hop — Ayarlar">
</div>

### VPN

Mac'inizin bildiği bütün VPN'ler, hangi firmadan olursa olsun, her biri kendi
anahtarıyla. Hop listeyi doğrudan sistem ayarlarından okur: dün kurduğunuz istemci
kendiliğinden görünür, kaldırdığınız kaybolur. Burada eklenecek bir şey yok,
belirli bir firma için destek beklemek de gerekmiyor.

Hiçbir şey açmadan bağlanın ve kesin. Bir tünel ayaktayken menü çubuğu simgesinin
köşesinde küçük bir nokta yanar, diğer göstergelerin yanında: bir şeyler geçtiği
sürece yeşil, tünel açık olduğu hâlde geri hiçbir şey gelmiyorsa turuncu. Sessizce
ölmüş bir bağlantı böylece sağlam görünmez, hangi satır olduğunu da panel gösterir.
Ada tıklayınca o VPN'in kendi penceresi açılır; kapattığınızda Hop uygulamayı kapatır.
Bağlantı kalır: tüneli uygulama değil sistem tutar.

Satırda istemcinin kendi bildirdiği şey görünür: adı ve parantez içinde
yapılandırmanın eklediği, genelde ülke. Hop ülkeyi sunucu adresinden tahmin etmez:
adres kaydı aralığın nerede kayıtlı olduğunu söyler, makinenin nerede durduğunu
değil.

Nokta ayarlardan kapatılabilir; modül de anahtarları da onsuz çalışmaya devam eder.

<div align="center">
<img src="https://hop.tools/screens/en/vpn.webp" width="420" alt="Hop — VPN anahtarları">
</div>

### Uygulamalar

Gün boyu açtığınız programlar bir ızgarada, Uygulamalar klasörüne uğramadan tek
tıkla. + düğmesine basıp seçin ya da Finder'dan sürükleyin; bir satıra dokuz sığar, en çok sekiz satır.

Bir simgeyi sürükleyerek yerini değiştirin: sarı çizgi hangi iki simgenin
arasına ineceğini gösterir, diğerleri ana ekrandaki gibi yer açar. Düzenleme
düğmesi sallanmayı başlatır, her simgede bir ✕ belirir ve ızgaraya kendi adı
verilebilir; uygulamalarınızı zaten tanıyorsanız simgelerin altındaki adlar da
orada kapatılır. İstediğiniz kadar ızgara tutabilirsiniz — iş bir alanda, gerisi
başka bir alanda — her birinin kendi uygulamaları olur.

Izgaralar modülleri düzenlediğiniz yerde doğar ve silinir: ayarlarda ya da modül
tablosunun kendisinde, oradaki etiketin ✕ işareti bir ızgarayı temelli siler.
Yeni bir ızgara boş başlar ve siz doldurana kadar bunu söyler.

<div align="center">
<img src="https://hop.tools/screens/en/apps.webp" width="420" alt="Hop — Uygulama ızgarası">
</div>

### Uygulama kaldırma

Bir uygulamayı satırın üstüne bırakın ya da kurulu olan her şeyin listesinden seçin: otuza yakın yerde bıraktığı her şeyle birlikte gider — application support, önbellekler, tercihler, container'lar, launch agent'lar, eklentiler, kurulum makbuzları ve gerisi. Listedeki her uygulama ne kadar yer kapladığını gösterir, paket ve verisi ayrı ayrı. Çöp kutusundaki bir uygulama da tanınır: kimlik oradaki paketten okunur ya da onu adıyla anan artıklardan çıkarılır.

Hiçbir şey silinmez. Her şey çöp kutusuna gider, yani bir hata bir dosyaya değil bir geri almaya mal olur; macOS'un vermediği şeyler sessizce atlanmaz, nedeniyle birlikte söylenir.

<div align="center">
<img src="https://hop.tools/screens/en/uninstall.webp" width="480" alt="Hop — Bir uygulamayı bıraktığı her şeyle kaldırma">
</div>

Aynı modül hiçbir şeyi kaldırmadan toparlar da: önbellek tutan her uygulama, büyükler önce; İndirilenler'de, Masaüstü'nde ve Belgeler'de kalan kurulum dosyaları; yıllar önce silinmiş uygulamaların verileri; ve boyutuyla birlikte çöp kutusu. Tek kutucuk koca bir bölümü alır. Bilerek dokunmadığı şeyler de listelenir — önbellekle verinin aynı klasörde durduğu bir container, bir mesajlaşma uygulamasının yirmi gigabaytı gibi: hangi yarısının atılabileceğini yalnızca o uygulama bilir.

<div align="center">
<img src="https://hop.tools/screens/en/clean.webp" width="480" alt="Hop — Önbellek, kurulum dosyaları, artıklar ve çöp kutusu">
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
uygulamanın ayarlar penceresi hepsini güncel durumlarıyla listeler:

- **ağ — hop.tools** — güncelleme aramak ve indirmek, ayrıca iki isteğe
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
Analiz yok, telemetri yok, hesap yok, çökme raporu yok: hop.tools'a
yalnızca daha yeni bir sürüm olup olmadığını sormak için bağlanılır — ve kabul
edersen onu ya da iki isteğe bağlı yardımcıdan birini indirmek için. Geri kalan
her şey bu Mac'te kalır: pano geçmişi, tutulan süre, yapılacaklar listesi,
tanınan metin ve alınan renkler.

Yukarıdaki her izin, bir özellik çalışsın diye var — başka hiçbir şey için değil.
Buna inanmak zorunda değilsin: Hop açık kaynak, toplayacak kod zaten yok — bu
deposunda oku. Uygulamanın ayarlar penceresinde «uygulama izinleri» bölümü var:
aynı liste ve her iznin güncel durumu.

1.10.0'a güncellemek tüm izinleri bir kez siler ve yeniden ister. İzin bir kod
imzasına bağlıdır ve Hop'unki Apple imzaladığında değişti: eski imzaya verilen
izinler listede duruyordu ama artık çalışmıyordu. 1.10.0'dan itibaren
güncellemeyi atlatırlar.

Web sitesi: [hop.tools](https://hop.tools)

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
