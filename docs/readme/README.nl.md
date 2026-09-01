<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop-appicoon — asterisk van vier lijnen">

# Hop

**Een piepklein menubalk-hulpje voor macOS: timer, tijdregistratie,
takenlijst, slaapblokkering, systeemmonitor, klembordgeschiedenis,
bestandsconverter, vensterbeheer en een lichte torrentclient. Je zet aan
wat je nodig hebt en verdeelt het over tot vier tabbladen op het icoon.
Eén klik — en alles wat je nodig hebt staat meteen klaar.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fhop.tools%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://hop.tools/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · **Nederlands** · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://hop.tools/screens/en/overview.webp" width="360" alt="Hop-paneel — menubalktimer met dot-matrixdisplay, presets en werk-rustcycli">

</div>

Hop woont in de menubalk van je Mac en vervangt een handvol kleine
hulpprogramma's: een timer in Pomodoro-stijl, een tijdregistratie met
takenlijst, een slaapblokkering à la caffeinate, een systeemmonitor, een
klembordbeheerder, een drag-and-drop-bestandsconverter, een venster-snapper
en een lichte torrentclient — één lichtgewicht native app, met de modules
die je gebruikt verdeeld over tot vier tabbladen op het icoon.

## Downloaden

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — openen en `Hop.app` naar de map Apps slepen (aanbevolen)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — dezelfde app als een gewoon archief (gebruikt door de ingebouwde updater); zie de [nieuwste release](https://github.com/antonyshakirov/hop/releases/latest)
- Snelle mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Hop is ondertekend met een Apple Developer ID en genotariseerd door Apple,
dus macOS opent het als elke andere app. De broncode is openbaar en
ingebouwde updates worden geverifieerd met Ed25519. Vereist macOS 14 of
nieuwer.

## Functies

### Ruimtes

Het icoon houdt tot vier tabbladen, en je sleept elke module naar het
tabblad dat je wilt: de timer op de een, de monitor op de ander, wat je
zelden opent aan de kant. Het oog naast een module verbergt hem, zonder hem
te verplaatsen of te verwijderen.

### Timer & cycli

Een dot-matrix-countdown die je in één gebaar instelt: sleep de cijfers, tik
de tijd in zoals op een magnetron, of kies een preset. Werk-rustcycli (25/5
Pomodoro, 52/17, 90/15 — of je eigen), een stopwatch, een stash die een
lopende timer bewaart terwijl je een andere probeert, en een eindmelding die
desgewenst ook je media pauzeert. Als de countdown afloopt, klinkt er één
geluid en knipperen de cijfers tot je reset.

<div align="center">
<img src="https://hop.tools/screens/en/timer.webp" width="420" alt="Hop — Timer & cycli">
</div>

### Tijdregistratie & taken

Taken kunnen in projecten worden gegroepeerd, elk met een eigen som, en een
schakelaar boven de lijst toont vandaag, deze week of alles. Een lopende taak
telt de sessie waarin je zit, vanaf nul; het ✓ ernaast sluit die sessie en in
de rij staat weer de som van de periode. Open een taak en al haar stukken tijd
staan er: de duur of het moment wijzigen, een sessie toevoegen die niemand
startte, of er een verwijderen; handmatige correcties staan in dezelfde lijst,
zodat de regels optellen tot het totaal erboven. Loopt er een te lang, dan
herinnert een banner je na acht uur. Ernaast staat een aparte to-do-lijst,
waarin afgevinkte items naar onderen zakken.

Klik op een taak en de regel klapt open: de volledige tekst op de eerste regel,
daaronder een beschrijving, een ster voor favorieten. Een to-do kan ook een
herinnering dragen — dag, tijd en de weekdagen die je wilt herhalen — en Hop laat
het weten: een banner met «uitstellen» en «klaar», geluid, een teken in de
menubalk; elk apart aan te zetten.

**Ook je eigen AI-agent kan taken toevoegen.** De lijst is een gewoon
JSON-bestand en Hop pikt wijzigingen tijdens het draaien op. Hop voert ook
opdrachten uit een bestand uit en begrijpt `hop://`-links: diezelfde agent, of een
Opdracht rond zo'n link, kan een timer starten, een taak met herinnering
toevoegen of lezen wat er draait. Zie
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://hop.tools/screens/en/tracker.webp" width="420" alt="Hop — Tijdregistratie & taken">
</div>

### Geen slaap

Houd de Mac 15 minuten, 8 uur of voor altijd wakker — één klik, geen
wachtwoord. Laat optioneel het scherm aan, of werk door met het deksel dicht
(handig voor downloads, lange builds en externe schermen).

<div align="center">
<img src="https://hop.tools/screens/en/awake.webp" width="420" alt="Hop — Geen slaap">
</div>

### Systeemmonitor

CPU- en GPU-belasting en -temperatuur, geheugen en swap, netwerk, schijf,
batterijconditie en stroomverbruik — livewaarden met sparkline-grafieken,
kleurdrempels die je zelf instelt, °C/°F en een uptime-regel. De metingen
komen rechtstreeks van macOS en worden alleen bijgewerkt zolang het tabblad
open is. De geheugenrij waarschuwt ook als veel geheugen naar de schijf is
verhuisd, en niet pas als macOS zelf krapte meldt.

<div align="center">
<img src="https://hop.tools/screens/en/system.webp" width="420" alt="Hop — Systeemmonitor">
</div>

### Klembordgeschiedenis

De laatste 100 (tot 300) dingen die je kopieerde — tekst, afbeeldingen en
bestanden — met één klik terug te kopiëren of direct te plakken in de vorige
app. Gekopieerde bestanden worden op naam onthouden (meerdere tegelijk
verschijnen als «naam +N»), en bij het plakken komt het bestand zelf terug.
Wachtwoorden en andere verborgen invoer worden nooit opgeslagen.

<div align="center">
<img src="https://hop.tools/screens/en/clipboard.webp" width="420" alt="Hop — Klembordgeschiedenis">
</div>

### Bestandsconverter

Sleep een lading afbeeldingen, pdf's, video's of audio op het paneel: JPEG,
PNG, HEIC, AVIF en WebP als uitvoer; pdf-compressie; HEVC-videoverkleinen met
een eerlijke live-schatting van de bestandsgrootte vóór je converteert. Alles
wordt lokaal verwerkt. Video kan bij het converteren ook opnieuw worden
gekaderd — 9:16, 4:5, vierkant of 16:9, bijgesneden, met balken of op een
vervaagde kopie — en de compressie heeft een eigen niveau, zodat de vooraf
beloofde grootte de werkelijke is.

Eén knop zet een clip klaar voor waar hij heen gaat — reels, feed, tiktok,
shorts of youtube — en schrijft kader, resolutie en compressie zoals het
platform zelf aanraadt, met de resulterende bitrate naast de schuif. MKV en
WebM worden eerst omgepakt naar MP4 (macOS opent geen van beide) door een
klein hulpje dat één keer downloadt. Pages-, Numbers- en Keynote-documenten
worden in batches geëxporteerd door de apps zelf: naar PDF, of naar docx, xlsx
en pptx.

<div align="center">
<img src="https://hop.tools/screens/en/converter.webp" width="480" alt="Hop — Bestandsconverter">
</div>

### Vensterbeheer

Klik vensters vast op helften, kwarten, derden en het midden via een
zonesymbool of een ⌃⌥-sneltoets — geen extra app nodig.

<div align="center">
<img src="https://hop.tools/screens/en/windows.webp" width="420" alt="Hop — Vensterbeheer">
</div>

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
<img src="https://hop.tools/screens/en/torrents.webp" width="420" alt="Hop-torrents — lichte BitTorrent-client in het menubalkpaneel">
</div>

### Bestandsarchieven

De regel van de module opent een venster, en dáárin sleep je je bestanden — ⌘V
kan ook, meerdere bestanden tegelijk. Wat je toevoegt wacht in een lijst tot je
op de knop drukt: archieven worden uitgepakt, al het andere gaat in één archief.
Het resultaat komt standaard op het bureaublad, of naast het origineel, of in
een map naar keuze. Ondersteund zijn zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz
en gz; voor rar en 7z wordt de eerste keer een kleine, op handtekening
gecontroleerde helper (~6 MB) opgehaald. Hop pakt rar uit maar maakt het nooit —
het formaat is propriëtair. «Hop als standaard voor archieven» bij de instellingen biedt
alleen rar aan wanneer geen Apple-app het beheert, en kan rar terugpakken van
apps van derden; zip, 7z en de native formaten blijven bij Archiefhulpprogramma. Het
werkt ook met een verborgen module, en de kaart toont de echte stand. Dubbelklikken op een archief in Finder pakt het uit vlak naast het bestand, in een eigen klein voortgangsvenster, en een mislukte poging laat niets verborgens achter. Bestanden die Hop opent dragen een eigen pictogram met het formaat erop, zodat een map in één oogopslag leesbaar is.

<div align="center">
<img src="https://hop.tools/screens/en/archives.webp" width="480" alt="Hop — Bestandsarchieven">
</div>

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

<div align="center">
<img src="https://hop.tools/screens/en/colors.webp" width="420" alt="Hop — Kleurenpipet">
</div>

### Tekstherkenning

Kader een deel van je scherm, of sleep een afbeelding in het venster en plak er
een met ⌘V: de tekst en eventuele QR-codes komen in een venster dat je kunt
lezen, bijwerken en waaruit je kunt kopiëren, en gaan tegelijk naar de
klembordgeschiedenis. Regeleindes blijven staan, dus een tabel blijft leesbaar.
De herkenning is Vision van Apple, volledig op deze Mac.

Staat er een webadres in het resultaat, dan verschijnt de knop «link openen»:
de link uit een QR-code op een rekening opent meteen in de browser, zonder dat
je je telefoon pakt. Alleen webadressen: een gescande code is invoer van
buiten, dus een telefoonnummer, een wifiwachtwoord of een visitekaartje blijft
gewone tekst.

<div align="center">
<img src="https://hop.tools/screens/en/recognition.webp" width="480" alt="Hop — Tekstherkenning">
</div>

### Toetsenbordslot

Tik 1, 5 of 15 minuten — of ∞ — en het hele toetsenbord reageert niet meer, zodat
je het kunt afnemen zonder de Mac uit te zetten of de klep te sluiten. Een
schermvullende afdekking legt uit wat er gebeurt en het menubalkpictogram wordt
een toetsenbord. Vier uitwegen: de knop op de afdekking, de knop in het paneel,
het paneel openen, of esc + shift vijf seconden vasthouden. Een korte druk op de
aan/uit-toets wordt ook geslikt; hem ingedrukt houden zet de Mac nog steeds uit,
want dat regelt de hardware.

<div align="center">
<img src="https://hop.tools/screens/en/keyboard.webp" width="480" alt="Hop — Toetsenbordslot">
</div>

### Snelheidstest

Eén tik meet de verbinding met macOS' eigen networkQuality tegen Apples servers — down, up en reactiesnelheid, en het laatste resultaat blijft in de rij staan.

<div align="center">
<img src="https://hop.tools/screens/en/speed.webp" width="420" alt="Hop — Snelheidstest">
</div>

### Het icoon in de menubalk

Op het icoon zitten kleine markeringen: de lopende tijd, de slaapblokkade, een
herinnering die afging, een stip zolang er een vpn staat (oranje als er niets meer
doorheen gaat) en pijlen zolang torrents lopen — in kleur of monochroom, elk apart uit
te zetten. Hops eigen vensters verschijnen in het Dock zolang ze open zijn, dus één
klik haalt er een terug in plaats van het paneel te openen, en het icoon vertrekt met
het laatste venster.

### Thema's, sneltoetsen en veilige modus

Donker en licht thema met filmkorrel-textuur, globale sneltoetsen, starten bij inloggen en een veilige modus die de app uit een crashlus haalt — alles in één instellingenvenster.

<div align="center">
<img src="https://hop.tools/screens/en/settings.webp" width="480" alt="Hop — Instellingen">
</div>

### VPN

Elke VPN die je Mac kent, elk met een eigen schakelaar, van welke aanbieder ook.
Hop leest de lijst rechtstreeks uit systeeminstellingen: een client die je gisteren
installeerde verschijnt vanzelf, een verwijderde verdwijnt. Hier valt niets toe te
voegen of in te stellen.

Verbind en verbreek zonder iets te openen. Zolang een tunnel staat, brandt een klein
puntje in de hoek van het menubalkicoon, naast de andere indicatoren: groen zolang er
iets doorheen gaat, oranje wanneer de tunnel aanstaat maar er niets terugkomt. Een
stilletjes gestorven verbinding ziet er zo niet langer gezond uit, en het paneel wijst
de rij aan. Klik op de naam en het venster van die VPN gaat open; sluit je het, dan
sluit Hop de app. De verbinding blijft: de tunnel wordt door het systeem vastgehouden,
niet door de app.

De regel toont wat de client zelf meldt: zijn naam en tussen haakjes wat de
configuratie toevoegt, meestal het land. Hop raadt het land nooit uit het
serveradres: het register zegt waar een reeks geregistreerd staat, niet waar de
machine staat.

De stip kun je in de instellingen uitzetten — de module en de schakelaars werken gewoon door.

<div align="center">
<img src="https://hop.tools/screens/en/vpn.webp" width="420" alt="Hop — VPN-schakelaars">
</div>

### Apps

Een raster met de programma's die je de hele dag opent — één klik weg, zonder
omweg via de map Programma's. Druk op + en kies ze, of sleep ze uit de Finder;
er passen er negen naast elkaar, tot acht rijen.

Sleep een symbool om het te verplaatsen: een gele lijn laat zien tussen welke
twee symbolen het landt en de rest schuift opzij, net als op een beginscherm. De
bewerkknop start het wiegen, elk symbool krijgt een ✕ en het raster kan een
eigen naam krijgen; daar zet je ook de namen onder de symbolen uit, als je je
apps op het oog herkent. Houd zoveel rasters aan als je wilt — werk op het ene
vlak, de rest op het andere — elk met eigen apps.

Rasters ontstaan en verdwijnen waar je de modules ordent: in de instellingen of
in de moduletabel zelf, waar de ✕ op de chip van een raster het definitief
verwijdert. Een nieuw raster begint leeg en zegt dat ook, tot je het vult.

<div align="center">
<img src="https://hop.tools/screens/en/apps.webp" width="420" alt="Hop — App-raster">
</div>

### Apps verwijderen

Sleep een app op de rij, of kies hem uit de lijst van alles wat geïnstalleerd is, en hij gaat mét wat hij op een stuk of dertig plekken achterliet: application support, caches, voorkeuren, containers, launch agents, plug-ins, installatiebonnetjes en de rest. Elke app in de lijst toont hoeveel hij weegt, de app en zijn gegevens apart. Een app die al in de prullenmand ligt wordt ook herkend: de identifier komt uit het pakket dat daar staat, of wordt afgeleid uit de resten die hem noemen.

Er wordt niets gewist. Alles gaat naar de prullenmand, dus een vergissing kost een herstel en geen bestand; en wat macOS niet afgeeft wordt met reden genoemd in plaats van stilletjes overgeslagen.

<div align="center">
<img src="https://hop.tools/screens/en/uninstall.webp" width="480" alt="Hop — Een app verwijderen met alles wat hij achterliet">
</div>

Dezelfde module ruimt op zonder iets te verwijderen: elke app die een cache aanhoudt, de grootste eerst; installers in Downloads, op het bureaublad en in Documenten; gegevens van apps die je jaren geleden weghaalde; en de prullenmand met zijn omvang. Eén vinkje neemt een hele sectie. Wat het bewust laat liggen staat er ook bij — een container waarin cache en gegevens in één map zitten, de twintig gigabyte van een berichtenapp bijvoorbeeld: alleen die app weet welke helft weg kan.

<div align="center">
<img src="https://hop.tools/screens/en/clean.webp" width="480" alt="Hop — Caches, installers, resten en de prullenmand opruimen">
</div>

## 22 talen

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — de app volgt standaard je systeemtaal.

## Steun het project

Hop is gratis en blijft dat. Als het een plek in je menubalk verdient, helpt een
vrijwillige bijdrage om nieuwe functies uit te brengen en de bestaande bij te
schaven — hij betaalt de tijd, niets anders.

**[→ Hop steunen](https://web.tribute.tg/d/Nvk)**

## Privacy — en waarom je de toestemmingen gerust kunt geven

**Hop verzamelt niets. Nu niet en later niet.** Geen eigen server, geen
analytics, geen telemetrie, geen accounts, geen crashrapporten. Elke toestemming
hieronder vraagt macOS pas wanneer je de functie die hem nodig heeft echt
gebruikt, en hij bestaat precies zodat die functie werkt — er wordt onderweg
niets verzameld. Je hoeft dat niet te geloven: de app is open source, en de code
die zou moeten verzamelen bestaat er simpelweg niet. Zoek in deze repository
naar een tracking-SDK of een analytics-aanroep — je vindt er geen.

Alles draait lokaal: geen server, geen analytics, geen accounts. De app
gebruikt het netwerk alleen om op updates te controleren, wanneer je de
ingebouwde snelheidstest draait en — als je de torrentmodule inschakelt — om
de engine eenmalig op te halen en het torrentverkeer zelf te verplaatsen. Die
updatecontrole stuurt de versie die je draait, en niets wat jou of je Mac
identificeert. Updates en de torrent-engine worden geleverd als ondertekende
archieven en vóór installatie geverifieerd met een Ed25519-handtekening.

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

Elke toestemming hierboven is er zodat een functie kan werken — en nergens
anders voor. Je hoeft dat niet te geloven: Hop is open source, en de code die
zou moeten verzamelen bestaat er simpelweg niet — lees hem in deze repository.
Het infovenster van de app heeft een tab «app-toestemmingen» met dezelfde lijst
en de huidige stand van elke toestemming.

Website: [hop.tools](https://hop.tools)

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

Drie manieren, alle drie welkom:

- **[Hop steunen met een bijdrage](https://web.tribute.tg/d/Nvk)** — die gaat recht
  naar nieuwe functies en fixes. Vrijwillig, zonder perks, niets achter een
  betaalmuur: elke module is voor iedereen hetzelfde.
- **[Geef de repo een ster](https://github.com/antonyshakirov/hop/stargazers)** —
  via sterren vinden anderen het.
- **[Open een issue](https://github.com/antonyshakirov/hop/issues)** — een
  bugmelding of een idee is net zoveel waard.

## Auteur & licentie

Gemaakt door [Anton Shakirov](https://www.antonshakirov.com/en). Uitgebracht
onder de [MIT-licentie](../../LICENSE): vrij te gebruiken en aan te passen,
behoud de copyrightvermelding — de app als je eigen werk presenteren is een
schending van de licentie.
