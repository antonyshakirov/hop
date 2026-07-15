<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="ไอคอนแอป Hop — เครื่องหมายดอกจันสี่เส้น">

# Hop

**เพื่อนตัวจิ๋วบนแถบเมนูของ macOS: ตัวจับเวลา ป้องกันเครื่องหลับ
มอนิเตอร์ระบบ ประวัติคลิปบอร์ด ตัวแปลงไฟล์ และตัวจัดการหน้าต่าง
คลิกเดียว — ทุกอย่างที่คุณต้องการอยู่ตรงนั้น**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · **ไทย** · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="แผงควบคุม Hop — ตัวจับเวลาบนแถบเมนูพร้อมจอแสดงผลแบบดอตแมทริกซ์ พรีเซ็ต และรอบทำงาน-พัก">

</div>

Hop อาศัยอยู่บนแถบเมนูของ Mac และเข้ามาแทนที่ยูทิลิตี้เล็ก ๆ ถึงหกตัว:
ตัวจับเวลาสไตล์ Pomodoro ตัวกันเครื่องหลับแบบ caffeinate มอนิเตอร์ระบบ
ตัวจัดการคลิปบอร์ด ตัวแปลงไฟล์แบบลากมาวาง และตัวจัดหน้าต่าง —
แอปเนทีฟเบา ๆ หนึ่งตัวแทนที่หกตัว

## ดาวน์โหลด

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — เปิดแล้วลาก `Hop.app` ไปยังโฟลเดอร์ Applications (แนะนำ)
- `Hop-x.y.z.zip` — แอปตัวเดียวกันในรูปแบบไฟล์บีบอัดธรรมดา (ตัวอัปเดตในตัวใช้ไฟล์นี้) ดูได้ที่[รีลีสล่าสุด](https://github.com/antonyshakirov/hop/releases/latest)
- มิเรอร์ความเร็วสูง: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

การเปิดครั้งแรก: คลิกขวาที่ `Hop.app` → **เปิด** → ยืนยัน
(แอปยังไม่ผ่านการ notarize) ต้องใช้ macOS 14 ขึ้นไป

## ฟีเจอร์

### ตัวจับเวลาและรอบทำงาน

นาฬิกานับถอยหลังแบบดอตแมทริกซ์ที่ตั้งได้ในท่าเดียว: ลากตัวเลข
พิมพ์เวลาเหมือนกดไมโครเวฟ หรือเลือกพรีเซ็ต มีรอบทำงาน-พัก
(Pomodoro 25/5, 52/17, 90/15 — หรือกำหนดเองก็ได้) นาฬิกาจับเวลา
ช่องพักตัวจับเวลาที่กำลังเดินอยู่ระหว่างที่คุณลองตัวอื่น
และการแจ้งเตือนเมื่อหมดเวลาที่หยุดสื่อที่กำลังเล่นให้ได้ด้วย

### กันเครื่องหลับ

ให้ Mac ตื่นอยู่ 15 นาที 8 ชั่วโมง หรือตลอดไป — คลิกเดียว
ไม่ต้องใส่รหัสผ่าน เลือกให้จอเปิดค้างไว้ หรือทำงานต่อทั้งที่ปิดฝาเครื่อง
ก็ได้ (เหมาะกับการดาวน์โหลด งานบิลด์ยาว ๆ และจอภายนอก)

### มอนิเตอร์ระบบ

โหลดและอุณหภูมิของ CPU กับ GPU หน่วยความจำและ swap เครือข่าย ดิสก์
สุขภาพแบตเตอรี่และการใช้พลังงาน — ค่าแบบเรียลไทม์พร้อมกราฟ sparkline
เกณฑ์สีที่คุณตั้งเอง สลับ °C/°F ได้ และบรรทัดแสดงเวลาเปิดเครื่อง
ค่าทั้งหมดอ่านตรงจาก macOS และอัปเดตเฉพาะตอนที่แท็บเปิดอยู่เท่านั้น

### ประวัติคลิปบอร์ด

100 รายการล่าสุดที่คุณคัดลอก (สูงสุด 300 รายการ) ทั้งข้อความและรูปภาพ คลิกเดียวเพื่อคัดลอกกลับ
หรือวางลงในแอปก่อนหน้าได้ทันที รหัสผ่านและข้อความที่ถูกซ่อน
จะไม่ถูกเก็บไว้เด็ดขาด

### ตัวแปลงไฟล์

ลากรูปภาพ PDF วิดีโอ หรือไฟล์เสียงทั้งชุดมาวางบนแผง: ส่งออกเป็น JPEG, PNG,
HEIC, AVIF และ WebP บีบอัด PDF ย่อวิดีโอด้วย HEVC พร้อมการประเมินขนาด
แบบเรียลไทม์ที่ตรงไปตรงมาก่อนแปลงจริง ทุกอย่างประมวลผลในเครื่องทั้งหมด

### ตัวจัดการหน้าต่าง

จัดหน้าต่างให้ชิดครึ่งจอ หนึ่งในสี่ หนึ่งในสาม หรือกึ่งกลาง
ด้วยการคลิกที่สัญลักษณ์โซนหรือกดปุ่มลัด ⌃⌥ — ไม่ต้องติดตั้งแอปเพิ่ม

### และอื่น ๆ

ทดสอบความเร็วเน็ตในตัว (networkQuality ของ Apple) ธีมมืดและสว่าง
พร้อมพื้นผิวลายเกรนฟิล์ม ปุ่มลัดระดับระบบ เปิดอัตโนมัติเมื่อเข้าสู่ระบบ
และเซฟโหมดที่กู้แอปคืนจาก crash loop

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="มอนิเตอร์ระบบของ Hop — กราฟ CPU, GPU, หน่วยความจำ, เครือข่าย, ดิสก์, แบตเตอรี่">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="ตัวแปลงไฟล์ของ Hop — แปลงรูปภาพ, PDF, วิดีโอ และเสียงเป็นชุด">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="การตั้งค่า Hop — ธีม, โมดูล, ปุ่มลัด, 18 ภาษา">
</div>

## 18 ภาษา

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — แอปเปลี่ยนตามภาษาระบบของคุณ
โดยอัตโนมัติตั้งแต่แรก

## ความเป็นส่วนตัว

ทุกอย่างทำงานในเครื่อง: ไม่มีเซิร์ฟเวอร์ ไม่มีระบบวิเคราะห์ ไม่มีบัญชี
แอปเชื่อมต่อเครือข่ายเฉพาะตอนตรวจหาอัปเดตและตอนที่คุณรันทดสอบ
ความเร็วในตัวเท่านั้น อัปเดตถูกส่งเป็นไฟล์บีบอัดที่ลงลายเซ็นไว้
และตรวจสอบด้วยลายเซ็น Ed25519 ก่อนติดตั้งทุกครั้ง

เว็บไซต์: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## บิลด์จากซอร์สโค้ด

Swift Package Manager, macOS 14+, ไม่มี dependency ภายนอก:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

ขั้นตอนการพัฒนา ไปป์ไลน์รีลีส และสเปกพฤติกรรมของแอปอยู่ใน
[docs/development.md](../development.md) และ [docs/spec.md](../spec.md)

## สนับสนุนโปรเจกต์

ถ้า Hop ช่วยคุณประหยัดคลิกไปสักหนึ่งหรือสองครั้ง **[กดดาวให้รีโป](https://github.com/antonyshakirov/hop/stargazers)** —
ดาวคือหนทางที่คนอื่นจะค้นพบแอปนี้ ยินดีรับรายงานบั๊กและไอเดียฟีเจอร์
ที่ [Issues](https://github.com/antonyshakirov/hop/issues) เสมอ

## ผู้สร้างและสัญญาอนุญาต

สร้างโดย [Anton Shakirov](https://www.antonshakirov.com/en) เผยแพร่ภายใต้
[สัญญาอนุญาต MIT](../../LICENSE): ใช้และแก้ไขได้อย่างอิสระ แต่ต้องคง
ประกาศลิขสิทธิ์ไว้ — การนำแอปไปแอบอ้างว่าเป็นผลงานของตัวเอง
ถือเป็นการละเมิดสัญญาอนุญาต
