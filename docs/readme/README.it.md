<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icona dell'app Hop — asterisco a quattro linee">

# Hop

**Un piccolo compagno per la barra dei menu di macOS: timer, monitoraggio
del tempo, cose da fare, anti-stop, monitor di sistema, cronologia degli
appunti, convertitore di file, gestore delle finestre e un client torrent
leggero. Attivi quelli che ti servono e li distribuisci su fino a quattro
schede dell'icona. Un clic — e tutto ciò che ti serve è lì.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Fdownloads&color=ffd60a)](https://www.antonshakirov.com/api/hop/downloads)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · **Italiano** · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/overview.png" width="360" alt="Pannello di Hop — timer nella barra dei menu con display a matrice di punti, preset e cicli lavoro-pausa">

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
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — la stessa app come semplice archivio (usato dall'aggiornatore integrato); vedi l'[ultima release](https://github.com/antonyshakirov/hop/releases/latest)
- Mirror veloce: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primo avvio su macOS 15 o successivo: prova ad aprire Hop una volta, poi vai
in **Impostazioni di Sistema → Privacy e sicurezza → Apri comunque** e
conferma **Apri**. Hop non è notarizzata perché l'autore non ha accesso a
un'iscrizione all'Apple Developer Program. Il codice sorgente è pubblico e
gli aggiornamenti integrati vengono verificati con Ed25519. Richiede macOS
14 o successivo.

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

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/timer.png" width="420" alt="Hop — Timer e cicli">
</div>

### Monitoraggio del tempo e attività

Le attività si raccolgono in progetti, ognuno con la propria somma, e un
interruttore sopra l'elenco mostra oggi, la settimana o tutto. Un'attività in
corso conta la sessione del momento, da zero; il ✓ accanto la chiude e la riga
torna alla somma del periodo. Apri un'attività e ci sono tutti i suoi tratti:
cambiare la durata o il momento, aggiungere una sessione che nessuno ha
avviato o eliminarne una; le correzioni a mano stanno nello stesso elenco,
così le righe fanno il totale sopra. Se una va troppo a lungo, dopo otto ore
un banner te lo ricorda. Accanto c'è una lista di cose da fare a parte, dove
il completato scende in fondo.

Clicca su un'attività e la riga si apre: il testo completo sulla prima riga, una
descrizione sotto, una stella per i preferiti. Un'attività può avere un
promemoria — giorno, ora e i giorni della settimana che vuoi — e Hop avvisa: un
banner con «posticipa» e «fatto», un suono, un segno nella barra dei menu,
ciascuno attivabile a parte.

**Anche il tuo agente IA può aggiungere attività.** L'elenco è un normale file
JSON e Hop ne raccoglie le modifiche mentre è in esecuzione. Hop esegue anche
comandi da un file e capisce i link `hop://`: lo stesso agente, o un comando
rapido costruito su uno di quei link, può avviare un timer, aggiungere
un'attività con promemoria o leggere cosa sta girando. Vedi
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/tracker.png" width="420" alt="Hop — Monitoraggio del tempo e attività">
</div>

### Niente stop

Tieni il Mac sveglio per 15 minuti, 8 ore o per sempre — un clic, nessuna
password. Facoltativamente tieni acceso lo schermo, oppure continua a
lavorare con il coperchio chiuso (comodo per download, build lunghe e
schermi esterni).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/awake.png" width="420" alt="Hop — Niente stop">
</div>

### Monitor di sistema

Carico e temperatura di CPU e GPU, memoria e swap, rete, disco, salute della
batteria e consumo energetico — valori in tempo reale con grafici sparkline,
soglie di colore che imposti tu, °C/°F e una riga di uptime. Le letture
arrivano direttamente da macOS e si aggiornano solo mentre la scheda è aperta.
La riga della memoria avvisa anche quando molta memoria è finita su disco, non
solo quando macOS stesso segnala difficoltà.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="420" alt="Hop — Monitor di sistema">
</div>

### Cronologia degli appunti

Le ultime 100 cose copiate (fino a 300) — testo, immagini e file — un clic per
ricopiarle o incollarle direttamente nell'app precedente. I file copiati
vengono ricordati per nome (più file insieme appaiono come «nome +N»), e
incollando torna il file vero e proprio. Le password e gli altri input
nascosti non vengono mai salvati.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clipboard.png" width="420" alt="Hop — Cronologia degli appunti">
</div>

### Convertitore di file

Trascina sul pannello un gruppo di immagini, PDF, video o audio: JPEG, PNG,
HEIC, AVIF e WebP in uscita; compressione dei PDF; riduzione video in HEVC con
una stima delle dimensioni onesta e in tempo reale prima di convertire. Tutto
viene elaborato in locale. Il video si può anche reinquadrare durante la
conversione — 9:16, 4:5, quadrato o 16:9, ritagliato, con bande o su una copia
sfocata — e la compressione ha un livello suo, così la dimensione promessa è
quella che esce.

Un pulsante prepara la clip per la sua destinazione — reels, feed, tiktok,
shorts o youtube — impostando inquadratura, risoluzione e compressione secondo
il consiglio della piattaforma, con il bitrate risultante accanto al cursore.
MKV e WebM vengono prima reimpacchettati in MP4 (macOS non apre né l'uno né
l'altro) da un piccolo aiutante che si scarica una volta. I documenti Pages,
Numbers e Keynote li esportano in blocco le app stesse: in PDF, oppure in
docx, xlsx e pptx.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="480" alt="Hop — Convertitore di file">
</div>

### Gestore delle finestre

Aggancia le finestre a metà, quarti, terzi e al centro con un clic su un
glifo di zona o con una scorciatoia ⌃⌥ — senza app aggiuntive.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/windows.png" width="420" alt="Hop — Gestore delle finestre">
</div>

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

### Archivi di file

La riga del modulo apre una finestra, ed è lì che si trascina — ⌘V funziona
anche, con più file insieme. Quello che aggiungi aspetta in un elenco finché non
premi il pulsante: gli archivi vengono estratti, tutto il resto finisce in un
unico archivio. Il risultato va sulla scrivania per impostazione predefinita,
oppure accanto all'originale o in una cartella a scelta. Sono supportati zip,
rar, 7z, tar, tar.gz, tar.bz2, tar.xz e gz; per rar e 7z alla prima occasione si
scarica un piccolo aiutante (~6 MB) con firma verificata. Hop estrae i rar ma
non li crea mai: il formato è proprietario. «Hop come predefinito per gli archivi» nelle impostazioni
propone solo rar quando nessuna app Apple lo gestisce e può riprenderlo dalle app
di terze parti; zip, 7z e i formati nativi restano a Utility Archivio.
Funziona con il modulo nascosto, e la scheda mostra lo stato reale. Un doppio clic su un archivio nel Finder lo estrae proprio accanto al file, in una piccola finestra di avanzamento tutta sua, e un errore non lascia dietro nulla di nascosto. I file che Hop apre portano una sua icona con il formato scritto sopra, così una cartella si legge a colpo d'occhio.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/archives.png" width="480" alt="Hop — Archivi di file">
</div>

### Documenti

Il convertitore ha imparato i documenti: markdown → PDF impaginato da Hop
stesso, file Word (.docx, .doc, .rtf) → PDF o markdown, e il testo di un PDF
come markdown — una pagina scansionata la legge Vision di Apple. Nativo e
offline, senza suite d'ufficio inclusa e senza download.

### Selettore colore

Prendi qualsiasi colore dallo schermo con la lente di sistema: resta in un
elenco, ogni riga con hex, rgb e hsl nella propria colonna — un clic copia
quella notazione. L'ordine non cambia mai sotto il cursore, quanti colori
tenere e quante righe mostrare sono impostazioni, e non serve il permesso di
registrazione schermo: la lente restituisce un colore e basta.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/colors.png" width="420" alt="Hop — Selettore colore">
</div>

### Riconoscimento del testo

Inquadra un'area dello schermo, oppure trascina un'immagine nella finestra e
incollane una con ⌘V: il testo e i codici QR escono in una finestra dove si
legge, si corregge e si copia, e finiscono insieme nella cronologia degli
appunti. Le andate a capo restano, così una tabella rimane leggibile. Il
riconoscimento è Vision di Apple, tutto su questo Mac.

Se il risultato contiene un indirizzo web compare il pulsante «apri il link»:
il link di un codice QR su una fattura si apre direttamente nel browser, senza
prendere il telefono. Solo indirizzi web: un codice scansionato è input
altrui, quindi un numero, una password Wi-Fi o un biglietto da visita restano
testo semplice.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/recognition.png" width="480" alt="Hop — Riconoscimento del testo">
</div>

### Blocco tastiera

Tocca 1, 5 o 15 minuti — oppure ∞ — e tutta la tastiera smette di rispondere,
per pulirla senza spegnere il Mac né chiudere il coperchio. Una copertura
spiega cosa sta succedendo e l'icona nella barra dei menu diventa una tastiera.
Quattro vie d'uscita: il pulsante sulla copertura, il pulsante nel pannello,
aprire il pannello, o tenere esc + shift per cinque secondi. Anche una pressione breve del
tasto di accensione viene ingoiata; tenerlo premuto spegne comunque il Mac,
perché di quello si occupa l'hardware.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/keyboard.png" width="480" alt="Hop — Blocco tastiera">
</div>

### Test di velocità

Un tocco misura la connessione con il networkQuality di macOS contro i server Apple — download, upload e reattività, e l'ultimo risultato resta nella riga.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/speed.png" width="420" alt="Hop — Test di velocità">
</div>

### L'icona nella barra dei menu

L'icona porta piccoli segni: il tempo in corso, l'anti-sospensione, un promemoria che
è suonato, un punto finché una VPN è su (arancione se smette di far passare qualcosa)
e frecce finché i torrent si muovono — a colori o monocromatici, ognuno disattivabile.
Le finestre di Hop compaiono nel Dock finché sono aperte, così un clic ne riporta una
invece di aprire il pannello, e l'icona se ne va con l'ultima finestra.

### Temi, scorciatoie e modalità sicura

Temi scuro e chiaro con texture a grana di pellicola, scorciatoie globali, avvio all'accesso e una modalità sicura che tira fuori l'app da un ciclo di crash — tutto in una finestra di impostazioni.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="480" alt="Hop — Impostazioni">
</div>

### VPN

Tutte le VPN che il tuo Mac conosce, ciascuna col suo interruttore, di qualunque
fornitore. Hop legge l'elenco direttamente dalle impostazioni di sistema: un
client installato ieri compare da solo, uno rimosso sparisce. Qui non c'è nulla da
aggiungere né da configurare.

Collega e scollega senza aprire niente. Finché un tunnel è su, un puntino sta
nell'angolo dell'icona nella barra dei menu, accanto agli altri indicatori: verde
finché qualcosa passa, arancione quando il tunnel è acceso ma non torna indietro
nulla. Una connessione morta in silenzio smette così di sembrare sana, e il pannello
indica la riga di cui si tratta. Clicca il nome e si apre la finestra di quella VPN
quando serve; quando la chiudi, Hop chiude l'app. La connessione resta: il tunnel lo
tiene il sistema, non l'app.

La riga mostra ciò che il client stesso dichiara: il nome e, tra parentesi, quello
che la configurazione aggiunge, di solito il paese. Hop non indovina mai il paese
dall'indirizzo del server: il registro dice dove è registrato l'intervallo, non
dove sta la macchina.

Il punto si può spegnere nelle impostazioni: il modulo e i suoi interruttori funzionano lo stesso.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/vpn.png" width="420" alt="Hop — Interruttori VPN">
</div>

### App

Una griglia con i programmi che apri tutto il giorno, a un clic e senza passare
dalla cartella Applicazioni. Premi + e scegli, oppure trascinali dal Finder:
nove per riga, fino a otto righe.

Trascina un'icona per spostarla: una linea gialla mostra tra quali due icone
finirà e le altre si spostano, come in una schermata home. Il pulsante di
modifica avvia l'oscillazione, ogni icona riceve una ✕ e la griglia può avere un
nome proprio; lì si spengono anche i nomi sotto le icone, se riconosci le tue
app a colpo d'occhio. Puoi tenere quante griglie vuoi — il lavoro su uno spazio,
il resto su un altro — ognuna con le sue app.

Le griglie si creano e si eliminano dove sistemi i moduli: nelle impostazioni o
nella tabella dei moduli stessa, dove la ✕ sulla targhetta di una griglia la
cancella per sempre. Una griglia nuova parte vuota e lo dice finché non la
riempi.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/apps.png" width="420" alt="Hop — Griglia di app">
</div>

### Rimuovere app

Trascina un'app sulla riga, o scegliela dall'elenco di tutto ciò che è installato, e se ne va insieme a quello che ha lasciato in una trentina di posti: application support, cache, preferenze, container, launch agent, plug-in, ricevute e il resto. Ogni app dell'elenco mostra quanto pesa, il bundle e i dati separati. Un'app già nel cestino viene comunque riconosciuta: l'identificativo si legge dal bundle che sta lì, o si ricava dai resti che lo nominano.

Niente viene cancellato. Tutto va nel cestino, quindi un errore costa un ripristino e non un file, e ciò che macOS non consegna è detto con il motivo invece di essere saltato in silenzio.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/uninstall.png" width="480" alt="Hop — Rimuovere un'app con tutto ciò che ha lasciato">
</div>

Lo stesso modulo mette ordine senza rimuovere nulla: ogni app che tiene una cache, le più grandi prima; gli installer rimasti in Download, sulla Scrivania e in Documenti; i dati di app cancellate anni fa; e il cestino con la sua dimensione. Una spunta prende un'intera sezione. Anche ciò che lascia stare di proposito è elencato — un container dove cache e dati stanno insieme, i venti giga di una messaggistica compresi: solo quell'app sa quale metà è superflua.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clean.png" width="480" alt="Hop — Svuotare cache, installer, resti e cestino">
</div>

## 22 lingue

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — l'app segue la lingua di sistema fin dal primo
avvio.

## Sostieni il progetto

Hop è gratis e resterà tale. Se si guadagna un posto nella tua barra dei menu, un
contributo volontario aiuta a far uscire funzioni nuove e a rifinire quelle che
ci sono: paga il tempo, nient'altro.

**[→ Sostenere Hop](https://web.tribute.tg/d/Nvk)**

## Privacy — e perché i permessi si possono dare tranquillamente

**Hop non raccoglie nulla. Né ora né poi.** Nessun server proprio, nessuna
analytics, nessuna telemetria, nessun account, nessun report di crash. Ogni
permesso qui sotto viene chiesto da macOS solo quando usi la funzione che ne ha
bisogno, ed esiste esattamente per quella — niente viene raccolto per strada.
Non serve crederci sulla parola: l'app è open source, e il codice che dovrebbe
raccogliere semplicemente non c'è. Cerca in questo repository un SDK di tracking
o una chiamata di analytics: non ne troverai.

Tutto gira in locale: nessun server, nessuna analitica, nessun account.
L'app tocca la rete solo per controllare gli aggiornamenti, quando avvii il
test di velocità integrato e — se attivi il modulo torrent — per scaricare
il motore una sola volta e trasportare il traffico torrent stesso. Il
controllo degli aggiornamenti invia la versione che stai usando, e nulla che
identifichi te o il tuo Mac. Gli aggiornamenti e il motore torrent arrivano
come archivi firmati e vengono verificati con una firma Ed25519 prima
dell'installazione.

## Permessi

Hop chiede un permesso solo quando usi davvero la funzione che lo richiede; la
finestra informazioni li elenca tutti con il loro stato attuale:

- **rete — antonshakirov.com** — cercare e scaricare aggiornamenti, più i due
  aiutanti opzionali (motore torrent e archiviatore 7-Zip)
- **rete — torrent, test di velocità** — traffico verso altri peer con il modulo
  torrent attivo; il test usa networkQuality di macOS verso i server di Apple
- **accessibilità** — incollare nell'app sottostante, il gestore finestre e il
  blocco tastiera
- **registrazione schermo** — solo il riconoscimento del testo, e solo quando
  inquadra un'area; il selettore colore non ne ha bisogno
- **notifiche** — l'avviso del timer e un torrent completato
- **password di amministratore** — una volta, per la modalità a coperchio chiuso
  (pmset gira solo come root)
- **apri all'accesso** — spento finché non lo accendi

All'avvio non viene chiesto nulla, e nulla viene chiesto per un modulo che non hai
attivato. Nessuna analytics, nessuna telemetria, nessun account, nessun report di
crash: antonshakirov.com viene contattato solo per chiedere se esiste una
versione più recente — e per scaricarla, o uno dei due aiutanti opzionali, se
acconsenti. Tutto il resto resta su questo Mac: la cronologia degli appunti, il
tempo registrato, la lista di cose da fare, il testo riconosciuto e i colori.

Ogni permesso qui sopra serve a far funzionare una funzione — e a nient'altro.
Non serve crederci sulla parola: Hop è open source, e il codice che dovrebbe
raccogliere semplicemente non c'è — leggilo in questo repository. La finestra di
informazioni dell'app ha una scheda «permessi dell'app» con lo stesso elenco e
lo stato attuale di ciascuno.

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

Tre modi, tutti graditi:

- **[Sostenere Hop con un contributo](https://web.tribute.tg/d/Nvk)** — va diretto
  in funzioni nuove e correzioni. Volontario, senza premi, senza nulla a
  pagamento: ogni modulo è uguale per tutti.
- **[Mettere una stella al repo](https://github.com/antonyshakirov/hop/stargazers)** —
  è dalle stelle che lo trovano gli altri.
- **[Aprire una issue](https://github.com/antonyshakirov/hop/issues)** — una
  segnalazione o un'idea valgono lo stesso.

## Autore e licenza

Creato da [Anton Shakirov](https://www.antonshakirov.com/en). Rilasciato con
[licenza MIT](../../LICENSE): usalo e modificalo liberamente, conserva la
nota di copyright — spacciare l'app per opera tua è una violazione della
licenza.
