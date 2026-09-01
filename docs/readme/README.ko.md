<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop 앱 아이콘 — 네 줄 애스터리스크">

# Hop

**macOS 메뉴 막대에 사는 작은 동반자: 타이머, 시간 추적, 할 일, 잠자기 방지,
시스템 모니터, 클립보드 히스토리, 파일 변환기, 창 관리자, 그리고 가벼운
토렌트 클라이언트. 필요한 것만 켜서 아이콘의 최대 네 개 탭에 나눠 담습니다.
클릭 한 번이면 필요한 모든 것이 바로 그 자리에.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · **한국어** · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://hop.tools/screens/en/overview.webp" width="360" alt="Hop 패널 — 도트 매트릭스 디스플레이, 프리셋과 작업-휴식 사이클을 갖춘 메뉴 막대 타이머">

</div>

Hop은 Mac의 메뉴 막대에 자리 잡고 자잘한 유틸리티 여러 개를 대신합니다.
뽀모도로식 타이머, 할 일 목록이 딸린 시간 추적, caffeinate 스타일 잠자기
차단, 시스템 모니터, 클립보드 관리자, 드래그 앤 드롭 파일 변환기, 창 스냅
기능, 그리고 가벼운 토렌트 클라이언트까지 — 가벼운 네이티브 앱 하나에,
자주 쓰는 모듈을 아이콘의 최대 네 개 탭에 나눠 담습니다.

## 다운로드

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — 열어서 `Hop.app`을 응용 프로그램 폴더로 드래그하세요(권장)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — 같은 앱의 일반 아카이브(내장 업데이터가 사용). [최신 릴리스](https://github.com/antonyshakirov/hop/releases/latest) 참고
- 고속 미러: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Hop은 Apple Developer ID로 서명되고 Apple의 공증을 받았습니다. macOS는 다른 앱과 똑같이 엽니다. 소스 코드는
공개되어 있으며, 내장 업데이트는 Ed25519로 검증됩니다. macOS 14 이상이 필요합니다.

## 기능

### 공간

아이콘에는 최대 네 개의 탭을 둘 수 있고, 각 모듈을 원하는 탭으로 끌어다
놓습니다. 타이머는 한쪽에, 모니터는 다른 쪽에, 잘 열지 않는 것은 옆으로.
「비활성」 선반은 옆으로 치워 둔 것을 지우지 않고 보관합니다.

### 타이머와 사이클

제스처 한 번으로 맞추는 도트 매트릭스 카운트다운: 숫자를 드래그하거나,
전자레인지처럼 시간을 입력하거나, 프리셋을 고르세요. 작업-휴식 사이클
(25/5 뽀모도로, 52/17, 90/15 — 직접 만들 수도 있습니다), 스톱워치,
다른 타이머를 써 보는 동안 돌아가던 타이머를 보관해 주는 스태시,
그리고 재생 중인 미디어까지 멈춰 줄 수 있는 종료 알림. 카운트다운이 끝나면
소리가 한 번 울리고, 초기화할 때까지 숫자가 깜박입니다.

<div align="center">
<img src="https://hop.tools/screens/en/timer.webp" width="420" alt="Hop — 타이머와 사이클">
</div>

### 시간 추적과 할 일

작업은 프로젝트로 묶을 수 있고 각각 합계가 붙습니다. 목록 위 스위치로 오늘·이번 주·전체를 고릅니다. 진행 중인 작업은 지금의 구간을
0부터 세고, 옆의 ✓ 가 그 구간을 닫으면 줄에는 그 기간의 합계가 돌아옵니다. 작업을 열면 모아온 시간 구간이 모두 보여, 길이나 시점을
고치고, 아무도 재지 않은 작업을 더하고, 필요 없는 줄을 지울 수 있습니다. 손으로 한 수정도 같은 목록에 있어 줄들의 합은 언제나 위의
합계와 맞습니다. 하나가 너무 오래 돌면 여덟 시간이 지날 때 배너가 알려 줍니다. 옆에는 별도의 할 일 목록이 있어, 끝낸 항목은 아래로
가라앉습니다.

작업을 클릭하면 펼쳐집니다. 첫 줄에 전체 제목, 그 아래에 설명, 별표는 즐겨찾기입니다.
할 일에는 날짜와 시간, 반복할 요일을 자유롭게 지정한 알림을 붙일 수 있고, 때가 되면
Hop이 알려줍니다 — '다시 알림'과 '완료'가 있는 배너, 소리, 메뉴 막대 표시. 각각 따로
켜고 끌 수 있습니다.

**당신의 AI 에이전트도 작업을 추가할 수 있습니다.** 목록은 평범한 JSON 파일이고, Hop은
실행 중에도 그 변경을 읽어들입니다. 명령 파일 실행과 `hop://` 링크도 지원하므로 같은
에이전트나 그 링크로 만든 단축어가 타이머를 시작하고, 알림이 있는 작업을 추가하고,
지금 무엇이 실행 중인지 읽을 수 있습니다.
[docs/automation.md](../automation.md) 참고.

<div align="center">
<img src="https://hop.tools/screens/en/tracker.webp" width="420" alt="Hop — 시간 추적과 할 일">
</div>

### 잠자기 방지

Mac을 15분, 8시간, 혹은 영원히 깨어 있게 — 클릭 한 번, 암호는 필요
없습니다. 디스플레이를 계속 켜 두거나, 덮개를 닫은 채로 작업을 이어갈
수도 있습니다(다운로드, 긴 빌드, 외장 디스플레이에 유용).

<div align="center">
<img src="https://hop.tools/screens/en/awake.webp" width="420" alt="Hop — 잠자기 방지">
</div>

### 시스템 모니터

CPU와 GPU의 부하와 온도, 메모리와 스왑, 네트워크, 디스크, 배터리 상태와 전력 소모 — 스파크라인
차트가 붙은 실시간 값, 직접 정하는 색상 임계값, °C/°F 전환, 가동 시간 표시까지. 값은 macOS에서
바로 읽어 오며 탭이 열려 있는 동안에만 갱신됩니다. 메모리 행은 macOS가 부족을 알릴 때뿐 아니라,
메모리가 디스크로 많이 밀려났을 때도 알려줍니다.

<div align="center">
<img src="https://hop.tools/screens/en/system.webp" width="420" alt="Hop — 시스템 모니터">
</div>

### 클립보드 히스토리

최근에 복사한 100개(최대 300개)의 항목 — 텍스트, 이미지, 파일 — 을 클릭 한
번으로 다시 복사하거나 이전 앱에 바로 붙여넣기. 복사한 파일은 이름으로
기억하고(여러 개면 「이름 +N」), 붙여넣으면 파일 자체가 돌아옵니다. 암호를
비롯한 가려진 입력은 절대 저장되지 않습니다.

<div align="center">
<img src="https://hop.tools/screens/en/clipboard.webp" width="420" alt="Hop — 클립보드 히스토리">
</div>

### 파일 변환기

이미지, PDF, 비디오, 오디오를 한꺼번에 패널에 드롭하세요. JPEG, PNG, HEIC, AVIF, WebP로 출력, PDF 압축, HEVC 비디오 용량 줄이기 — 변환 전에 실시간으로 정직한 용량 예측을 보여 줍니다. 모든 처리는 로컬에서 이루어집니다. 영상은 변환하면서 화면비도 바꿀 수 있습니다. 9:16, 4:5, 정사각형, 16:9 중에서, 잘라 채우거나 여백을 넣거나 자신의 흐린 복사본 위에 올려서. 압축에는 세기 조절이 생겨서, 변환 전에 알려 준 크기가 그대로 나옵니다.

버튼 하나로 영상을 올릴 곳에 맞춥니다 — reels·feed·tiktok·shorts·youtube — 화면비, 해상도, 압축 정도를
플랫폼 권장값대로 맞추고, 그 결과 비트레이트를 슬라이더 옆에 보여 줍니다. MKV와 WebM은 먼저 MP4로 다시 담습니다(macOS는 둘
다 열지 못합니다). 작은 도우미를 한 번만 내려받습니다. Pages·Numbers·Keynote 문서는 앱이 직접 묶음으로 내보냅니다:
PDF, 또는 docx·xlsx·pptx.

<div align="center">
<img src="https://hop.tools/screens/en/converter.webp" width="480" alt="Hop — 파일 변환기">
</div>

### 창 관리자

존 글리프를 클릭하거나 ⌃⌥ 단축키를 누르면 창을 절반, 4분의 1, 3분의 1,
가운데로 스냅 — 별도의 앱이 필요 없습니다.

<div align="center">
<img src="https://hop.tools/screens/en/windows.webp" width="420" alt="Hop — 창 관리자">
</div>

### 토렌트

같은 패널 안의 가벼운 BitTorrent 클라이언트: .torrent 파일을 드롭하거나
magnet 링크를 붙여넣고, 내려받을 파일을 정확히 골라 보세요 — 다운로드
전은 물론 진행 중에도 가능합니다. 일시 정지, 재개, 시딩을 지원하고,
비율 1.0에서 자동으로 멈추는 옵션도 있습니다. 이 모듈은 기본적으로
꺼져 있으며, 켜면 오픈 소스 엔진을 작은 별도 다운로드(~26 MB, 서명
검증)로 받아 오고, 이 엔진은 로컬 포트로만 Hop과 통신합니다. Hop을
.torrent 파일과 magnet 링크의 기본 앱으로 지정할 수도 있습니다.

<div align="center">
<img src="https://hop.tools/screens/en/torrents.webp" width="420" alt="Hop 토렌트 — 메뉴 막대 패널의 가벼운 BitTorrent 클라이언트">
</div>

### 파일 압축

모듈의 줄이 창을 열고, 파일은 그 창에 놓습니다 — ⌘V도 되고 여러 파일을 한 번에 넣을 수 있습니다.
추가한 것은 목록에서 기다리다가 버튼을 누르면 실행됩니다: 압축 파일은 풀리고, 나머지는 하나의 압축
파일로 묶입니다. 결과는 기본으로 데스크탑에 놓이며, 원본 옆이나 원하는 폴더도 고를 수 있습니다.
zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz, gz를 지원합니다. rar과 7z은 처음 만났을 때 약 6 MB짜리
작은 도우미를 서명 확인 후 내려받습니다. Hop은 rar을 풀지만 만들지는 않습니다. 독점 형식이기
때문입니다. 설정의 «압축 파일의 기본 앱을 Hop으로»는 Apple 앱이 맡지 않는 rar만 제안하고,
rar은 서드파티 앱에서 도로 가져올 수 있습니다. zip, 7z과 기본 형식은 «압축 유틸리티»에 그대로 둡니다. 모듈이 숨겨져 있어도
동작하며, 카드는 실제 상태를 보여 줍니다. Finder에서 압축 파일을 두 번 클릭하면 파일 바로 옆에 풀리고, 작은 진행 창이 따로 뜹니다. 실패해도 숨겨진 것이 남지 않습니다. Hop이 여는 파일에는 형식이 적힌 고유 아이콘이 붙어, 폴더를 한눈에 알아볼 수 있습니다.

<div align="center">
<img src="https://hop.tools/screens/en/archives.webp" width="480" alt="Hop — 파일 압축">
</div>

### 문서

변환기가 문서를 익혔습니다. markdown → PDF는 Hop이 직접 조판하고, Word
파일(.docx, .doc, .rtf) → PDF 또는 markdown, PDF의 본문을 markdown으로 뽑아낼
수도 있습니다. 스캔한 페이지는 Apple의 Vision이 읽습니다. 전부 네이티브에
오프라인이며, 내장 오피스도 추가 다운로드도 없습니다.

### 색상 스포이트

시스템 확대경으로 화면의 어떤 색이든 집으면 목록에 남습니다. 각 줄은 hex, rgb, hsl을 저마다의
칸에 담고, 누른 표기가 복사됩니다. 커서 밑에서 순서가 바뀌지 않고, 몇 개를 보관할지와 몇 줄을
보여 줄지는 설정이며, 화면 기록 권한도 필요 없습니다. 확대경은 색 하나만 돌려줍니다.

<div align="center">
<img src="https://hop.tools/screens/en/colors.webp" width="420" alt="Hop — 색상 스포이트">
</div>

### 텍스트 인식

화면 영역을 잡거나, 창에 이미지를 끌어다 놓거나 ⌘V로 붙여넣으세요. 그 안의 텍스트와 QR 코드가
읽고 고치고 복사할 수 있는 창에 나오고, 동시에 클립보드 기록에도 들어갑니다. 줄바꿈이 유지되어
표도 읽을 수 있습니다. 인식은 Apple의 Vision이며 전부 이 Mac 안에서 이뤄집니다.

인식 결과에 웹 주소가 있으면 「링크 열기」 버튼이 나타납니다. 청구서 QR 코드의 링크가 휴대폰 없
이 브라우저에서 바로 열립니다. 웹 주소만 해당합니다. 스캔한 코드는 외부에서 온 입력이므로 전화번
호나 Wi-Fi 비밀번호, 연락처 카드는 그대로 텍스트로 남습니다.

<div align="center">
<img src="https://hop.tools/screens/en/recognition.webp" width="480" alt="Hop — 텍스트 인식">
</div>

### 키보드 잠금

1분, 5분, 15분 — 또는 ∞ — 를 누르면 키보드 전체가 반응하지 않아, Mac을 끄거나 덮개를 닫지 않고도
닦을 수 있습니다. 전체 화면 덮개가 상황을 알려 주고 메뉴 막대 아이콘은 키보드로 바뀝니다. 푸는
방법은 넷입니다: 덮개의 버튼, 패널의 버튼, 패널 열기, esc + shift 5초 길게 누르기. 전원 키의 짧은 누름도
삼켜지지만, 길게 누르면 여전히 Mac이 강제로 꺼집니다. 그것은 하드웨어가 처리하기 때문입니다.

<div align="center">
<img src="https://hop.tools/screens/en/keyboard.webp" width="480" alt="Hop — 키보드 잠금">
</div>

### 속도 테스트

한 번 누르면 macOS 자체의 networkQuality가 Apple 서버를 상대로 회선을 잽니다. 내려받기, 올리기, 응답성이 나오고 마지막 결과는 줄에 남습니다.

<div align="center">
<img src="https://hop.tools/screens/en/speed.webp" width="420" alt="Hop — 속도 테스트">
</div>

### 메뉴 막대 아이콘

아이콘에는 작은 표시가 붙습니다. 흐르는 시간, 잠자기 방지, 울린 알림, VPN이 켜져 있는 동안의 점(아무것도 지나가지 않으면 주황), 토렌트가 오가는 동안의 화살표 — 컬러든 단색이든, 각각 끌 수 있습니다. Hop의 창들은 열려 있는 동안 Dock에 나타나므로, 클릭하면 패널을 열지 않고 창이 돌아오고, 마지막 창과 함께 아이콘도 사라집니다.

### 테마, 단축키, 안전 모드

필름 그레인 질감의 어두운 테마와 밝은 테마, 전역 단축키, 로그인 시 실행, 그리고 앱을 충돌 반복에서 꺼내 주는 안전 모드 — 모두 하나의 설정 창 안에.

<div align="center">
<img src="https://hop.tools/screens/en/settings.webp" width="480" alt="Hop — 설정">
</div>

### VPN

Mac이 아는 모든 VPN을, 어느 회사 것이든 각각 스위치와 함께. Hop은 목록을 시스템 설정에서
바로 읽습니다. 어제 설치한 클라이언트는 저절로 나타나고, 지운 것은 사라집니다. 여기서
추가하거나 설정할 것은 없고, 특정 업체 지원을 기다릴 필요도 없습니다.

아무것도 열지 않고 연결하고 끊습니다. 터널이 서 있는 동안에는 메뉴 막대 아이콘 모서리에 작은 점이 다른 표시들과 나란히 켜집니다. 무언가 지나가는 동안에는 초록, 터널은 켜져 있는데 아무것도 돌아오지 않으면 주황이 되어 조용히 죽은 연결이 멀쩡해 보이지 않습니다. 어느 줄인지는 패널이 표시합니다. 이름을 누르면 그 VPN의 창이 열리고, 창을
닫으면 Hop이 앱을 종료합니다. 연결은 유지됩니다 — 터널을 붙잡는 것은 앱이 아니라
시스템이니까요.

행에는 클라이언트가 스스로 알린 것만 나옵니다: 이름과, 괄호 안에 구성이 덧붙이는 것,
보통은 국가입니다. 서버 주소로 국가를 추측하지는 않습니다. 주소 등록부가 말해주는 것은
대역이 어디에 등록됐는지이지 장비가 어디 있는지가 아닙니다.

이 점은 설정에서 끌 수 있습니다. 모듈과 스위치는 그대로 동작합니다.

<div align="center">
<img src="https://hop.tools/screens/en/vpn.webp" width="420" alt="Hop — VPN 스위치">
</div>

### 앱

하루 종일 여는 프로그램을 격자에 모아 두면 응용 프로그램 폴더를 거치지 않고 한 번의 클릭으로 열립니다. + 를 눌러 고르거나 Finder에서
끌어다 놓으세요. 한 줄에 아홉 개, 최대 여덟 줄까지 들어갑니다.

아이콘을 끌어 자리를 바꿉니다. 노란 선이 어느 두 아이콘 사이에 놓일지 보여 주고 나머지는 홈 화면처럼 비켜섭니다. 편집 버튼을 누르면
아이콘이 흔들리고 각각 ✕ 가 생기며 격자에 이름을 붙일 수 있습니다. 앱을 눈으로 알아본다면 그 자리에서 아이콘 아래 이름을 끌 수도
있습니다. 격자는 얼마든지 만들 수 있습니다. 일은 한 공간에, 나머지는 다른 공간에, 각각 다른 앱을 담습니다.

격자는 모듈을 배치하는 곳에서 만들고 지웁니다. 설정에서도, 모듈 표 자체에서도 가능하며 표 안 칩의 ✕ 가 격자를 완전히 삭제합니다. 새
격자는 비어 있고 채우기 전까지 그렇다고 알려 줍니다.

<div align="center">
<img src="https://hop.tools/screens/en/apps.webp" width="420" alt="Hop — 앱 격자">
</div>

### 앱 삭제

앱을 이 줄에 끌어다 놓거나 설치된 목록에서 고르면, 서른 곳쯤에 남긴 것까지 함께 사라집니다: application support, 캐시, 환경설정, 컨테이너, launch agents, 플러그인, 설치 영수증 등. 목록의 각 앱에는 크기가 적혀 있습니다(본체와 데이터를 나눠서). 이미 휴지통에 있는 앱도 알아봅니다. 식별자는 휴지통 속 번들에서 읽거나, 그 이름을 담은 잔여물에서 추론합니다.

무엇도 즉시 삭제하지 않습니다. 전부 휴지통으로 가므로 실수의 대가는 복원 한 번이지 파일이 아니며, macOS가 내주지 않는 것은 조용히 건너뛰지 않고 이유와 함께 이름을 밝힙니다.

<div align="center">
<img src="https://hop.tools/screens/en/uninstall.webp" width="480" alt="Hop — 앱을 남긴 것까지 함께 삭제">
</div>

같은 모듈이 아무것도 지우지 않고 정리도 합니다: 캐시를 안고 있는 모든 앱을 큰 순서로, 다운로드·데스크탑·서류에 남은 설치 파일, 오래전에 지운 앱의 데이터, 그리고 휴지통과 그 크기. 체크 하나로 한 섹션 전체. 일부러 건드리지 않는 것도 함께 적힙니다 — 캐시와 데이터가 한 폴더에 있는 컨테이너, 어느 메신저의 이십여 기가바이트 같은 것. 어느 쪽을 버려도 되는지는 그 앱 자신만 알기 때문입니다.

<div align="center">
<img src="https://hop.tools/screens/en/clean.webp" width="480" alt="Hop — 캐시·설치 파일·잔여물·휴지통 정리">
</div>

## 22개 언어

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — 앱은 처음부터 시스템 언어를 그대로
따라갑니다.

## 프로젝트 응원하기

Hop은 무료이고 앞으로도 그렇습니다. 메뉴 막대의 한 자리를 얻었다면, 자발적인 후원이 새 기능을
내고 기존 기능을 다듬는 데 도움이 됩니다. 사는 것은 시간뿐입니다.

**[→ Hop 후원하기](https://web.tribute.tg/d/Nvk)**

## 개인정보 보호 — 그리고 권한을 안심하고 줘도 되는 이유

**Hop은 아무것도 수집하지 않습니다. 지금도, 나중에도.** 자체 서버도, 분석도, 텔레메트리도,
계정도, 크래시 리포트도 없습니다. 아래의 모든 권한은 그것이 필요한 기능을 실제로 쓸 때만
macOS가 묻고, 오직 그 기능을 위해 존재합니다. 곁다리로 무언가를 모으는 일은 없습니다.
믿어 달라고 할 필요도 없습니다. 앱은 오픈 소스이고, 수집할 코드 자체가 없습니다. 이 저장소에서
트래킹 SDK나 분석 호출을 찾아보세요. 없습니다.

모든 것이 로컬에서 동작합니다: 서버도, 분석 도구도, 계정도 없습니다.
앱이 네트워크에 접근하는 것은 업데이트를 확인할 때, 내장 속도 측정을
실행할 때, 그리고 — 토렌트 모듈을 켰다면 — 엔진을 한 번 받아 오고
토렌트 트래픽 자체를 주고받을 때뿐입니다. 업데이트 확인은 사용 중인
버전만 보내며, 사용자나 Mac을 식별하는 정보는 담기지 않습니다.
업데이트와 토렌트 엔진은 서명된 아카이브로 배포되며 설치 전에 Ed25519
서명으로 검증됩니다.

## 권한

Hop은 그 권한이 필요한 기능을 실제로 쓸 때만 권한을 요청하며, 앱의 정보 창에
모든 권한과 현재 상태가 정리되어 있습니다:

- **네트워크 — antonshakirov.com** — 업데이트 확인과 내려받기, 그리고 선택 도구
  두 가지(토렌트 엔진, 7-Zip 압축 도우미)
- **네트워크 — 토렌트, 속도 측정** — 토렌트 모듈이 켜져 있을 때 다른 피어와의
  트래픽. 속도 측정은 macOS의 networkQuality로 Apple 서버를 상대로 합니다
- **손쉬운 사용** — 아래 앱에 붙여넣기, 창 관리자, 키보드 잠금
- **화면 기록** — 텍스트 인식 모듈에만, 그것도 영역을 잡을 때만 해당합니다. 색상 스포이트에는
  필요 없습니다
- **알림** — 타이머 알림과 토렌트 완료 소식
- **관리자 암호** — 한 번, 덮개를 닫은 모드를 위해(pmset은 root 전용)
- **로그인 시 열기** — 직접 켜기 전에는 꺼져 있습니다

실행할 때는 아무것도 요청하지 않고, 켜지 않은 모듈을 위해 무언가를 묻지도 않습니다.
분석도, 텔레메트리도, 계정도, 크래시 리포트도 없습니다. antonshakirov.com에는 새 버전이 있는지
묻기 위해서만 접속하고, 동의하면 그것 또는 두 가지 선택적 도우미 중 하나를 내려받습니다.
나머지는 모두 이 Mac에 남습니다: 클립보드 기록, 기록한 시간, 할 일 목록, 인식한 텍스트, 집은 색.

위의 모든 권한은 기능이 동작하기 위한 것이며 그 밖의 목적은 없습니다. 믿어 달라고 할 필요도
없습니다. Hop은 오픈 소스이고, 무언가를 수집할 코드 자체가 없습니다 — 이 저장소에서 직접 읽어
보세요. 앱의 정보 창에는 «앱 권한» 탭이 있어 같은 목록과 각 권한의 현재 상태를 보여 줍니다.

웹사이트: [hop.tools](https://hop.tools)

## 무료인 이유

Hop은 완전히 무료입니다. 체험판도, 프로 버전도, 인앱 구매도 없습니다. 광고도, 데이터 수집도, 계정도 없어 수익화할 것도, 팔 것도 없습니다. 개인 프로젝트입니다. 제가 쓰려고 Hop을 만들어 매일 사용하고 있고, 그저 공유할 뿐입니다. 쓸모가 있다면 다른 사람에게도 알려 주세요. 그리고 힘을 보태고 싶다면, 이제 Hop을 후원하는 방법도 있습니다 — 그저 선물일 뿐, 대가는 아무것도 없습니다.

## 소스에서 빌드하기

Swift Package Manager, macOS 14+, 외부 의존성 없음:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

개발 워크플로, 릴리스 파이프라인, 동작 명세는
[docs/development.md](../development.md)와 [docs/spec.md](../spec.md)에
있습니다.

## 프로젝트 응원하기

세 가지 방법, 어느 것이든 반갑습니다:

- **[후원으로 Hop 돕기](https://web.tribute.tg/d/Nvk)** — 그대로 새 기능과 수정에
  들어갑니다. 자발적이고, 보상도 없고, 유료 기능도 없습니다. 모든 모듈은 모두에게 같습니다.
- **[저장소에 별 주기](https://github.com/antonyshakirov/hop/stargazers)** — 다른
  사람들은 별을 보고 찾아옵니다.
- **[이슈 남기기](https://github.com/antonyshakirov/hop/issues)** — 버그 신고나
  아이디어도 그만큼 값집니다.

## 만든 사람과 라이선스

[Anton Shakirov](https://www.antonshakirov.com/en)가 만들었습니다.
[MIT 라이선스](../../LICENSE)로 배포합니다: 자유롭게 사용하고 수정하되
저작권 고지는 남겨 주세요 — 이 앱을 자신의 작품인 것처럼 내세우는 것은
라이선스 위반입니다.
