<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ikona Hop — czteroramienna gwiazdka">

# Hop

**Malutki towarzysz na pasku menu macOS: timer, blokada uśpienia,
monitor systemu, historia schowka, konwerter plików, menedżer okien i
lekki klient torrentów. Jedno kliknięcie — i wszystko, czego
potrzebujesz, jest pod ręką.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · **Polski** · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="Panel Hop — timer na pasku menu z wyświetlaczem matrycowym, presetami i cyklami pracy i odpoczynku">

</div>

Hop mieszka na pasku menu Twojego Maca i zastępuje pół tuzina drobnych
narzędzi: timer w stylu Pomodoro, blokadę uśpienia w duchu caffeinate,
monitor systemu, menedżer schowka, konwerter plików „przeciągnij i
upuść", przyciąganie okien oraz lekki klient torrentów — jedna lekka,
natywna aplikacja zamiast siedmiu.

## Pobierz

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — otwórz i przeciągnij `Hop.app` do katalogu Aplikacje (zalecane)
- `Hop-x.y.z.zip` — ta sama aplikacja jako zwykłe archiwum (używa go wbudowany aktualizator); zobacz [najnowsze wydanie](https://github.com/antonyshakirov/hop/releases/latest)
- Szybki mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Pierwsze uruchomienie: kliknij `Hop.app` prawym przyciskiem → **Otwórz**
→ potwierdź (aplikacja nie jest jeszcze notaryzowana). Wymaga macOS 14
lub nowszego.

## Funkcje

### Timer i cykle

Odliczanie na matrycy punktowej, które ustawiasz jednym gestem:
przeciągnij cyfry, wpisz czas jak na mikrofalówce albo wybierz preset.
Cykle pracy i odpoczynku (25/5 Pomodoro, 52/17, 90/15 — albo własne),
stoper, kieszeń, która przechowuje działający timer, gdy próbujesz
innego, oraz alert końcowy, który może przy okazji wstrzymać odtwarzane
media.

### Blokada uśpienia

Nie pozwól Macowi zasnąć przez 15 minut, 8 godzin albo bez końca —
jedno kliknięcie, bez hasła. Opcjonalnie utrzymuj włączony ekran albo
pracuj dalej z zamkniętą pokrywą (przydatne przy pobieraniu, długich
buildach i zewnętrznych monitorach).

### Monitor systemu

Obciążenie i temperatura CPU i GPU, pamięć i swap, sieć, dysk, kondycja
baterii i pobór mocy — wartości na żywo z wykresami sparkline, progi
kolorów, które ustawiasz samodzielnie, °C/°F i linia czasu działania.
Odczyty pochodzą prosto z macOS i odświeżają się tylko wtedy, gdy karta
jest otwarta.

### Historia schowka

Ostatnie 100 (do 300) skopiowanych rzeczy — tekst i obrazy — jedno kliknięcie, by
skopiować ponownie albo wkleić prosto do poprzedniej aplikacji. Hasła i
inne ukryte dane wejściowe nigdy nie są zapisywane.

### Konwerter plików

Upuść na panel paczkę obrazów, PDF-ów, wideo lub audio: na wyjściu JPEG,
PNG, HEIC, AVIF i WebP; kompresja PDF; zmniejszanie wideo w HEVC z
uczciwym, aktualizowanym na żywo szacunkiem rozmiaru jeszcze przed
konwersją. Wszystko jest przetwarzane lokalnie.

### Menedżer okien

Przyciągaj okna do połówek, ćwiartek, jednej trzeciej ekranu i na środek
kliknięciem w glif strefy albo skrótem ⌃⌥ — bez dodatkowej aplikacji.

### Torrenty

Lekki klient BitTorrent w tym samym panelu: upuść plik .torrent albo
wklej link magnet, wybierz dokładnie, które pliki pobrać — przed
pobieraniem albo nawet w jego trakcie — wstrzymuj, wznawiaj i seeduj,
z opcjonalnym zatrzymaniem przy ratio 1.0. Moduł jest domyślnie
wyłączony; po włączeniu silnik open source jest pobierany osobno jako
niewielki pakiet (~26 MB, z weryfikacją podpisu) i komunikuje się z
Hopem wyłącznie przez lokalny port. Hop może też zostać domyślną
aplikacją dla plików .torrent i linków magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Torrenty Hop — lekki klient BitTorrent w panelu na pasku menu">
</div>

### I cała reszta

Wbudowany test prędkości (networkQuality od Apple), ciemny i jasny motyw
z teksturą filmowego ziarna, globalne skróty klawiszowe, uruchamianie
przy logowaniu oraz tryb awaryjny, który wyciąga aplikację z pętli
awarii.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Monitor systemu Hop — wykresy CPU, GPU, pamięci, sieci, dysku i baterii">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Konwerter plików Hop — wsadowa konwersja obrazów, PDF, wideo i audio">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Ustawienia Hop — motywy, moduły, skróty klawiszowe, 18 języków">
</div>

## 18 języków

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — aplikacja od razu podąża za językiem
Twojego systemu.

## Prywatność

Wszystko działa lokalnie: bez serwera, bez analityki, bez kont.
Aplikacja łączy się z siecią tylko po to, by sprawdzić aktualizacje,
gdy uruchamiasz wbudowany test prędkości, oraz — jeśli włączysz moduł
torrentów — by raz pobrać silnik i przesyłać sam ruch torrentowy.
Aktualizacje i silnik torrentowy są dostarczane jako podpisane archiwa
i przed instalacją weryfikowane podpisem Ed25519.

Strona: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Za darmo — i dlaczego

Hop jest całkowicie darmowy: bez okresu próbnego, bez wersji pro, bez zakupów w
aplikacji. Bez reklam, bez zbierania danych, bez kont — nie ma czego
monetyzować ani czego sprzedawać. To projekt osobisty: zrobiłem Hopa dla
siebie, używam go codziennie i po prostu się nim dzielę. Jeśli się przyda,
przekaż go dalej.

## Budowanie ze źródeł

Swift Package Manager, macOS 14+, bez zewnętrznych zależności:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Proces developerski, pipeline wydań i specyfikacja zachowania znajdują
się w [docs/development.md](../development.md) i
[docs/spec.md](../spec.md).

## Wesprzyj projekt

Jeśli Hop oszczędza Ci kliknięcie czy dwa, **[zostaw repozytorium gwiazdkę](https://github.com/antonyshakirov/hop/stargazers)** —
to dzięki gwiazdkom znajdują je inni. Zgłoszenia błędów i pomysły na
funkcje są mile widziane w [Issues](https://github.com/antonyshakirov/hop/issues).

## Autor i licencja

Stworzone przez [Antona Shakirova](https://www.antonshakirov.com/en).
Wydane na [licencji MIT](../../LICENSE): używaj i modyfikuj swobodnie,
zachowując informację o prawach autorskich — podawanie aplikacji za
własną pracę to naruszenie licencji.
