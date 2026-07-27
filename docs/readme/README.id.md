<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ikon aplikasi Hop — asterisk empat garis">

# Hop

**Pendamping mungil di menu bar macOS: timer, pelacak waktu, daftar tugas,
anti-tidur, monitor sistem, riwayat clipboard, konverter file, pengelola
jendela, dan klien torrent ringan — tersebar di hingga empat tab pada ikon.
Sekali klik — semua yang kamu butuhkan langsung ada.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

**Bahasa Indonesia** · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/overview.png" width="360" alt="Panel Hop — timer di menu bar dengan tampilan dot-matrix, preset, dan siklus kerja-istirahat">

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

Peluncuran pertama di macOS 15 atau lebih baru: coba buka Hop sekali, lalu
buka **Pengaturan Sistem → Privasi & Keamanan → Tetap Buka** dan konfirmasi
**Buka**. Hop tidak dinotarisasi karena keanggotaan Apple Developer Program
tidak tersedia bagi pembuatnya. Kode sumbernya terbuka untuk umum, dan
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
<img src="https://www.antonshakirov.com/products/hop/screens/en/timer.png" width="420" alt="Hop — Timer & siklus">
</div>

### Pelacak waktu & tugas

Catat waktu di daftar tugas yang datar: tiap baris menampilkan waktu hari
ini dan total berjalan, dan angka hari ini bisa kamu perbaiki manual. Kalau
satu berjalan terlalu lama, sebuah spanduk mengingatkan setelah delapan jam.
Di sebelahnya ada daftar tugas terpisah, tempat yang selesai turun ke bawah.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/tracker.png" width="420" alt="Hop — Pelacak waktu & tugas">
</div>

### Anti-tidur

Jaga Mac tetap terjaga selama 15 menit, 8 jam, atau selamanya — sekali
klik, tanpa kata sandi. Opsional: biarkan layar tetap menyala, atau terus
bekerja dengan penutup tertutup (praktis untuk unduhan, build panjang, dan
layar eksternal).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/awake.png" width="420" alt="Hop — Anti-tidur">
</div>

### Monitor sistem

Beban dan suhu CPU dan GPU, memori dan swap, jaringan, disk, kesehatan
baterai, dan konsumsi daya — nilai langsung dengan grafik sparkline, ambang
warna yang kamu atur sendiri, °C/°F, dan baris uptime. Semua pembacaan
datang langsung dari macOS dan hanya diperbarui saat tabnya terbuka.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="420" alt="Hop — Monitor sistem">
</div>

### Riwayat clipboard

100 hal terakhir yang kamu salin (hingga 300) — teks, gambar, dan file —
sekali klik untuk menyalin kembali atau menempel langsung ke aplikasi
sebelumnya. File yang disalin diingat berdasarkan namanya (beberapa sekaligus
tampil sebagai «nama +N»), dan menempel akan mengembalikan file itu sendiri.
Kata sandi dan input tersembunyi lainnya tidak pernah disimpan.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clipboard.png" width="420" alt="Hop — Riwayat clipboard">
</div>

### Konverter file

Jatuhkan sekumpulan gambar, PDF, video, atau audio ke panel: keluarannya
JPEG, PNG, HEIC, AVIF, dan WebP; kompresi PDF; pengecilan video HEVC dengan
perkiraan ukuran yang jujur dan langsung sebelum kamu mengonversi. Semuanya
diproses secara lokal.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="480" alt="Hop — Konverter file">
</div>

### Pengelola jendela

Tata jendela ke setengah, seperempat, sepertiga, dan tengah layar dengan
sekali klik pada glyph zona atau pintasan ⌃⌥ — tanpa aplikasi tambahan.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/windows.png" width="420" alt="Hop — Pengelola jendela">
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
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Torrent Hop — klien BitTorrent ringan di panel menu bar">
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
<img src="https://www.antonshakirov.com/products/hop/screens/en/archives.png" width="480" alt="Hop — Arsip berkas">
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
<img src="https://www.antonshakirov.com/products/hop/screens/en/colors.png" width="420" alt="Hop — Pemilih warna">
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
<img src="https://www.antonshakirov.com/products/hop/screens/en/recognition.png" width="480" alt="Hop — Pengenalan teks">
</div>

### Kunci papan ketik

Ketuk 1, 5, atau 15 menit — atau ∞ — dan seluruh papan ketik berhenti merespons,
sehingga bisa dilap tanpa mematikan Mac atau menutup layar. Penutup layar penuh
menjelaskan apa yang terjadi, dan ikon bilah menu berubah jadi papan ketik.
Empat jalan keluar: tombol di penutup, tombol di panel, membuka panel, atau
menahan esc + shift lima detik. Tekanan singkat tombol daya juga ditelan; menahannya
tetap mematikan Mac secara paksa, karena itu urusan perangkat keras.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/keyboard.png" width="480" alt="Hop — Kunci papan ketik">
</div>

### Dan selebihnya

Indikator status kecil pada ikon menu bar — waktu, anti-tidur, peringatan,
dan aktivitas torrent, berwarna atau monokrom —, tes kecepatan bawaan
(networkQuality dari Apple), tema gelap dan terang dengan tekstur film-grain,
pintasan global, buka saat login, dan mode aman yang memulihkan aplikasi
dari crash loop.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Monitor sistem Hop — grafik CPU, GPU, memori, jaringan, disk, baterai">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Konverter file Hop — konversi batch gambar, PDF, video, dan audio">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Pengaturan Hop — tema, modul, pintasan, 22 bahasa">
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

Situs web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

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
