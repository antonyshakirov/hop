<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ikona Hop — czteroramienna gwiazdka">

# Hop

**Malutki towarzysz na pasku menu macOS: timer, śledzenie czasu, lista
zadań, blokada uśpienia, monitor systemu, historia schowka, konwerter
plików, menedżer okien i lekki klient torrentów. Włączasz te, których
potrzebujesz, i rozkładasz je na maksymalnie czterech kartach na ikonie.
Jedno kliknięcie — i wszystko, czego potrzebujesz, jest pod ręką.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · **Polski** · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://hop.tools/screens/en/overview.webp" width="360" alt="Panel Hop — timer na pasku menu z wyświetlaczem matrycowym, presetami i cyklami pracy i odpoczynku">

</div>

Hop mieszka na pasku menu Twojego Maca i zastępuje garść drobnych
narzędzi: timer w stylu Pomodoro, śledzenie czasu z listą zadań, blokadę
uśpienia w duchu caffeinate, monitor systemu, menedżer schowka, konwerter
plików „przeciągnij i upuść", przyciąganie okien oraz lekki klient
torrentów — jedna lekka, natywna aplikacja, w której używane moduły
rozkładasz na maksymalnie czterech kartach na ikonie.

## Pobierz

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — otwórz i przeciągnij `Hop.app` do katalogu Aplikacje (zalecane)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — ta sama aplikacja jako zwykłe archiwum (używa go wbudowany aktualizator); zobacz [najnowsze wydanie](https://github.com/antonyshakirov/hop/releases/latest)
- Szybki mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Hop jest podpisany Apple Developer ID i notaryzowany przez Apple, więc macOS
otwiera go jak każdą inną aplikację. Kod źródłowy jest publiczny, a
wbudowane aktualizacje są weryfikowane podpisem Ed25519. Wymaga macOS 14 lub
nowszego.

## Funkcje

### Przestrzenie

Ikona mieści do czterech kart, a każdy moduł przeciągasz na wybraną kartę:
timer na jedną, monitor na drugą, rzadko używane na bok. Oko obok modułu
ukrywa go, nie przenosząc ani nie usuwając.

### Timer i cykle

Odliczanie na matrycy punktowej, które ustawiasz jednym gestem:
przeciągnij cyfry, wpisz czas jak na mikrofalówce albo wybierz preset.
Cykle pracy i odpoczynku (25/5 Pomodoro, 52/17, 90/15 — albo własne),
stoper, kieszeń, która przechowuje działający timer, gdy próbujesz
innego, oraz alert końcowy, który może przy okazji wstrzymać odtwarzane
media. Gdy odliczanie się kończy, rozlega się jeden dźwięk, a cyfry migają,
aż je wyzerujesz.

<div align="center">
<img src="https://hop.tools/screens/en/timer.webp" width="420" alt="Hop — Timer i cykle">
</div>

### Śledzenie czasu i zadania

Zadania można zebrać w projekty, każdy z własną sumą, a przełącznik nad listą
pokazuje dziś, tydzień albo całość. Trwające zadanie liczy bieżący odcinek, od
zera; ✓ obok zamyka odcinek, a w wierszu wraca suma za okres. Otwórz zadanie,
a zobaczysz wszystkie jego odcinki: zmienić długość albo moment, dopisać
sesję, której nikt nie mierzył, albo skasować wpis; poprawki ręczne są na tej
samej liście, więc wiersze sumują się do liczby nad nimi. Jeśli któreś działa
za długo, po ośmiu godzinach przypomni o tym baner. Obok jest osobna lista
rzeczy do zrobienia, w której ukończone spada na dół.

Kliknij zadanie, a wiersz się rozwinie: pełny tekst w pierwszej linii, opis
poniżej, gwiazdka dla ulubionych. Zadanie może mieć przypomnienie — dzień,
godzinę i dowolne dni tygodnia do powtarzania — a Hop da znać, gdy przyjdzie
pora: baner z «odłóż» i «gotowe», dźwięk, znak na pasku menu; każde włącza się
osobno.

**Zadania może dodawać także twój agent AI.** Lista to zwykły plik JSON, a Hop
odczytuje zmiany na bieżąco. Hop wykonuje też polecenia z pliku i rozumie linki
`hop://`: ten sam agent albo skrót zbudowany wokół takiego odnośnika może
uruchomić minutnik, dodać zadanie z przypomnieniem lub sprawdzić, co jest
uruchomione. Zobacz [docs/automation.md](../automation.md).

<div align="center">
<img src="https://hop.tools/screens/en/tracker.webp" width="420" alt="Hop — Śledzenie czasu i zadania">
</div>

### Blokada uśpienia

Nie pozwól Macowi zasnąć przez 15 minut, 8 godzin albo bez końca —
jedno kliknięcie, bez hasła. Opcjonalnie utrzymuj włączony ekran albo
pracuj dalej z zamkniętą pokrywą (przydatne przy pobieraniu, długich
buildach i zewnętrznych monitorach).

<div align="center">
<img src="https://hop.tools/screens/en/awake.webp" width="420" alt="Hop — Blokada uśpienia">
</div>

### Monitor systemu

Obciążenie i temperatura CPU i GPU, pamięć i swap, sieć, dysk, kondycja
baterii i pobór mocy — wartości na żywo z wykresami sparkline, progi kolorów,
które ustawiasz samodzielnie, °C/°F i linia czasu działania. Odczyty pochodzą
prosto z macOS i odświeżają się tylko wtedy, gdy karta jest otwarta. Wiersz
pamięci ostrzega także wtedy, gdy dużo pamięci trafiło na dysk, a nie tylko
gdy sam macOS zgłasza ciasnotę.

<div align="center">
<img src="https://hop.tools/screens/en/system.webp" width="420" alt="Hop — Monitor systemu">
</div>

### Historia schowka

Ostatnie 100 (do 300) skopiowanych rzeczy — tekst, obrazy i pliki — jedno
kliknięcie, by skopiować ponownie albo wkleić prosto do poprzedniej
aplikacji. Skopiowane pliki są pamiętane po nazwie (kilka naraz pokazuje
się jako „nazwa +N"), a wklejenie przywraca sam plik. Hasła i inne ukryte
dane wejściowe nigdy nie są zapisywane.

<div align="center">
<img src="https://hop.tools/screens/en/clipboard.webp" width="420" alt="Hop — Historia schowka">
</div>

### Konwerter plików

Upuść na panel paczkę obrazów, PDF-ów, wideo lub audio: na wyjściu JPEG, PNG,
HEIC, AVIF i WebP; kompresja PDF; zmniejszanie wideo w HEVC z uczciwym,
aktualizowanym na żywo szacunkiem rozmiaru jeszcze przed konwersją. Wszystko
jest przetwarzane lokalnie. Wideo można też przekadrować przy konwersji —
9:16, 4:5, kwadrat albo 16:9, z przycięciem, pasami lub na rozmytej kopii — a
kompresja ma własny poziom, więc obiecany rozmiar jest tym, który wychodzi.

Jeden przycisk ustawia klip pod to, dokąd trafi — reels, feed, tiktok, shorts
albo youtube — zapisując kadr, rozdzielczość i kompresję według zaleceń samej
platformy, a obok suwaka pokazuje wynikowy bitrate. MKV i WebM są najpierw
przepakowywane do MP4 (macOS nie otwiera żadnego) przez małego pomocnika,
który pobiera się raz. Dokumenty Pages, Numbers i Keynote eksportują partiami
same aplikacje: do PDF albo do docx, xlsx i pptx.

<div align="center">
<img src="https://hop.tools/screens/en/converter.webp" width="480" alt="Hop — Konwerter plików">
</div>

### Menedżer okien

Przyciągaj okna do połówek, ćwiartek, jednej trzeciej ekranu i na środek
kliknięciem w glif strefy albo skrótem ⌃⌥ — bez dodatkowej aplikacji.

<div align="center">
<img src="https://hop.tools/screens/en/windows.webp" width="420" alt="Hop — Menedżer okien">
</div>

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
<img src="https://hop.tools/screens/en/torrents.webp" width="420" alt="Torrenty Hop — lekki klient BitTorrent w panelu na pasku menu">
</div>

### Archiwa plików

Wiersz modułu otwiera okno i to w nim się upuszcza — ⌘V też działa, od razu z
kilkoma plikami. To, co dodasz, czeka na liście, dopóki nie naciśniesz
przycisku: archiwa są rozpakowywane, cała reszta trafia do jednego archiwum.
Wynik ląduje domyślnie na biurku, a można też obok oryginału albo w dowolnym
wybranym folderze. Obsługiwane są zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz i
gz; dla rar i 7z przy pierwszym spotkaniu pobiera się mały pomocnik (~6 MB) ze
sprawdzonym podpisem. Hop rozpakowuje rar, ale nigdy go nie tworzy — format jest
zastrzeżony. «Hop domyślnie dla archiwów» w ustawieniach oferuje tylko rar, gdy
nie obsługuje go aplikacja Apple, i może odebrać rar aplikacjom innych firm;
zip, 7z i formaty natywne zostają przy Narzędziu archiwizacji. Działa też przy
ukrytym module, a karta pokazuje prawdziwy stan. Podwójne kliknięcie archiwum w Finderze rozpakowuje je tuż obok pliku, we własnym niewielkim oknie postępu, a nieudana próba nie zostawia niczego ukrytego. Pliki, które otwiera Hop, mają własną ikonę z nazwą formatu, więc folder czyta się jednym spojrzeniem.

<div align="center">
<img src="https://hop.tools/screens/en/archives.webp" width="480" alt="Hop — Archiwa plików">
</div>

### Dokumenty

Konwerter nauczył się dokumentów: markdown → PDF składany przez sam Hop, pliki
Word (.docx, .doc, .rtf) → PDF albo markdown, a także tekst z PDF-a jako
markdown — zeskanowaną stronę czyta Vision od Apple. Natywnie i offline, bez
dołączonego pakietu biurowego i bez pobierania.

### Próbnik koloru

Pobierz lupą systemową dowolny kolor z ekranu — zostaje na liście, a w każdym
wierszu hex, rgb i hsl stoją we własnych kolumnach: klikasz jeden i ten zapis
się kopiuje. Kolejność nie zmienia się pod kursorem, ile kolorów przechowywać i
ile wierszy pokazywać ustawisz w ustawieniach, a uprawnienie do nagrywania
ekranu nie jest potrzebne: lupa zwraca jeden kolor i nic więcej.

<div align="center">
<img src="https://hop.tools/screens/en/colors.webp" width="420" alt="Hop — Próbnik koloru">
</div>

### Rozpoznawanie tekstu

Zaznacz obszar ekranu albo upuść obraz w oknie i wklej go przez ⌘V: tekst i
kody QR z niego pojawią się w oknie, w którym można je przeczytać, poprawić i
skopiować, a jednocześnie trafią do historii schowka. Złamania linii zostają,
więc tabela pozostaje czytelna. Rozpoznaje Vision od Apple, w całości na tym
Macu.

Jeśli w odczycie jest adres internetowy, pojawia się przycisk «otwórz link»:
link z kodu QR na rachunku otwiera się wprost w przeglądarce, bez sięgania po
telefon. Tylko adresy internetowe: zeskanowany kod to obce wejście, więc numer
telefonu, hasło Wi-Fi albo wizytówka zostają zwykłym tekstem.

<div align="center">
<img src="https://hop.tools/screens/en/recognition.webp" width="480" alt="Hop — Rozpoznawanie tekstu">
</div>

### Blokada klawiatury

Naciśnij 1, 5 albo 15 minut — lub ∞ — i cała klawiatura przestaje odpowiadać,
żeby dało się ją przetrzeć bez wyłączania Maca i zamykania pokrywy. Zasłona
tłumaczy, co się dzieje, a ikona na pasku menu zmienia się w klawiaturę. Wyjścia
są cztery: przycisk na zasłonie, przycisk w panelu, samo otwarcie panelu albo
przytrzymanie esc + shift przez pięć sekund. Krótkie naciśnięcie przycisku zasilania
też jest połykane; przytrzymanie nadal wyłącza Maca, bo robi to sprzęt.

<div align="center">
<img src="https://hop.tools/screens/en/keyboard.webp" width="480" alt="Hop — Blokada klawiatury">
</div>

### Test prędkości

Jedno dotknięcie mierzy łącze narzędziem samego macOS (networkQuality, serwery Apple) — pobieranie, wysyłanie i responsywność, a ostatni wynik zostaje w wierszu.

<div align="center">
<img src="https://hop.tools/screens/en/speed.webp" width="420" alt="Hop — Test prędkości">
</div>

### Ikona na pasku menu

Na ikonie siedzą małe znaczniki: biegnący czas, blokada uśpienia, przypomnienie, które
zadzwoniło, kropka, gdy VPN jest podniesiony (pomarańczowa, gdy nic już nie
przechodzi), i strzałki, gdy idą torrenty — kolorowe albo monochromatyczne, każdy da
się wyłączyć. Własne okna Hopa pojawiają się w Docku, dopóki są otwarte, więc
kliknięcie przywraca okno zamiast otwierać panel, a z ostatnim oknem znika też ikona.

### Motywy, skróty i tryb awaryjny

Ciemny i jasny motyw z fakturą ziarna filmowego, skróty globalne, uruchamianie przy logowaniu i tryb awaryjny, który wyciąga aplikację z pętli awarii — wszystko w jednym oknie ustawień.

<div align="center">
<img src="https://hop.tools/screens/en/settings.webp" width="480" alt="Hop — Ustawienia">
</div>

### VPN

Wszystkie VPN, które zna twój Mac, każdy z własnym przełącznikiem, czyjkolwiek by
był. Hop czyta listę prosto z ustawień systemowych: klient zainstalowany wczoraj
pojawia się sam, usunięty znika. Nie ma tu nic do dodawania ani konfigurowania.

Włączaj i wyłączaj tunel, nie otwierając niczego. Dopóki stoi, w rogu ikony na pasku
menu świeci mała kropka, obok pozostałych wskaźników: zielona, dopóki coś przechodzi,
pomarańczowa, gdy tunel jest włączony, ale nic przez niego nie wraca. Cicho zmarłe
połączenie przestaje wyglądać na sprawne, a panel pokazuje, o który wiersz chodzi.
Kliknij nazwę, a otworzy się okno samego VPN; gdy je zamkniesz, Hop zamknie aplikację.
Połączenie zostaje: tunel trzyma system, nie aplikacja.

W wierszu widać to, co zgłasza sam klient: nazwę i w nawiasie to, co dodaje
konfiguracja, zwykle kraj. Hop nie zgaduje kraju z adresu serwera: rejestr mówi,
gdzie zakres jest zarejestrowany, a nie gdzie stoi maszyna.

Kropkę można wyłączyć w ustawieniach — moduł i jego przełączniki działają i bez niej.

<div align="center">
<img src="https://hop.tools/screens/en/vpn.webp" width="420" alt="Hop — Przełączniki VPN">
</div>

### Aplikacje

Siatka programów, które otwierasz przez cały dzień — jednym kliknięciem, bez
wyprawy do folderu z aplikacjami. Naciśnij + i wybierz je albo przeciągnij z
Findera; w rzędzie mieści się dziewięć, rzędów może być do ośmiu.

Przeciągnij ikonę, żeby ją przestawić: żółta linia pokazuje, między którymi
ikonami wyląduje, a reszta rozsuwa się jak na ekranie głównym. Przycisk edycji
włącza kołysanie, każda ikona dostaje ✕, a siatce można nadać własną nazwę; tam
też wyłącza się podpisy pod ikonami, jeśli rozpoznajesz aplikacje z wyglądu.
Siatek możesz mieć dowolnie wiele — praca na jednej przestrzeni, reszta na
drugiej — każda ma swoje aplikacje.

Siatki powstają i znikają tam, gdzie układasz moduły: w ustawieniach albo w
samej tabeli modułów, gdzie ✕ na chipie siatki usuwa ją na dobre. Nowa siatka
zaczyna pusta i tak o sobie pisze, dopóki jej nie wypełnisz.

<div align="center">
<img src="https://hop.tools/screens/en/apps.webp" width="420" alt="Hop — Siatka aplikacji">
</div>

### Usuwanie aplikacji

Upuść aplikację na wiersz albo wybierz ją z listy wszystkiego, co zainstalowane — zniknie razem z tym, co zostawiła w jakichś trzydziestu miejscach: application support, pamięci podręczne, preferencje, kontenery, launch agents, wtyczki, kwity instalacji i reszta. Każda aplikacja na liście pokazuje, ile waży: pakiet i dane osobno. Aplikacja leżąca już w koszu też zostanie rozpoznana: identyfikator pochodzi z pakietu w koszu albo wynika z pozostałości, które go nazywają.

Nic nie jest kasowane. Wszystko trafia do kosza, więc pomyłka kosztuje przywrócenie, a nie plik, a czego macOS nie oddaje, jest nazwane z powodem, a nie po cichu pominięte.

<div align="center">
<img src="https://hop.tools/screens/en/uninstall.webp" width="480" alt="Hop — Usunięcie aplikacji ze wszystkim, co zostawiła">
</div>

Ten sam moduł sprząta, nic nie usuwając: każda aplikacja z pamięcią podręczną, największe na górze; instalatory w Pobranych, na Biurku i w Dokumentach; dane aplikacji usuniętych lata temu; i kosz wraz z rozmiarem. Jeden ptaszek bierze całą sekcję. Czego celowo nie rusza, też jest wypisane — kontener, w którym cache leży razem z danymi, choćby dwadzieścia gigabajtów komunikatora: co z tego można wyrzucić, wie tylko sama aplikacja.

<div align="center">
<img src="https://hop.tools/screens/en/clean.webp" width="480" alt="Hop — Czyszczenie cache, instalatorów, pozostałości i kosza">
</div>

## 22 języki

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — aplikacja od razu podąża za językiem
Twojego systemu.

## Wesprzyj projekt

Hop jest darmowy i taki zostanie. Jeśli zasłużył na miejsce na twoim pasku menu,
dobrowolne wsparcie pomaga wypuszczać nowe funkcje i dopracowywać te, które już
są — płaci za czas, i tylko za to.

**[→ Wesprzyj Hopa](https://web.tribute.tg/d/Nvk)**

## Prywatność — i dlaczego uprawnienia można spokojnie dać

**Hop nie zbiera niczego. Ani teraz, ani później.** Brak własnego serwera, brak
analityki, brak telemetrii, brak kont, brak raportów awarii. O każde uprawnienie
poniżej macOS pyta dopiero wtedy, gdy naprawdę używasz funkcji, która go
potrzebuje, i istnieje ono właśnie po to, żeby ta funkcja działała — przy okazji
nic nie jest zbierane. Nie musisz w to wierzyć: aplikacja jest open source, a
kodu, który miałby cokolwiek zbierać, po prostu nie ma. Poszukaj w tym
repozytorium SDK do śledzenia albo wywołania analityki — nie znajdziesz.

Wszystko działa lokalnie: bez serwera, bez analityki, bez kont.
Aplikacja łączy się z siecią tylko po to, by sprawdzić aktualizacje,
gdy uruchamiasz wbudowany test prędkości, oraz — jeśli włączysz moduł
torrentów — by raz pobrać silnik i przesyłać sam ruch torrentowy.
Sprawdzanie aktualizacji wysyła używaną wersję i nic, co identyfikowałoby
Ciebie lub Twojego Maca. Aktualizacje i silnik torrentowy są dostarczane
jako podpisane archiwa i przed instalacją weryfikowane podpisem Ed25519.

## Uprawnienia

Hop prosi o uprawnienie dopiero wtedy, gdy naprawdę używasz funkcji, która go
potrzebuje; okno ustawień wymienia je wszystkie z bieżącym stanem:

- **sieć — antonshakirov.com** — sprawdzanie i pobieranie aktualizacji oraz dwa
  opcjonalne pomocniki (silnik torrentów i archiwizator 7-Zip)
- **sieć — torrenty, test prędkości** — ruch do innych użytkowników przy włączonym
  module torrentów; test używa systemowego networkQuality wobec serwerów Apple
- **dostępność** — wklejanie do aplikacji pod spodem, menedżer okien i blokada
  klawiatury
- **nagrywanie ekranu** — tylko moduł rozpoznawania tekstu i tylko przy
  zaznaczaniu obszaru; próbnik koloru go nie potrzebuje
- **powiadomienia** — alarm minutnika i ukończony torrent
- **hasło administratora** — raz, dla trybu zamkniętej klapy (pmset działa tylko
  jako root)
- **otwieraj przy logowaniu** — wyłączone, dopóki sam nie włączysz

Przy starcie nie jest proszone o nic, i nic nie jest proszone dla modułu, którego
nie włączyłeś. Bez analityki, bez telemetrii, bez kont, bez raportów awarii: z
antonshakirov.com aplikacja łączy się tylko po to, by zapytać, czy jest nowsza
wersja — i pobrać ją albo jednego z dwóch opcjonalnych pomocników, jeśli się
zgodzisz. Cała reszta zostaje na tym Macu: historia schowka, zmierzony czas,
lista zadań, rozpoznany tekst i pobrane kolory.

Każde uprawnienie powyżej jest po to, żeby funkcja działała — i po nic więcej.
Nie musisz w to wierzyć: Hop jest open source, a kodu, który miałby cokolwiek
zbierać, po prostu nie ma — przeczytaj go w tym repozytorium. Okno ustawień
aplikacji ma sekcję «uprawnienia aplikacji» z tą samą listą i aktualnym stanem
każdego z nich.

Strona: [hop.tools](https://hop.tools)

## Za darmo — i dlaczego

Hop jest całkowicie darmowy: bez okresu próbnego, bez wersji pro, bez zakupów w
aplikacji. Bez reklam, bez zbierania danych, bez kont — nie ma czego
monetyzować ani czego sprzedawać. To projekt osobisty: zrobiłem Hopa dla
siebie, używam go codziennie i po prostu się nim dzielę. Jeśli się przyda,
przekaż go dalej. A jeśli chcesz się dołożyć, jest teraz sposób, by wesprzeć
Hopa — po prostu prezent, bez niczego w zamian.

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

Trzy sposoby, każdy mile widziany:

- **[Wesprzyj Hopa wpłatą](https://web.tribute.tg/d/Nvk)** — idzie prosto w nowe
  funkcje i poprawki. Dobrowolnie, bez nagród, bez niczego za opłatą: każdy moduł
  jest taki sam dla wszystkich.
- **[Daj repo gwiazdkę](https://github.com/antonyshakirov/hop/stargazers)** — to
  po gwiazdkach znajdują go inni.
- **[Otwórz issue](https://github.com/antonyshakirov/hop/issues)** — zgłoszenie
  błędu albo pomysł są warte tyle samo.

## Autor i licencja

Stworzone przez [Antona Shakirova](https://www.antonshakirov.com/en).
Wydane na [licencji MIT](../../LICENSE): używaj i modyfikuj swobodnie,
zachowując informację o prawach autorskich — podawanie aplikacji za
własną pracę to naruszenie licencji.
