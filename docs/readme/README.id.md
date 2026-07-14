<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ikon aplikasi Hop — asterisk empat garis">

# Hop

**Pendamping mungil di menu bar macOS: timer, anti-tidur, monitor sistem,
riwayat clipboard, konverter file, dan pengelola jendela. Sekali klik —
semua yang kamu butuhkan langsung ada.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

**Bahasa Indonesia** · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="Panel Hop — timer di menu bar dengan tampilan dot-matrix, preset, dan siklus kerja-istirahat">

</div>

Hop tinggal di menu bar Mac kamu dan menggantikan setengah lusin utilitas
kecil: timer ala Pomodoro, pencegah tidur ala caffeinate, monitor sistem,
pengelola clipboard, konverter file drag-and-drop, dan penata jendela —
satu aplikasi native yang ringan, bukan enam.

## Unduh

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — buka lalu seret `Hop.app` ke Applications (disarankan)
- `Hop-x.y.z.zip` — aplikasi yang sama dalam bentuk arsip biasa (dipakai oleh pembaru bawaan); lihat [rilis terbaru](https://github.com/antonyshakirov/hop/releases/latest)
- Mirror cepat: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Peluncuran pertama: klik kanan `Hop.app` → **Open** → konfirmasi
(aplikasi belum dinotarisasi). Membutuhkan macOS 14 atau lebih baru.

## Fitur

### Timer & siklus

Hitung mundur dot-matrix yang kamu atur dengan satu gerakan: seret
angkanya, ketik waktunya seperti di microwave, atau pilih preset. Siklus
kerja-istirahat (Pomodoro 25/5, 52/17, 90/15 — atau buatanmu sendiri),
stopwatch, kantong simpanan yang menjaga timer tetap berjalan saat kamu
mencoba timer lain, dan notifikasi selesai yang juga bisa menjeda media.

### Anti-tidur

Jaga Mac tetap terjaga selama 15 menit, 8 jam, atau selamanya — sekali
klik, tanpa kata sandi. Opsional: biarkan layar tetap menyala, atau terus
bekerja dengan penutup tertutup (praktis untuk unduhan, build panjang, dan
layar eksternal).

### Monitor sistem

Beban dan suhu CPU dan GPU, memori dan swap, jaringan, disk, kesehatan
baterai, dan konsumsi daya — nilai langsung dengan grafik sparkline, ambang
warna yang kamu atur sendiri, °C/°F, dan baris uptime. Semua pembacaan
datang langsung dari macOS dan hanya diperbarui saat tabnya terbuka.

### Riwayat clipboard

100 hal terakhir yang kamu salin (hingga 300), sekali klik untuk menyalin
kembali atau menempel langsung ke aplikasi sebelumnya. Kata sandi dan input
tersembunyi lainnya tidak pernah disimpan.

### Konverter file

Jatuhkan sekumpulan gambar, PDF, video, atau audio ke panel: keluarannya
JPEG, PNG, HEIC, AVIF, dan WebP; kompresi PDF; pengecilan video HEVC dengan
perkiraan ukuran yang jujur dan langsung sebelum kamu mengonversi. Semuanya
diproses secara lokal.

### Pengelola jendela

Tata jendela ke setengah, seperempat, sepertiga, dan tengah layar dengan
sekali klik pada glyph zona atau pintasan ⌃⌥ — tanpa aplikasi tambahan.

### Dan selebihnya

Tes kecepatan bawaan (networkQuality dari Apple), tema gelap dan terang
dengan tekstur film-grain, pintasan global, buka saat login, dan mode aman
yang memulihkan aplikasi dari crash loop.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Monitor sistem Hop — grafik CPU, GPU, memori, jaringan, disk, baterai">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Konverter file Hop — konversi batch gambar, PDF, video, dan audio">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Pengaturan Hop — tema, modul, pintasan, 18 bahasa">
</div>

## 18 bahasa

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — aplikasi langsung mengikuti bahasa sistem
kamu.

## Privasi

Semuanya berjalan secara lokal: tanpa server, tanpa analitik, tanpa akun.
Aplikasi hanya menyentuh jaringan untuk memeriksa pembaruan dan saat kamu
menjalankan tes kecepatan bawaan. Pembaruan dikirim sebagai arsip
bertanda tangan dan diverifikasi dengan tanda tangan Ed25519 sebelum
dipasang.

Situs web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

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

Kalau Hop menghemat satu-dua klik untukmu, **[beri bintang pada repo](https://github.com/antonyshakirov/hop/stargazers)** —
lewat bintang itulah orang lain menemukannya. Laporan bug dan ide fitur
sangat diterima di [Issues](https://github.com/antonyshakirov/hop/issues).

## Pembuat & lisensi

Dibuat oleh [Anton Shakirov](https://www.antonshakirov.com/en). Dirilis di
bawah [lisensi MIT](../../LICENSE): gunakan dan modifikasi dengan bebas,
pertahankan pemberitahuan hak cipta — mengaku-ngaku aplikasi ini sebagai
karyamu sendiri adalah pelanggaran lisensi.
