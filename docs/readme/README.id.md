<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ikon aplikasi Hop — asterisk empat garis">

# Hop

**Pendamping mungil di menu bar macOS: timer, pelacak waktu, daftar tugas,
anti-tidur, monitor sistem, riwayat clipboard, konverter file, pengelola
jendela, dan klien torrent ringan. Kamu menyalakan yang kamu butuhkan dan
menyebarnya di hingga empat tab pada ikon. Sekali klik — semua yang kamu
butuhkan langsung ada.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

**Bahasa Indonesia** · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://hop.tools/screens/en/overview.webp" width="360" alt="Panel Hop — timer di menu bar dengan tampilan dot-matrix, preset, dan siklus kerja-istirahat">

</div>

Hop tinggal di menu bar Mac kamu dan menggantikan segenggam utilitas
kecil: timer ala Pomodoro, pelacak waktu dengan daftar tugas, pencegah
tidur ala caffeinate, monitor sistem, pengelola clipboard, konverter file
drag-and-drop, penata jendela, dan klien torrent ringan — satu aplikasi
native yang ringan, dengan modul yang kamu pakai tersebar di hingga empat
tab pada ikon.

## Unduh

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — buka lalu seret `Hop.app` ke Applications (disarankan)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — aplikasi yang sama dalam bentuk arsip biasa (dipakai oleh pembaru bawaan); lihat [rilis terbaru](https://github.com/antonyshakirov/hop/releases/latest)
- Mirror cepat: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Hop ditandatangani dengan Apple Developer ID dan dinotarisasi oleh Apple,
jadi macOS membukanya seperti aplikasi lain. Kode sumbernya terbuka, dan
pembaruan bawaan diverifikasi dengan Ed25519. Membutuhkan macOS 14 atau
lebih baru.

## Fitur

### Ruang

Ikon menampung hingga empat tab, dan kamu menyeret tiap modul ke tab yang
kamu mau: timer di satu, monitor di lainnya, yang jarang dibuka ke samping.
Rak «nonaktif» menyimpan apa yang kamu sisihkan tanpa menghapusnya.

### Timer & siklus

Hitung mundur dot-matrix yang kamu atur dengan satu gerakan: seret
angkanya, ketik waktunya seperti di microwave, atau pilih preset. Siklus
kerja-istirahat (Pomodoro 25/5, 52/17, 90/15 — atau buatanmu sendiri),
stopwatch, kantong simpanan yang menjaga timer tetap berjalan saat kamu
mencoba timer lain, dan notifikasi selesai yang juga bisa menjeda media.
Saat hitung mundur selesai, terdengar satu bunyi dan angkanya berkedip
sampai kamu mereset.

<div align="center">
<img src="https://hop.tools/screens/en/timer.webp" width="420" alt="Hop — Timer & siklus">
</div>

### Pelacak waktu & tugas

Tugas bisa dikelompokkan ke proyek, masing-masing membawa jumlahnya sendiri,
dan sakelar di atas daftar menampilkan hari ini, minggu ini, atau seluruhnya.
Tugas yang sedang berjalan menghitung sesi yang kamu jalani, dari nol; ✓ di
sampingnya menutup sesi itu dan baris kembali ke jumlah periode. Buka sebuah
tugas dan semua potongan waktunya ada di sana: ubah durasi atau waktunya,
tambahkan sesi yang tak sempat dicatat, atau hapus satu baris; koreksi manual
ada di daftar yang sama, jadi barisnya berjumlah sama dengan total di atasnya.
Kalau satu berjalan terlalu lama, sebuah spanduk mengingatkan setelah delapan
jam. Di sebelahnya ada daftar tugas terpisah, tempat yang selesai turun ke
bawah.

Klik sebuah tugas dan barisnya terbuka: teks lengkap di baris pertama,
deskripsi di bawahnya, bintang untuk favorit. Sebuah to-do juga bisa membawa
pengingat — hari, jam, dan hari-hari dalam seminggu untuk mengulanginya — dan Hop
memberi tahu saat waktunya: spanduk dengan «tunda» dan «selesai», suara, tanda di
bilah menu; masing-masing dinyalakan terpisah.

**Agen AI Anda juga bisa menambah tugas.** Daftarnya berupa berkas JSON biasa,
dan Hop membaca perubahannya saat berjalan. Hop juga menjalankan perintah dari
sebuah berkas dan memahami tautan `hop://`: agen yang sama, atau sebuah Pintasan
yang dibuat dari tautan itu, bisa memulai pengatur waktu, menambah tugas
berpengingat, atau membaca apa yang sedang berjalan. Lihat
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://hop.tools/screens/en/tracker.webp" width="420" alt="Hop — Pelacak waktu & tugas">
</div>

### Anti-tidur

Jaga Mac tetap terjaga selama 15 menit, 8 jam, atau selamanya — sekali
klik, tanpa kata sandi. Opsional: biarkan layar tetap menyala, atau terus
bekerja dengan penutup tertutup (praktis untuk unduhan, build panjang, dan
layar eksternal).

<div align="center">
<img src="https://hop.tools/screens/en/awake.webp" width="420" alt="Hop — Anti-tidur">
</div>

### Monitor sistem

Beban dan suhu CPU dan GPU, memori dan swap, jaringan, disk, kesehatan
baterai, dan konsumsi daya — nilai langsung dengan grafik sparkline, ambang
warna yang kamu atur sendiri, °C/°F, dan baris uptime. Semua pembacaan datang
langsung dari macOS dan hanya diperbarui saat tabnya terbuka. Baris memori
juga memperingatkan saat banyak memori pindah ke disk, bukan hanya saat macOS
sendiri bilang sedang sesak.

<div align="center">
<img src="https://hop.tools/screens/en/system.webp" width="420" alt="Hop — Monitor sistem">
</div>

### Riwayat clipboard

100 hal terakhir yang kamu salin (hingga 300) — teks, gambar, dan file —
sekali klik untuk menyalin kembali atau menempel langsung ke aplikasi
sebelumnya. File yang disalin diingat berdasarkan namanya (beberapa sekaligus
tampil sebagai «nama +N»), dan menempel akan mengembalikan file itu sendiri.
Kata sandi dan input tersembunyi lainnya tidak pernah disimpan.

<div align="center">
<img src="https://hop.tools/screens/en/clipboard.webp" width="420" alt="Hop — Riwayat clipboard">
</div>

### Konverter file

Jatuhkan sekumpulan gambar, PDF, video, atau audio ke panel: keluarannya JPEG,
PNG, HEIC, AVIF, dan WebP; kompresi PDF; pengecilan video HEVC dengan
perkiraan ukuran yang jujur dan langsung sebelum kamu mengonversi. Semuanya
diproses secara lokal. Video juga bisa dibingkai ulang saat dikonversi — 9:16,
4:5, persegi, atau 16:9, dipangkas, diberi bilah, atau di atas salinan
buramnya — dan kompresi punya tingkatnya sendiri, jadi ukuran yang dijanjikan
sama dengan yang keluar.

Satu tombol menyiapkan klip untuk tujuannya — reels, feed, tiktok, shorts,
atau youtube — menuliskan bingkai, resolusi, dan kompresi sesuai anjuran
platform itu sendiri, dengan bitrate hasilnya di sebelah penggeser. MKV dan
WebM dikemas ulang ke MP4 lebih dulu (macOS tidak membuka keduanya) oleh
pembantu kecil yang diunduh sekali. Dokumen Pages, Numbers, dan Keynote
diekspor secara massal oleh aplikasinya sendiri: ke PDF, atau ke docx, xlsx,
dan pptx.

<div align="center">
<img src="https://hop.tools/screens/en/converter.webp" width="480" alt="Hop — Konverter file">
</div>

### Pengelola jendela

Tata jendela ke setengah, seperempat, sepertiga, dan tengah layar dengan
sekali klik pada glyph zona atau pintasan ⌃⌥ — tanpa aplikasi tambahan.

<div align="center">
<img src="https://hop.tools/screens/en/windows.webp" width="420" alt="Hop — Pengelola jendela">
</div>

### Torrent

Klien BitTorrent ringan di panel yang sama: jatuhkan file .torrent atau
tempel tautan magnet, pilih persis file mana yang mau diunduh — sebelum
atau bahkan selama pengunduhan — jeda, lanjutkan, dan seeding, dengan
opsi berhenti otomatis di rasio 1.0. Modul ini nonaktif secara bawaan;
saat diaktifkan, mesin open source diunduh sebagai paket kecil terpisah
(~26 MB, tanda tangannya diverifikasi) yang hanya berkomunikasi dengan
Hop lewat port lokal. Hop juga bisa menjadi aplikasi bawaan untuk file
.torrent dan tautan magnet.

<div align="center">
<img src="https://hop.tools/screens/en/torrents.webp" width="420" alt="Torrent Hop — klien BitTorrent ringan di panel menu bar">
</div>

### Arsip berkas

Baris modul membuka sebuah jendela, dan di jendela itulah berkas dijatuhkan —
⌘V juga bisa, beberapa berkas sekaligus. Yang kamu tambahkan menunggu dalam
daftar sampai kamu menekan tombol: arsip diekstrak, sisanya masuk ke satu arsip.
Hasilnya jatuh ke desktop secara bawaan, atau di sebelah aslinya, atau ke folder
mana pun yang kamu pilih. Yang didukung: zip, rar, 7z, tar, tar.gz, tar.bz2,
tar.xz, dan gz; untuk rar dan 7z, saat pertama kali dijumpai, diunduh pembantu
kecil (~6 MB) yang tanda tangannya diperiksa. Hop membuka rar tetapi tidak
pernah membuatnya — formatnya berpemilik. «Hop sebagai bawaan untuk arsip» di pengaturan hanya
menawarkan rar saat tidak ada aplikasi Apple yang menanganinya, dan dapat merebut rar
kembali dari aplikasi pihak ketiga; zip, 7z, dan format bawaan tetap di Utilitas Arsip. Ini
bekerja walau modulnya disembunyikan, dan kartunya menunjukkan keadaan asli. Klik ganda pada arsip di Finder membukanya tepat di sebelah berkasnya, dalam jendela progres kecil tersendiri, dan kegagalan tidak meninggalkan apa pun yang tersembunyi. Berkas yang dibuka Hop membawa ikonnya sendiri dengan nama formatnya, jadi satu folder terbaca sekali lihat.

<div align="center">
<img src="https://hop.tools/screens/en/archives.webp" width="480" alt="Hop — Arsip berkas">
</div>

### Dokumen

Konverter belajar dokumen: markdown → PDF yang ditata Hop sendiri, berkas Word
(.docx, .doc, .rtf) → PDF atau markdown, dan teks dari PDF sebagai markdown —
halaman pindaian dibaca oleh Vision milik Apple. Semuanya native dan offline,
tanpa paket kantor bawaan dan tanpa unduhan.

### Pemilih warna

Ambil warna apa pun di layar dengan lup sistem: warnanya tinggal di daftar,
tiap baris membawa hex, rgb, dan hsl di kolomnya sendiri — klik salah satu dan
notasi itulah yang tersalin. Urutannya tak pernah berubah di bawah kursor,
berapa warna disimpan dan berapa baris tampil adalah pengaturan, dan izin rekam
layar tidak diperlukan: lup hanya mengembalikan satu warna.

<div align="center">
<img src="https://hop.tools/screens/en/colors.webp" width="420" alt="Hop — Pemilih warna">
</div>

### Pengenalan teks

Bingkai sebuah area layar, atau jatuhkan gambar ke jendela dan tempel satu
dengan ⌘V: teks dan kode QR di dalamnya keluar di jendela yang bisa dibaca,
disunting, dan disalin, sekaligus masuk ke riwayat papan klip. Pemenggalan
baris dipertahankan, jadi tabel tetap terbaca. Pengenalannya memakai Vision
milik Apple, sepenuhnya di Mac ini.

Kalau hasilnya memuat alamat web, tombol «buka tautan» muncul: tautan dari
kode QR pada tagihan langsung terbuka di peramban, tanpa perlu ponsel. Hanya
alamat web: kode yang dipindai adalah masukan dari luar, jadi nomor telepon,
kata sandi Wi-Fi atau kartu kontak tetap teks biasa.

<div align="center">
<img src="https://hop.tools/screens/en/recognition.webp" width="480" alt="Hop — Pengenalan teks">
</div>

### Kunci papan ketik

Ketuk 1, 5, atau 15 menit — atau ∞ — dan seluruh papan ketik berhenti merespons,
sehingga bisa dilap tanpa mematikan Mac atau menutup layar. Penutup layar penuh
menjelaskan apa yang terjadi, dan ikon bilah menu berubah jadi papan ketik.
Empat jalan keluar: tombol di penutup, tombol di panel, membuka panel, atau
menahan esc + shift lima detik. Tekanan singkat tombol daya juga ditelan; menahannya
tetap mematikan Mac secara paksa, karena itu urusan perangkat keras.

<div align="center">
<img src="https://hop.tools/screens/en/keyboard.webp" width="480" alt="Hop — Kunci papan ketik">
</div>

### Tes kecepatan

Sekali ketuk, koneksi diukur lewat networkQuality bawaan macOS terhadap server Apple — unduh, unggah, dan responsivitas, dengan hasil terakhir tersimpan di barisnya.

<div align="center">
<img src="https://hop.tools/screens/en/speed.webp" width="420" alt="Hop — Tes kecepatan">
</div>

### Ikon di bilah menu

Ikonnya membawa tanda kecil: waktu yang berjalan, penahan tidur, pengingat yang
berbunyi, titik selama VPN menyala (jingga bila tak ada lagi yang lewat), dan panah
selama torrent bergerak — berwarna atau monokrom, masing-masing bisa dimatikan.
Jendela milik Hop muncul di Dock selama terbuka, jadi satu klik mengembalikan jendela
alih-alih membuka panel, dan ikonnya pergi bersama jendela terakhir.

### Tema, pintasan, dan mode aman

Tema gelap dan terang dengan tekstur butiran film, pintasan global, jalan saat masuk, dan mode aman yang mengeluarkan aplikasi dari putaran kegagalan — semuanya di satu jendela pengaturan.

<div align="center">
<img src="https://hop.tools/screens/en/settings.webp" width="480" alt="Hop — Pengaturan">
</div>

### VPN

Semua VPN yang dikenal Mac Anda, masing-masing dengan sakelarnya, dari vendor mana
pun. Hop membaca daftarnya langsung dari pengaturan sistem: klien yang dipasang
kemarin muncul sendiri, yang dihapus menghilang. Tidak ada yang perlu ditambahkan
atau diatur di sini.

Sambung dan putus tanpa membuka apa pun. Selama sebuah terowongan berdiri, titik kecil
menyala di sudut ikon bilah menu, di samping indikator lain: hijau selama ada yang
lewat, jingga ketika terowongan menyala tetapi tidak ada yang kembali lewat sana.
Sambungan yang mati diam-diam tidak lagi tampak sehat, dan panel menandai baris yang
dimaksud. Klik namanya dan jendela VPN itu terbuka; setelah Anda menutupnya, Hop
menutup aplikasinya. Sambungan tetap ada: terowongan dipegang sistem, bukan aplikasi.

Barisnya menunjukkan apa yang dilaporkan klien itu sendiri: namanya dan, dalam
kurung, tambahan dari konfigurasi — biasanya negara. Hop tidak pernah menebak
negara dari alamat server: daftar alamat menyebut di mana rentang itu terdaftar,
bukan di mana mesinnya berada.

Titik itu bisa dimatikan di pengaturan; modul dan sakelarnya tetap bekerja.

<div align="center">
<img src="https://hop.tools/screens/en/vpn.webp" width="420" alt="Hop — Sakelar VPN">
</div>

### Aplikasi

Kisi berisi program yang Anda buka sepanjang hari, sekali klik tanpa mampir ke
folder Applications. Tekan + lalu pilih, atau seret dari Finder; sembilan muat dalam sebaris, sampai delapan baris.

Seret ikon untuk memindahkannya: garis kuning menunjukkan di antara ikon mana ia
akan jatuh dan yang lain bergeser seperti di layar utama. Tombol ubah memulai
goyangan, tiap ikon mendapat ✕, dan kisi bisa diberi nama sendiri; di sana pula
nama di bawah ikon bisa dimatikan kalau Anda mengenali aplikasi dari
tampilannya. Kisinya boleh sebanyak apa pun — kerja di satu ruang, sisanya di
ruang lain — masing-masing punya aplikasi sendiri.

Kisi dibuat dan dihapus di tempat Anda menyusun modul: di pengaturan atau di
tabel modul itu sendiri, di mana ✕ pada cip sebuah kisi menghapusnya untuk
selamanya. Kisi baru mulai kosong dan mengatakannya sampai Anda mengisinya.

<div align="center">
<img src="https://hop.tools/screens/en/apps.webp" width="420" alt="Hop — Kisi aplikasi">
</div>

### Menghapus aplikasi

Jatuhkan aplikasi ke baris ini, atau pilih dari daftar semua yang terpasang, dan ia pergi bersama apa yang ditinggalkannya di sekitar tiga puluh tempat: application support, cache, preferensi, container, launch agents, plug-in, tanda terima pemasangan, dan selebihnya. Tiap aplikasi di daftar menunjukkan besarnya, bundel dan datanya terpisah. Aplikasi yang sudah ada di tempat sampah tetap dikenali: pengenalnya dibaca dari bundel di sana, atau disimpulkan dari sisa-sisa yang menyebut namanya.

Tidak ada yang dihapus permanen. Semuanya pindah ke tempat sampah, jadi kesalahan berharga satu pemulihan, bukan sebuah berkas; dan yang tidak diserahkan macOS disebutkan beserta alasannya, bukan dilewati diam-diam.

<div align="center">
<img src="https://hop.tools/screens/en/uninstall.webp" width="480" alt="Hop — Menghapus aplikasi beserta semua yang ditinggalkannya">
</div>

Modul yang sama merapikan tanpa menghapus apa pun: setiap aplikasi yang menyimpan cache, terbesar dulu; pemasang yang tertinggal di Unduhan, Meja, dan Dokumen; data aplikasi yang dihapus bertahun lalu; dan tempat sampah beserta ukurannya. Satu centang mengambil satu bagian penuh. Yang sengaja tidak disentuh juga didaftar — container tempat cache dan data berbagi satu folder, termasuk dua puluh gigabyte sebuah aplikasi pesan: hanya aplikasi itu yang tahu bagian mana yang bisa dibuang.

<div align="center">
<img src="https://hop.tools/screens/en/clean.webp" width="480" alt="Hop — Membersihkan cache, pemasang, sisa, dan tempat sampah">
</div>

## 22 bahasa

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — aplikasi langsung mengikuti bahasa sistem
kamu.

## Dukung proyek ini

Hop gratis dan akan tetap begitu. Kalau ia layak dapat tempat di bilah menumu,
kontribusi sukarela membantu merilis fitur baru dan memoles yang sudah ada — yang
dibelinya cuma waktu.

**[→ Dukung Hop](https://web.tribute.tg/d/Nvk)**

## Privasi — dan kenapa izinnya aman diberikan

**Hop tidak mengumpulkan apa pun. Sekarang tidak, nanti juga tidak.** Tidak ada
server sendiri, tidak ada analitik, tidak ada telemetri, tidak ada akun, tidak
ada laporan crash. Setiap izin di bawah baru diminta macOS ketika kamu memang
memakai fungsi yang membutuhkannya, dan izin itu ada persis supaya fungsi itu
bekerja — tidak ada yang dikumpulkan sambil jalan. Kamu tidak perlu percaya
begitu saja: aplikasinya open source, dan kode yang mengumpulkan itu memang
tidak ada. Cari SDK pelacakan atau panggilan analitik di repositori ini — tidak
akan ketemu.

Semuanya berjalan secara lokal: tanpa server, tanpa analitik, tanpa akun.
Aplikasi hanya menyentuh jaringan untuk memeriksa pembaruan, saat kamu
menjalankan tes kecepatan bawaan, dan — jika kamu mengaktifkan modul
torrent — untuk mengunduh mesinnya sekali serta memindahkan lalu lintas
torrent itu sendiri. Pemeriksaan pembaruan itu mengirim versi yang kamu
jalankan, dan tidak ada yang mengidentifikasi kamu atau Mac-mu. Pembaruan
dan mesin torrent dikirim sebagai arsip bertanda tangan dan diverifikasi
dengan tanda tangan Ed25519 sebelum
dipasang.

## Izin

Hop meminta izin hanya ketika fitur yang membutuhkannya benar-benar dipakai, dan
jendela info aplikasi mendaftar semuanya beserta statusnya saat ini:

- **jaringan — antonshakirov.com** — memeriksa dan mengunduh pembaruan, plus dua
  pembantu opsional (mesin torrent dan pengarsip 7-Zip)
- **jaringan — torrent, tes kecepatan** — lalu lintas ke peer lain saat modul
  torrent aktif; tesnya memakai networkQuality bawaan macOS ke server Apple
- **aksesibilitas** — menempel ke aplikasi di bawah, pengatur jendela, dan kunci
  papan ketik
- **rekam layar** — hanya modul pengenalan teks, dan hanya saat membingkai area;
  pemilih warna tidak memerlukannya
- **notifikasi** — peringatan pengatur waktu dan torrent yang selesai
- **kata sandi administrator** — sekali, untuk mode layar tertutup (pmset hanya
  jalan sebagai root)
- **buka saat masuk** — mati sampai kamu menyalakannya

Saat dibuka tidak ada yang diminta, dan tidak ada yang ditanyakan untuk modul yang
belum kamu nyalakan. Tanpa analitik, tanpa telemetri, tanpa akun, tanpa laporan
crash: antonshakirov.com dihubungi hanya untuk menanyakan apakah ada versi lebih
baru — dan mengunduhnya, atau salah satu dari dua pembantu opsional, kalau kamu
setuju. Sisanya tetap di Mac ini: riwayat papan klip, waktu yang tercatat, daftar
tugas, teks hasil pengenalan, dan warna yang diambil.

Setiap izin di atas ada supaya sebuah fungsi bisa bekerja — dan tidak untuk hal
lain. Kamu tidak perlu percaya begitu saja: Hop open source, dan kode yang
mengumpulkan itu memang tidak ada — baca di repositori ini. Jendela info
aplikasi punya tab «izin aplikasi» dengan daftar yang sama dan status setiap
izin saat ini.

Situs web: [hop.tools](https://hop.tools)

## Gratis, dan alasannya

Hop sepenuhnya gratis: tanpa masa coba, tanpa versi pro, tanpa pembelian dalam
aplikasi. Tanpa iklan, tanpa pengumpulan data, tanpa akun — tidak ada yang bisa
dimonetisasi dan tidak ada yang bisa dijual. Ini proyek pribadi: saya membuat
Hop untuk diri sendiri, memakainya setiap hari, dan sekadar membagikannya.
Kalau bermanfaat, teruskan ke orang lain. Dan kalau kamu ingin ikut membantu,
kini ada cara untuk mendukung Hop — murni sebuah hadiah, tanpa imbalan apa pun.

## Membangun dari sumber

Swift Package Manager, macOS 14+, tanpa dependensi eksternal:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Alur pengembangan, pipeline rilis, dan spesifikasi perilaku ada di
[docs/development.md](../development.md) dan [docs/spec.md](../spec.md).

## Dukung proyek ini

Tiga cara, semuanya diterima dengan senang hati:

- **[Dukung Hop dengan kontribusi](https://web.tribute.tg/d/Nvk)** — langsung jadi
  fitur baru dan perbaikan. Sukarela, tanpa imbalan, tanpa apa pun yang berbayar:
  setiap modul sama untuk semua orang.
- **[Beri bintang ke repo](https://github.com/antonyshakirov/hop/stargazers)** —
  lewat bintang orang lain menemukannya.
- **[Buka issue](https://github.com/antonyshakirov/hop/issues)** — laporan bug atau
  sebuah ide nilainya sama.

## Pembuat & lisensi

Dibuat oleh [Anton Shakirov](https://www.antonshakirov.com/en). Dirilis di
bawah [lisensi MIT](../../LICENSE): gunakan dan modifikasi dengan bebas,
pertahankan pemberitahuan hak cipta — mengaku-ngaku aplikasi ini sebagai
karyamu sendiri adalah pelanggaran lisensi.
