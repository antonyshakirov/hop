<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop-App-Icon — Asterisk aus vier Linien">

# Hop

**Ein winziger Menüleisten-Begleiter für macOS: Timer, Zeiterfassung,
Aufgabenliste, Wachhalten, Systemmonitor, Zwischenablage-Verlauf,
Dateikonverter, Fenstermanager und ein leichter Torrent-Client — verteilt auf
bis zu vier Tabs am Symbol. Ein Klick — und alles, was du brauchst, ist sofort
zur Hand.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · **Deutsch** · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/de/overview.png" width="360" alt="Hop-Panel — Menüleisten-Timer mit Punktmatrix-Anzeige, Presets und Arbeits-Pausen-Zyklen">

</div>

Hop lebt in der Menüleiste deines Mac und ersetzt eine Handvoll kleiner
Utilities: einen Timer im Pomodoro-Stil, eine Zeiterfassung mit Aufgabenliste,
einen Schlafblocker à la caffeinate, einen Systemmonitor, einen
Zwischenablage-Manager, einen Drag-and-drop-Dateikonverter, einen
Fenster-Snapper und einen leichten Torrent-Client — eine leichtgewichtige
native App, deren Module du auf bis zu vier Tabs am Symbol verteilst.

## Download

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — öffnen und `Hop.app` in den Programme-Ordner ziehen (empfohlen)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — dieselbe App als einfaches Archiv (wird vom eingebauten Updater verwendet); siehe das [neueste Release](https://github.com/antonyshakirov/hop/releases/latest)
- Schneller Mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Erster Start unter macOS 15 oder neuer: Versuche Hop einmal zu öffnen.
Gehe dann zu **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch
öffnen** und bestätige **Öffnen**. Hop ist nicht notarisiert, weil dem Autor
keine Mitgliedschaft im Apple Developer Program zur Verfügung steht. Der
Quellcode ist öffentlich, und integrierte Updates werden mit Ed25519
verifiziert. Benötigt macOS 14 oder neuer.

## Funktionen

### Bereiche

Das Symbol fasst bis zu vier Tabs, und du ziehst jedes Modul in den Tab
deiner Wahl — den Timer auf den einen, den Monitor auf den anderen, selten
Genutztes zur Seite. Ein Regal „inaktiv“ bewahrt Beiseitegelegtes auf, ohne
es zu löschen.

### Timer & Zyklen

Ein Punktmatrix-Countdown, den du mit einer einzigen Geste stellst: Ziffern
ziehen, die Zeit wie an einer Mikrowelle eintippen oder ein Preset wählen.
Arbeits-Pausen-Zyklen (25/5 Pomodoro, 52/17, 90/15 — oder deine eigenen), eine
Stoppuhr, ein Stash, der einen laufenden Timer aufbewahrt, während du einen
anderen ausprobierst, und ein Endalarm, der auf Wunsch auch deine Medien
pausiert. Läuft der Countdown ab, ertönt ein einzelner Ton und die Ziffern
pulsieren, bis du zurücksetzt.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/timer.png" width="420" alt="Hop — Timer & Zyklen">
</div>

### Zeiterfassung & To-dos

Erfasse Zeit über eine flache Aufgabenliste — jede Zeile zeigt die heutige
Zeit und eine laufende Gesamtsumme, und den heutigen Wert kannst du von Hand
korrigieren. Läuft eine zu lange, erinnert dich nach acht Stunden ein Banner.
Daneben liegt eine eigene To-do-Liste, in der Erledigtes nach unten wandert.

Klicken Sie eine Aufgabe an, und die Zeile klappt auf: der ganze Text in der
ersten Zeile, darunter eine Beschreibung, ein Stern für Favoriten. Ein To-do
kann eine Erinnerung tragen — Tag, Uhrzeit und beliebige Wochentage zum
Wiederholen —, und Hop meldet sich: Banner mit „später“ und „erledigt“, Ton,
Zeichen in der Menüleiste, jedes einzeln abschaltbar.

**Auch Ihr KI-Agent kann Aufgaben anlegen.** Die Liste ist eine schlichte
JSON-Datei, und Hop übernimmt Änderungen im laufenden Betrieb. Hop führt zudem
Befehle aus einer Datei aus und versteht `hop://`-Links — derselbe Agent oder ein
Kurzbefehl um so einen Link herum kann einen Timer starten, eine Aufgabe mit
Erinnerung anlegen oder abfragen, was gerade läuft. Siehe
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/tracker.png" width="420" alt="Hop — Zeiterfassung & To-dos">
</div>

### Kein Schlaf

Halte den Mac 15 Minuten, 8 Stunden oder für immer wach — ein Klick, kein
Passwort. Optional bleibt das Display an, oder du arbeitest bei geschlossenem
Deckel weiter (praktisch für Downloads, lange Builds und externe Displays).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/awake.png" width="420" alt="Hop — Kein Schlaf">
</div>

### Systemmonitor

CPU- und GPU-Last samt Temperatur, Speicher und Swap, Netzwerk, Festplatte,
Batteriezustand und Leistungsaufnahme — Live-Werte mit Sparkline-Diagrammen,
Farbschwellen, die du selbst festlegst, °C/°F und einer Uptime-Zeile. Die
Messwerte kommen direkt von macOS und aktualisieren sich nur, solange der Tab
geöffnet ist. Die speicherzeile warnt auch, wenn viel speicher auf der platte
gelandet ist, und nicht erst, wenn macOS selbst knappheit meldet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/system.png" width="420" alt="Hop — Systemmonitor">
</div>

### Zwischenablage-Verlauf

Die letzten 100 (bis zu 300) kopierten Einträge — Text, Bilder und Dateien —
ein Klick zum erneuten Kopieren oder zum direkten Einfügen in die vorherige
App. Kopierte Dateien werden mit Namen gemerkt (mehrere zeigen sich als
„Name +N“), und beim Einfügen kommt die eigentliche Datei zurück. Passwörter
und andere verdeckte Eingaben werden niemals gespeichert.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/clipboard.png" width="420" alt="Hop — Zwischenablage-Verlauf">
</div>

### Dateikonverter

Zieh einen Stapel Bilder, PDFs, Videos oder Audiodateien auf das Panel: JPEG,
PNG, HEIC, AVIF und WebP als Ausgabe; PDF-Komprimierung; HEVC-
Videoverkleinerung mit einer ehrlichen Live-Größenschätzung, bevor du
konvertierst. Alles wird lokal verarbeitet. Video lässt sich beim Konvertieren
auch neu rahmen — 9:16, 4:5, Quadrat oder 16:9, beschnitten, mit Balken oder
auf einer unscharfen Kopie —, und die Komprimierung hat eine eigene Stufe,
sodass die vorher genannte Größe auch die tatsächliche ist.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/converter.png" width="480" alt="Hop — Dateikonverter">
</div>

### Fenstermanager

Fenster mit einem Klick auf ein Zonensymbol oder per ⌃⌥-Hotkey auf Hälften,
Viertel, Drittel und die Mitte einrasten — ganz ohne zusätzliche App.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/windows.png" width="420" alt="Hop — Fenstermanager">
</div>

### Torrents

Ein leichter BitTorrent-Client im selben Panel: Zieh eine .torrent-Datei
hinein oder füge einen magnet-Link ein, wähle genau die Dateien aus, die du
laden willst — vor oder sogar während des Downloads —, pausiere, setze fort
und seede, auf Wunsch mit automatischem Stopp bei Ratio 1.0. Das Modul ist
standardmäßig deaktiviert; beim Aktivieren wird die Open-Source-Engine als
kleiner separater Download (~26 MB, signaturgeprüft) geholt, die nur über
einen lokalen Port mit Hop spricht. Hop kann außerdem zur Standard-App für
.torrent-Dateien und magnet-Links werden.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/torrents.png" width="420" alt="Hop-Torrents — leichter BitTorrent-Client im Menüleisten-Panel">
</div>

### Dateiarchive

Die Zeile des Moduls öffnet ein Fenster, und dort wird abgelegt — ⌘V geht auch,
mehrere Dateien auf einmal. Was du hinzufügst, wartet in einer Liste, bis du auf
den Knopf drückst: Archive werden entpackt, alles andere wird zu einem Archiv.
Das Ergebnis landet standardmäßig auf dem Schreibtisch, wahlweise neben dem
Original oder in einem eigenen Ordner. Unterstützt sind zip, rar, 7z, tar,
tar.gz, tar.bz2, tar.xz und gz; für rar und 7z lädt beim ersten Mal ein kleiner,
signaturgeprüfter Helfer (~6 MB). Hop entpackt rar, erstellt es aber nie — das
Format ist proprietär. «Hop als Standard für Archive» in den Einstellungen
bietet nur rar an, solange keine Apple-App zuständig ist, und kann rar von
Fremd-Apps zurückholen; zip, 7z und die nativen Formate bleiben beim
Archivierungsprogramm. Es funktioniert auch mit verstecktem Modul, und die Karte
zeigt den echten Stand. Ein Doppelklick auf ein Archiv im Finder entpackt es direkt neben der Datei, in einem eigenen kleinen Fortschrittsfenster, und ein fehlgeschlagener Lauf lässt nichts Verstecktes zurück. Dateien, die Hop öffnet, tragen ein eigenes Symbol mit dem Format darauf, sodass ein Ordner davon auf einen Blick lesbar ist.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/archives.png" width="480" alt="Hop — Dateiarchive">
</div>

### Dokumente

Der Konverter kann jetzt Dokumente: markdown → PDF, von Hop selbst gesetzt,
Word-Dateien (.docx, .doc, .rtf) → PDF oder markdown, und der Text eines PDFs
als markdown — eine gescannte Seite liest Apples Vision. Nativ und offline,
ohne mitgeliefertes Office-Paket und ohne Download.

### Farbpipette

Nimm mit der Systemlupe jede Farbe vom Bildschirm auf: sie bleibt in einer
Liste, jede Zeile mit hex, rgb und hsl in eigener Spalte — ein Klick kopiert
genau diese Schreibweise. Die Reihenfolge ändert sich nie unter dem Zeiger,
Listenlänge und sichtbare Zeilen sind einstellbar, und eine Berechtigung für
Bildschirmaufnahmen braucht es nicht: die Lupe liefert genau eine Farbe.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/colors.png" width="420" alt="Hop — Farbpipette">
</div>

### Texterkennung

Rahme einen Bereich des Bildschirms ein oder zieh ein Bild ins Fenster und füge
eines mit ⌘V ein: Text und QR-Codes darin erscheinen in einem Fenster, das man
lesen, bearbeiten und daraus kopieren kann, und landen zugleich im Verlauf der
Zwischenablage. Zeilenumbrüche bleiben, eine Tabelle bleibt lesbar. Erkannt
wird mit Apples Vision, komplett auf diesem Mac.

Enthält ein Ergebnis eine Web-Adresse, erscheint die Schaltfläche «Link
öffnen»: der Link aus einem QR-Code auf einer Rechnung öffnet sich direkt im
Browser, ganz ohne Telefon. Nur Web-Adressen: ein gescannter Code ist fremde
Eingabe, deshalb bleiben Telefonnummer, WLAN-Passwort oder Visitenkarte
einfacher Text.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/recognition.png" width="480" alt="Hop — Texterkennung">
</div>

### Tastatursperre

Tippe 1, 5 oder 15 Minuten — oder ∞ — und die ganze Tastatur reagiert nicht
mehr, zum Abwischen, ohne den Mac herunterzufahren oder den Deckel zu
schließen. Eine Abdeckung erklärt, was los ist, und das Menüleisten-Symbol wird
zur Tastatur. Vier Wege hinaus: der Knopf auf der Abdeckung, der Knopf im
Panel, das Öffnen des Panels oder esc + shift fünf Sekunden halten. Ein kurzer Druck
auf die Ein-/Aus-Taste wird ebenfalls geschluckt; langes Halten schaltet den
Mac weiterhin aus, denn das macht die Hardware.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/keyboard.png" width="480" alt="Hop — Tastatursperre">
</div>

### Geschwindigkeitstest

Ein Tippen misst die Verbindung mit macOS' eigenem networkQuality gegen Apples Server — Download, Upload und Reaktionszeit, das letzte Ergebnis bleibt in der Zeile stehen.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/speed.png" width="420" alt="Hop — Geschwindigkeitstest">
</div>

### Das Symbol in der Menüleiste

Auf dem Symbol sitzen kleine Marken: die laufende Zeit, der Schlafschutz, eine
ausgelöste Erinnerung, ein Punkt solange ein VPN steht (orange, wenn nichts mehr
durchkommt), und Pfeile solange Torrents laufen — farbig oder monochrom, jede einzeln
abschaltbar. Hops eigene Fenster erscheinen im Dock, solange sie offen sind, ein Klick
holt eines zurück statt das Panel zu öffnen, und mit dem letzten Fenster verschwindet
das Symbol wieder.

### Themes, Kurzbefehle und der abgesicherte Modus

Dunkles und helles Theme mit Filmkorn-Textur, globale Kurzbefehle, Start bei der Anmeldung und ein abgesicherter Modus, der die App aus einer Absturzschleife holt — alles in einem Einstellungsfenster.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/settings.png" width="480" alt="Hop — Einstellungen">
</div>

### VPN

Jedes VPN, das Ihr Mac kennt, mit je einem Schalter — von welchem Anbieter auch
immer. Hop liest die Liste direkt aus den Systemeinstellungen: ein gestern
installierter Client erscheint von selbst, ein entfernter verschwindet. Hier gibt
es nichts hinzuzufügen und auf Unterstützung für einen bestimmten Anbieter muss
niemand warten.

Schalten Sie einen Tunnel ein und aus, ohne etwas zu öffnen. Solange einer steht,
sitzt ein kleiner Punkt in der Ecke des Menüleisten-Symbols, neben den übrigen
Anzeigen — sichtbar auch bei geschlossenem Panel: grün, solange etwas durchgeht,
orange, wenn der Tunnel an ist, aber nichts zurückkommt. Eine still gestorbene
Verbindung sieht damit nicht mehr nach einer funktionierenden aus, und das Panel
zeigt, welche Zeile gemeint ist. Ein Klick auf den Namen öffnet das Fenster des VPN
selbst, wenn Sie es brauchen; schließen Sie es, beendet Hop die App wieder. Die
Verbindung bleibt: den Tunnel hält das System, nicht die App.

In der Zeile steht, was der Client selbst meldet — sein Name und in Klammern, was
die Konfiguration hinzufügt, meist das Land. Aus der Serveradresse rät Hop das
Land nicht: das Adressregister sagt, wo ein Bereich registriert ist, nicht wo die
Maschine steht.

Der Punkt lässt sich in den Einstellungen abschalten — das Modul und seine Schalter arbeiten auch ohne ihn.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/vpn.png" width="420" alt="Hop — VPN-Schalter">
</div>

### Programme

Ein Raster mit den Apps, die Sie den ganzen Tag öffnen — einen Klick entfernt,
ohne Umweg über den Programme-Ordner. Auf + drücken und auswählen oder aus dem
Finder hineinziehen; neun passen nebeneinander, bis zu acht Reihen.

Ziehen Sie ein Symbol, um es zu verschieben: eine gelbe Linie zeigt, zwischen
welche Symbole es rutscht, die übrigen rücken auf wie auf einem Home-Bildschirm.
Die Bearbeiten-Taste startet das Wackeln, jedes Symbol bekommt ein ✕, und das
Raster kann einen eigenen Namen bekommen; dort lassen sich auch die Namen unter
den Symbolen abschalten, wenn Sie Ihre Apps ohnehin erkennen. Sie können
beliebig viele Raster anlegen — Arbeit auf einer Fläche, alles andere auf einer
zweiten — jedes mit eigenen Apps.

Raster entstehen und verschwinden dort, wo Sie die Module anordnen: in den
Einstellungen oder in der Modultabelle selbst, wo das ✕ am Chip eines Rasters es
endgültig löscht. Ein neues Raster ist leer und sagt das auch, bis Sie es
füllen.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/apps.png" width="420" alt="Hop — App-Raster">
</div>

### Apps entfernen

Leg eine App auf die Zeile oder wähle sie aus der Liste aller installierten — sie geht mitsamt allem, was sie an rund dreißig Stellen hinterlassen hat: application support, Caches, Einstellungen, Container, Launch Agents, Plug-ins, Quittungen und der Rest. Jede App in der Liste zeigt ihr Gewicht, Bundle und Daten getrennt. Eine App, die schon im Papierkorb liegt, wird trotzdem erkannt: die Kennung stammt aus dem Bundle dort oder wird aus den Resten erschlossen, die sie nennen.

Nichts wird gelöscht. Alles wandert in den Papierkorb, ein Fehler kostet also eine Wiederherstellung und keine Datei, und was macOS nicht herausgibt, wird mit Grund genannt statt stillschweigend übergangen.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/uninstall.png" width="480" alt="Hop — eine App mitsamt allem entfernen, was sie hinterließ">
</div>

Dasselbe Modul räumt auf, ohne etwas zu entfernen: jede App mit Cache, die größten zuerst; Installer in Downloads, auf dem Schreibtisch und in Dokumenten; Daten längst entfernter Apps; und der Papierkorb mit seiner Größe. Ein Häkchen nimmt einen ganzen Abschnitt. Was es bewusst in Ruhe lässt, steht ebenfalls da — ein Container, in dem Cache und Daten zusammenliegen, die zwanzig Gigabyte eines Messengers etwa: was davon entbehrlich ist, weiß nur die App selbst.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/de/clean.png" width="480" alt="Hop — Caches, Installer, Reste und den Papierkorb leeren">
</div>

## 22 Sprachen

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — die App folgt von Haus aus deiner Systemsprache.

## Unterstütze das Projekt

Hop ist kostenlos und bleibt es. Wenn es sich einen Platz in deiner Menüleiste
verdient hat, hilft ein freiwilliger Beitrag dabei, neue Funktionen zu bringen
und die bestehenden zu schleifen — er bezahlt die Zeit, sonst nichts.

**[→ Hop unterstützen](https://web.tribute.tg/d/Nvk)**

## Datenschutz — und warum die Berechtigungen unbedenklich sind

**Hop sammelt nichts. Jetzt nicht und später nicht.** Kein eigener Server, keine
Analytics, keine Telemetrie, keine Accounts, keine Crash-Reports. Jede
Berechtigung unten fragt macOS erst dann, wenn die Funktion, die sie braucht,
wirklich benutzt wird, und sie ist genau dafür da — nebenbei wird nichts
gesammelt. Du musst das nicht glauben: die App ist Open Source, den sammelnden
Code gibt es schlicht nicht. Suche in diesem Repository nach einem Tracking-SDK
oder einem Analytics-Aufruf — du wirst keinen finden.

Alles läuft lokal: kein Server, keine Analytics, keine Konten. Die App greift
nur auf das Netzwerk zu, um nach Updates zu suchen, wenn du den eingebauten
Speedtest startest und — falls du das Torrent-Modul aktivierst — um die
Engine einmalig zu laden und den Torrent-Verkehr selbst zu übertragen. Die
Update-Abfrage sendet die Version, die du nutzt — und nichts, was dich oder
deinen Mac identifiziert. Updates und die Torrent-Engine werden als signierte
Archive ausgeliefert und vor der Installation mit einer Ed25519-Signatur
verifiziert.

## Berechtigungen

Hop fragt eine Berechtigung erst dann ab, wenn die zugehörige Funktion wirklich
benutzt wird; das Infofenster listet alle mit ihrem aktuellen Stand auf:

- **Netzwerk — antonshakirov.com** — Updates suchen und laden, dazu die zwei
  optionalen Helfer (Torrent-Engine und 7-Zip-Archivierer)
- **Netzwerk — Torrents, Geschwindigkeitstest** — Verkehr zu anderen Teilnehmern
  bei eingeschaltetem Torrent-Modul; der Test nutzt macOS' networkQuality gegen
  Apples Server
- **Bedienungshilfen** — Einfügen in die App darunter, Fenstermanager und
  Tastatursperre
- **Bildschirmaufnahme** — nur die Texterkennung, und nur beim Einrahmen eines
  Bereichs; die Farbpipette braucht sie nicht
- **Mitteilungen** — der Timer-Hinweis und ein fertiger Torrent
- **Administratorkennwort** — einmalig, für den Modus mit geschlossenem Deckel
  (pmset läuft nur als root)
- **Beim Anmelden öffnen** — aus, bis du es einschaltest

Beim Start wird nichts angefragt, und nichts wird für ein Modul verlangt, das du
nicht eingeschaltet hast. Keine Analytics, keine Telemetrie, kein Account, keine
Crash-Reports: antonshakirov.com wird nur kontaktiert, um zu fragen, ob es eine
neuere Version gibt — und um sie oder einen der zwei optionalen Helfer zu laden,
wenn du zustimmst. Alles andere bleibt auf diesem Mac: der Verlauf der
Zwischenablage, erfasste Zeit, die Aufgabenliste, erkannter Text und Farben.

Jede Berechtigung oben ist dafür da, dass eine Funktion arbeitet — und für
nichts sonst. Du musst das nicht glauben: Hop ist Open Source, den sammelnden
Code gibt es schlicht nicht — lies ihn in diesem Repository. Im Infofenster der
App gibt es den Tab «App-Berechtigungen» mit derselben Liste und dem aktuellen
Stand jeder einzelnen.

Website: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Kostenlos — und warum

Hop ist völlig kostenlos: keine Testphase, keine Pro-Version, keine
In-App-Käufe. Keine Werbung, keine Datenerfassung, keine Konten — es gibt
nichts zu monetarisieren und nichts zu verkaufen. Es ist ein persönliches
Projekt: Ich habe Hop für mich selbst gebaut, nutze es täglich und teile es
einfach. Wenn es nützlich ist, gib es weiter. Und wenn du etwas beisteuern
möchtest, gibt es jetzt eine Möglichkeit, Hop zu unterstützen — einfach ein
Geschenk, ohne dass etwas dahinter verborgen ist.

## Aus dem Quellcode bauen

Swift Package Manager, macOS 14+, keine externen Abhängigkeiten:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Dev-Workflow, Release-Pipeline und die Verhaltensspezifikation findest du in
[docs/development.md](../development.md) und [docs/spec.md](../spec.md).

## Unterstütze das Projekt

Drei Wege, jeder davon willkommen:

- **[Hop mit einem Beitrag unterstützen](https://web.tribute.tg/d/Nvk)** — er
  geht direkt in neue Funktionen und Fixes. Freiwillig, ohne Perks, ohne
  Bezahlschranke: jedes Modul ist für alle gleich.
- **[Dem Repo einen Stern geben](https://github.com/antonyshakirov/hop/stargazers)** —
  über Sterne finden andere es.
- **[Ein Issue eröffnen](https://github.com/antonyshakirov/hop/issues)** — ein
  Bug-Report oder eine Idee ist genauso wertvoll.

## Autor & Lizenz

Entwickelt von [Anton Shakirov](https://www.antonshakirov.com/en).
Veröffentlicht unter der [MIT-Lizenz](../../LICENSE): frei nutzen und
verändern, den Copyright-Hinweis behalten — die App als eigene Arbeit
auszugeben ist ein Lizenzverstoß.
