<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icona dell'app Hop — asterisco a quattro linee">

# Hop

**Un piccolo compagno per la barra dei menu di macOS: timer, monitoraggio del
tempo, cose da fare, anti-stop, monitor di sistema, cronologia degli appunti,
convertitore di file, gestore delle finestre e un client torrent leggero —
distribuiti su fino a quattro schede dell'icona. Un clic — e tutto ciò che ti
serve è lì.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · **Italiano** · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="Pannello di Hop — timer nella barra dei menu con display a matrice di punti, preset e cicli lavoro-pausa">

</div>

Hop vive nella barra dei menu del tuo Mac e sostituisce una manciata di
piccole utility: un timer in stile Pomodoro, un monitoraggio del tempo con
lista di cose da fare, un blocca-riposo in stile caffeinate, un monitor di
sistema, un gestore degli appunti, un convertitore di file drag-and-drop, uno
strumento per agganciare le finestre e un client torrent leggero — una sola
app nativa e leggera, con i moduli che usi distribuiti su fino a quattro
schede dell'icona.

## Download

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — aprilo e trascina `Hop.app` in Applicazioni (consigliato)
- `Hop-x.y.z.zip` — la stessa app come semplice archivio (usato dall'aggiornatore integrato); vedi l'[ultima release](https://github.com/antonyshakirov/hop/releases/latest)
- Mirror veloce: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primo avvio: clic destro su `Hop.app` → **Apri** → conferma
(l'app non è ancora notarizzata). Richiede macOS 14 o più recente.

## Funzionalità

### Spazi

L'icona ospita fino a quattro schede, e trascini ogni modulo nella scheda che
preferisci: il timer su una, il monitor su un'altra, ciò che apri di rado da
parte. Un ripiano «inattivi» conserva quel che metti via, senza eliminarlo.

### Timer e cicli

Un conto alla rovescia a matrice di punti che imposti con un solo gesto:
trascina le cifre, digita il tempo come su un microonde, oppure scegli un
preset. Cicli lavoro-pausa (Pomodoro 25/5, 52/17, 90/15 — o i tuoi), un
cronometro, una tasca che conserva un timer in corso mentre ne provi un
altro, e un avviso di fine che può anche mettere in pausa i tuoi media. Quando
il conto alla rovescia finisce, suona una sola volta e le cifre pulsano finché
non azzeri.

### Monitoraggio del tempo e attività

Tieni il tempo su una lista piatta di attività: ogni riga mostra il tempo di
oggi e un totale progressivo, e puoi correggere a mano la cifra di oggi. Se
una va troppo a lungo, dopo otto ore un banner te lo ricorda. Accanto c'è una
lista di cose da fare a parte, dove il completato scende in fondo.

### Niente stop

Tieni il Mac sveglio per 15 minuti, 8 ore o per sempre — un clic, nessuna
password. Facoltativamente tieni acceso lo schermo, oppure continua a
lavorare con il coperchio chiuso (comodo per download, build lunghe e
schermi esterni).

### Monitor di sistema

Carico e temperatura di CPU e GPU, memoria e swap, rete, disco, salute
della batteria e consumo energetico — valori in tempo reale con grafici
sparkline, soglie di colore che imposti tu, °C/°F e una riga di uptime. Le
letture arrivano direttamente da macOS e si aggiornano solo mentre la
scheda è aperta.

### Cronologia degli appunti

Le ultime 100 cose copiate (fino a 300) — testo, immagini e file — un clic per
ricopiarle o incollarle direttamente nell'app precedente. I file copiati
vengono ricordati per nome (più file insieme appaiono come «nome +N»), e
incollando torna il file vero e proprio. Le password e gli altri input
nascosti non vengono mai salvati.

### Convertitore di file

Trascina sul pannello un gruppo di immagini, PDF, video o audio: JPEG, PNG,
HEIC, AVIF e WebP in uscita; compressione dei PDF; riduzione video in HEVC
con una stima delle dimensioni onesta e in tempo reale prima di convertire.
Tutto viene elaborato in locale.

### Gestore delle finestre

Aggancia le finestre a metà, quarti, terzi e al centro con un clic su un
glifo di zona o con una scorciatoia ⌃⌥ — senza app aggiuntive.

### Torrent

Un client BitTorrent leggero nello stesso pannello: trascina un file
.torrent o incolla un link magnet, scegli esattamente quali file scaricare —
prima o anche durante il download —, metti in pausa, riprendi e fai seeding,
con uno stop facoltativo al ratio 1.0. Il modulo è disattivato per
impostazione predefinita; attivandolo, il motore open source viene scaricato
come piccolo download separato (~26 MB, con firma verificata) che comunica
con Hop solo tramite una porta locale. Hop può anche diventare l'app
predefinita per i file .torrent e i link magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Torrent di Hop — client BitTorrent leggero nel pannello della barra dei menu">
</div>

### E il resto

Piccoli indicatori di stato sull'icona nella barra dei menu — tempo,
anti-stop, avvisi e attività torrent, a colori o monocromatici —, un test di
velocità integrato (networkQuality di Apple), temi scuro e chiaro con una
texture a grana di pellicola, scorciatoie globali, avvio al login e una
modalità sicura che recupera l'app da un loop di crash.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Monitor di sistema di Hop — grafici di CPU, GPU, memoria, rete, disco, batteria">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Convertitore di file di Hop — conversione in batch di immagini, PDF, video e audio">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Impostazioni di Hop — temi, moduli, scorciatoie, 18 lingue">
</div>

## 18 lingue

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — l'app segue la lingua di sistema fin dal primo
avvio.

## Privacy

Tutto gira in locale: nessun server, nessuna analitica, nessun account.
L'app tocca la rete solo per controllare gli aggiornamenti, quando avvii il
test di velocità integrato e — se attivi il modulo torrent — per scaricare
il motore una sola volta e trasportare il traffico torrent stesso. Gli
aggiornamenti e il motore torrent arrivano come archivi firmati e vengono
verificati con una firma Ed25519 prima dell'installazione.

Sito web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Gratis, ed ecco perché

Hop è completamente gratis: nessuna prova, nessuna versione pro, nessun
acquisto in-app. Niente pubblicità, niente raccolta dati, niente account: non
c'è nulla da monetizzare e nulla da vendere. È un progetto personale: ho creato
Hop per me, lo uso ogni giorno e semplicemente lo condivido. Se ti è utile,
passalo ad altri. E se vuoi contribuire, ora c'è un modo per sostenere Hop —
semplicemente un regalo, senza nulla in cambio.

## Compilare dai sorgenti

Swift Package Manager, macOS 14+, nessuna dipendenza esterna:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Il flusso di sviluppo, la pipeline di release e la specifica comportamentale
si trovano in [docs/development.md](../development.md) e
[docs/spec.md](../spec.md).

## Sostieni il progetto

Se Hop ti risparmia un clic o due, **[metti una stella al repo](https://github.com/antonyshakirov/hop/stargazers)** —
è grazie alle stelle che gli altri lo trovano. Segnalazioni di bug e idee
per nuove funzionalità sono benvenute nelle
[Issues](https://github.com/antonyshakirov/hop/issues).

## Autore e licenza

Creato da [Anton Shakirov](https://www.antonshakirov.com/en). Rilasciato con
[licenza MIT](../../LICENSE): usalo e modificalo liberamente, conserva la
nota di copyright — spacciare l'app per opera tua è una violazione della
licenza.
