<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop-appicoon — asterisk van vier lijnen">

# Hop

**Een piepklein menubalk-hulpje voor macOS: timer, tijdregistratie,
takenlijst, slaapblokkering, systeemmonitor, klembordgeschiedenis,
bestandsconverter, vensterbeheer en een lichte torrentclient — verdeeld over
tot vier tabbladen op het icoon. Eén klik — en alles wat je nodig hebt staat
meteen klaar.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · **Nederlands** · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="Hop-paneel — menubalktimer met dot-matrixdisplay, presets en werk-rustcycli">

</div>

Hop woont in de menubalk van je Mac en vervangt een handvol kleine
hulpprogramma's: een timer in Pomodoro-stijl, een tijdregistratie met
takenlijst, een slaapblokkering à la caffeinate, een systeemmonitor, een
klembordbeheerder, een drag-and-drop-bestandsconverter, een venster-snapper
en een lichte torrentclient — één lichtgewicht native app, met de modules
die je gebruikt verdeeld over tot vier tabbladen op het icoon.

## Downloaden

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — openen en `Hop.app` naar de map Apps slepen (aanbevolen)
- `Hop-x.y.z.zip` — dezelfde app als een gewoon archief (gebruikt door de ingebouwde updater); zie de [nieuwste release](https://github.com/antonyshakirov/hop/releases/latest)
- Snelle mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Eerste keer starten: klik met de rechtermuisknop op `Hop.app` → **Open** →
bevestigen (de app is nog niet genotariseerd). Vereist macOS 14 of nieuwer.

## Functies

### Ruimtes

Het icoon houdt tot vier tabbladen, en je sleept elke module naar het
tabblad dat je wilt: de timer op de een, de monitor op de ander, wat je
zelden opent aan de kant. Een plank «inactief» bewaart wat je opzij zet,
zonder het te verwijderen.

### Timer & cycli

Een dot-matrix-countdown die je in één gebaar instelt: sleep de cijfers, tik
de tijd in zoals op een magnetron, of kies een preset. Werk-rustcycli (25/5
Pomodoro, 52/17, 90/15 — of je eigen), een stopwatch, een stash die een
lopende timer bewaart terwijl je een andere probeert, en een eindmelding die
desgewenst ook je media pauzeert. Als de countdown afloopt, klinkt er één
geluid en knipperen de cijfers tot je reset.

### Tijdregistratie & taken

Houd tijd bij op een platte takenlijst: elke rij toont de tijd van vandaag en
een doorlopend totaal, en het cijfer van vandaag pas je met de hand aan. Loopt
er een te lang, dan herinnert een banner je na acht uur. Ernaast staat een
aparte to-do-lijst, waarin afgevinkte items naar onderen zakken.

### Geen slaap

Houd de Mac 15 minuten, 8 uur of voor altijd wakker — één klik, geen
wachtwoord. Laat optioneel het scherm aan, of werk door met het deksel dicht
(handig voor downloads, lange builds en externe schermen).

### Systeemmonitor

CPU- en GPU-belasting en -temperatuur, geheugen en swap, netwerk, schijf,
batterijconditie en stroomverbruik — livewaarden met sparkline-grafieken,
kleurdrempels die je zelf instelt, °C/°F en een uptime-regel. De metingen
komen rechtstreeks van macOS en worden alleen bijgewerkt zolang het tabblad
open is.

### Klembordgeschiedenis

De laatste 100 (tot 300) dingen die je kopieerde — tekst, afbeeldingen en
bestanden — met één klik terug te kopiëren of direct te plakken in de vorige
app. Gekopieerde bestanden worden op naam onthouden (meerdere tegelijk
verschijnen als «naam +N»), en bij het plakken komt het bestand zelf terug.
Wachtwoorden en andere verborgen invoer worden nooit opgeslagen.

### Bestandsconverter

Sleep een lading afbeeldingen, pdf's, video's of audio op het paneel: JPEG,
PNG, HEIC, AVIF en WebP als uitvoer; pdf-compressie; HEVC-videoverkleinen met
een eerlijke live-schatting van de bestandsgrootte vóór je converteert. Alles
wordt lokaal verwerkt.

### Vensterbeheer

Klik vensters vast op helften, kwarten, derden en het midden via een
zonesymbool of een ⌃⌥-sneltoets — geen extra app nodig.

### Torrents

Een lichte BitTorrent-client in hetzelfde paneel: sleep een .torrent-bestand
erin of plak een magnet-link, kies precies welke bestanden je downloadt —
vooraf of zelfs tijdens de download —, pauzeer, hervat en seed, met een
optionele stop bij ratio 1.0. De module staat standaard uit; bij het
inschakelen wordt de opensource-engine opgehaald als een kleine aparte
download (~26 MB, met geverifieerde handtekening) die alleen via een lokale
poort met Hop praat. Hop kan ook de standaardapp worden voor
.torrent-bestanden en magnet-links.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Hop-torrents — lichte BitTorrent-client in het menubalkpaneel">
</div>

### Bestandsarchieven

De regel van de module opent een venster, en dáárin sleep je je bestanden — ⌘V
kan ook, meerdere bestanden tegelijk. Wat je toevoegt wacht in een lijst tot je
op de knop drukt: archieven worden uitgepakt, al het andere gaat in één archief.
Het resultaat komt standaard op het bureaublad, of naast het origineel, of in
een map naar keuze. Ondersteund zijn zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz
en gz; voor rar en 7z wordt de eerste keer een kleine, op handtekening
gecontroleerde helper (~6 MB) opgehaald. Hop pakt rar uit maar maakt het nooit —
het formaat is propriëtair. «Archieven openen met Hop» bij de instellingen neemt de
formaten waarvoor macOS geen eigen app heeft — vooral rar en 7z — en pakt ze
terug van apps van derden; zip en tar blijven bij Archiefhulpprogramma. Het
werkt ook met een verborgen module, en de kaart toont de echte stand.

### Documenten

De converter kan nu documenten: markdown → PDF, opgemaakt door Hop zelf,
Word-bestanden (.docx, .doc, .rtf) → PDF of markdown, en de tekst uit een PDF als
markdown — een gescande pagina wordt gelezen door Vision van Apple. Native en
offline, zonder meegeleverd officepakket en zonder downloads.

### Kleurenpipet

Pak met de systeemloep elke kleur van je scherm: hij blijft in een lijst staan,
elke rij met hex, rgb en hsl in een eigen kolom — klik er een en precies die
notatie wordt gekopieerd. De volgorde verandert nooit onder je cursor, hoeveel
kleuren je bewaart en hoeveel rijen je ziet zijn instellingen, en toestemming
voor schermopname is niet nodig: de loep geeft één kleur terug.

### Tekstherkenning

Kader een deel van je scherm, of sleep een afbeelding in het venster en plak er
een met ⌘V: de tekst en eventuele QR-codes komen in een venster dat je kunt
lezen, bijwerken en waaruit je kunt kopiëren, en gaan tegelijk naar de
klembordgeschiedenis. Regeleindes blijven staan, dus een tabel blijft leesbaar.
De herkenning is Vision van Apple, volledig op deze Mac.

### Toetsenbordslot

Tik 1, 5 of 15 minuten — of ∞ — en het hele toetsenbord reageert niet meer, zodat
je het kunt afnemen zonder de Mac uit te zetten of de klep te sluiten. Een
schermvullende afdekking legt uit wat er gebeurt en het menubalkpictogram wordt
een toetsenbord. Vier uitwegen: de knop op de afdekking, de knop in het paneel,
het paneel openen, of esc + shift vijf seconden vasthouden. Een korte druk op de
aan/uit-toets wordt ook geslikt; hem ingedrukt houden zet de Mac nog steeds uit,
want dat regelt de hardware.

### En de rest

Kleine statusindicatoren op het menubalk-icoon — tijd, slaapblokkering,
waarschuwingen en torrentactiviteit, in kleur of monochroom —, een
ingebouwde snelheidstest (Apples networkQuality), donkere en lichte thema's
met een filmkorrel-textuur, globale sneltoetsen, starten bij inloggen en een
veilige modus die de app uit een crashlus haalt.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Hop-systeemmonitor — grafieken voor CPU, GPU, geheugen, netwerk, schijf, batterij">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Hop-bestandsconverter — batchconversie van afbeeldingen, pdf's, video en audio">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Hop-instellingen — thema's, modules, sneltoetsen, 18 talen">
</div>

## 18 talen

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — de app volgt standaard je systeemtaal.

## Privacy

Alles draait lokaal: geen server, geen analytics, geen accounts. De app
gebruikt het netwerk alleen om op updates te controleren, wanneer je de
ingebouwde snelheidstest draait en — als je de torrentmodule inschakelt — om
de engine eenmalig op te halen en het torrentverkeer zelf te verplaatsen.
Updates en de torrent-engine worden geleverd als ondertekende archieven en
vóór installatie geverifieerd met een Ed25519-handtekening.

## Toestemmingen

Hop vraagt pas om een toestemming wanneer de functie die haar nodig heeft echt
gebruikt wordt; het infovenster van de app somt ze allemaal op met hun stand:

- **netwerk — antonshakirov.com** — controleren op updates en ze downloaden, plus
  de twee optionele hulpjes (de torrent-engine en de 7-Zip-archiveerder)
- **netwerk — torrents, snelheidstest** — verkeer met andere peers zolang de
  torrentmodule aanstaat; de test gebruikt macOS' eigen networkQuality tegen de
  servers van Apple
- **toegankelijkheid** — plakken in de app eronder, de vensterbeheerder en de
  toetsenbordvergrendeling
- **schermopname** — alleen de tekstherkenning, en alleen bij het kaderen van
  een gebied; de kleurenpipet heeft het niet nodig
- **berichtgeving** — het signaal van de timer en een afgeronde torrent
- **beheerderswachtwoord** — één keer, voor de stand met gesloten klep (pmset
  draait alleen als root)
- **openen bij inloggen** — uit tot je het zelf aanzet

Bij het starten wordt niets gevraagd, en niets wordt gevraagd voor een module die
je niet hebt aangezet. Geen analytics, geen telemetrie, geen account, geen
crashrapporten: antonshakirov.com wordt alleen benaderd om te vragen of er een
nieuwere versie is — en om die, of een van de twee optionele helpers, te
downloaden als jij ja zegt. Al het andere blijft op deze Mac: de
klembordgeschiedenis, bijgehouden tijd, de takenlijst, herkende tekst en kleuren.

Website: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Gratis, en waarom

Hop is volledig gratis: geen proefperiode, geen pro-versie, geen
in-app-aankopen. Geen advertenties, geen dataverzameling, geen accounts — er
valt niets te verdienen en niets te verkopen. Het is een persoonlijk project:
ik heb Hop voor mezelf gemaakt, gebruik het elke dag en deel het gewoon. Is het
nuttig, geef het dan door. En wil je bijdragen, dan is er nu een manier om Hop
te steunen — puur een cadeau, zonder dat er iets achter zit.

## Bouwen vanaf de broncode

Swift Package Manager, macOS 14+, geen externe afhankelijkheden:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

De dev-workflow, de release-pipeline en de gedragsspecificatie staan in
[docs/development.md](../development.md) en [docs/spec.md](../spec.md).

## Steun het project

Als Hop je een klik of twee bespaart, **[geef de repo dan een ster](https://github.com/antonyshakirov/hop/stargazers)** —
via sterren vinden anderen het project. Bugmeldingen en feature-ideeën zijn
welkom in [Issues](https://github.com/antonyshakirov/hop/issues).

## Auteur & licentie

Gemaakt door [Anton Shakirov](https://www.antonshakirov.com/en). Uitgebracht
onder de [MIT-licentie](../../LICENSE): vrij te gebruiken en aan te passen,
behoud de copyrightvermelding — de app als je eigen werk presenteren is een
schending van de licentie.
