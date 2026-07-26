<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icône de l'app Hop — astérisque à quatre traits">

# Hop

**Un petit compagnon pour la barre de menus de macOS : minuteur, suivi du
temps, liste de tâches, anti-veille, moniteur système, historique du
presse-papiers, convertisseur de fichiers, gestionnaire de fenêtres et client
torrent léger — répartis sur jusqu'à quatre onglets de l'icône. Un clic — et
tout ce qu'il vous faut est là.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · **Français** · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/fr/panel.png" width="420" alt="Panneau Hop — minuteur dans la barre de menus avec affichage à matrice de points, préréglages et cycles travail-pause">

</div>

Hop vit dans la barre de menus de votre Mac et remplace une poignée de petits
utilitaires : un minuteur façon Pomodoro, un suivi du temps avec liste de
tâches, un bloqueur de veille façon caffeinate, un moniteur système, un
gestionnaire de presse-papiers, un convertisseur de fichiers par
glisser-déposer, un outil d'ancrage de fenêtres et un client torrent léger —
une seule app native et légère, dont les modules se répartissent sur jusqu'à
quatre onglets de l'icône.

## Téléchargement

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — ouvrez-le et glissez `Hop.app` dans Applications (recommandé)
- `Hop-x.y.z.zip` — la même app en archive simple (utilisée par le système de mise à jour intégré) ; voir la [dernière release](https://github.com/antonyshakirov/hop/releases/latest)
- Miroir rapide : [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Premier lancement sous macOS 15 ou plus récent : essayez d'ouvrir Hop une
fois, puis allez dans **Réglages Système → Confidentialité et sécurité →
Ouvrir quand même** et confirmez **Ouvrir**. Hop n'est pas notariée, car
l'auteur ne dispose pas d'une adhésion à l'Apple Developer Program. Le code
source est public et les mises à jour intégrées sont vérifiées avec Ed25519.
Nécessite macOS 14 ou plus récent.

## Fonctionnalités

### Espaces

L'icône accueille jusqu'à quatre onglets, et vous glissez chaque module dans
l'onglet de votre choix : le minuteur sur l'un, le moniteur sur l'autre, ce
que vous ouvrez rarement à l'écart. Une étagère « inactifs » conserve ce que
vous mettez de côté, sans le supprimer.

### Minuteur et cycles

Un compte à rebours à matrice de points que vous réglez d'un seul geste :
faites glisser les chiffres, tapez la durée comme sur un micro-ondes, ou
choisissez un préréglage. Des cycles travail-pause (Pomodoro 25/5, 52/17,
90/15 — ou les vôtres), un chronomètre, une mise de côté qui garde un
minuteur en cours pendant que vous en essayez un autre, et une alerte de fin
qui peut aussi mettre vos médias en pause. À la fin du compte à rebours, un
seul son retentit et les chiffres clignotent jusqu'à la réinitialisation.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/timer.png" width="420" alt="Hop — Minuteur et cycles">
</div>

### Suivi du temps et tâches

Suivez le temps sur une liste de tâches à plat : chaque ligne montre le temps
du jour et un total cumulé, et vous pouvez corriger le chiffre du jour à la
main. Si l'une tourne trop longtemps, un bandeau vous le rappelle au bout de
huit heures. À côté, une liste de choses à faire distincte, où le terminé
descend en bas.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/tracker.png" width="420" alt="Hop — Suivi du temps et tâches">
</div>

### Anti-veille

Gardez le Mac éveillé pendant 15 minutes, 8 heures ou pour toujours — un
clic, pas de mot de passe. En option, gardez l'écran allumé, ou continuez à
travailler avec le couvercle fermé (pratique pour les téléchargements, les
longues compilations et les écrans externes).

### Moniteur système

Charge et température du CPU et du GPU, mémoire et swap, réseau, disque,
santé de la batterie et consommation électrique — des valeurs en direct avec
des graphiques sparkline, des seuils de couleur que vous définissez
vous-même, °C/°F, et une ligne d'uptime. Les mesures viennent directement de
macOS et ne se rafraîchissent que lorsque l'onglet est ouvert.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/system.png" width="420" alt="Hop — Moniteur système">
</div>

### Historique du presse-papiers

Les 100 derniers éléments copiés (jusqu'à 300) — texte, images et fichiers —
un clic pour les recopier ou les coller directement dans l'app précédente.
Les fichiers copiés sont retenus par leur nom (plusieurs à la fois
apparaissent en « nom +N »), et le collage ramène le fichier lui-même. Les
mots de passe et autres saisies masquées ne sont jamais enregistrés.

### Convertisseur de fichiers

Déposez un lot d'images, de PDF, de vidéos ou d'audio sur le panneau : JPEG,
PNG, HEIC, AVIF et WebP en sortie ; compression de PDF ; réduction vidéo en
HEVC avec une estimation de taille honnête et en direct avant de convertir.
Tout est traité en local.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/converter.png" width="480" alt="Hop — Convertisseur de fichiers">
</div>

### Gestionnaire de fenêtres

Ancrez les fenêtres en moitiés, quarts, tiers et au centre d'un clic sur un
glyphe de zone ou avec un raccourci ⌃⌥ — sans app supplémentaire.

### Torrents

Un client BitTorrent léger dans le même panneau : déposez un fichier
.torrent ou collez un lien magnet, choisissez précisément les fichiers à
télécharger — avant ou même pendant le téléchargement —, mettez en pause,
reprenez et laissez en seed, avec un arrêt optionnel au ratio 1.0. Le module
est désactivé par défaut ; l'activer récupère le moteur open source sous
forme d'un petit téléchargement séparé (~26 Mo, signature vérifiée) qui ne
communique avec Hop que par un port local. Hop peut aussi devenir l'app par
défaut pour les fichiers .torrent et les liens magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/torrents.png" width="420" alt="Torrents Hop — client BitTorrent léger dans le panneau de la barre de menus">
</div>

### Archives de fichiers

La ligne du module ouvre une fenêtre, et c'est là qu'on dépose — ⌘V marche
aussi, plusieurs fichiers à la fois. Ce que tu ajoutes attend dans une liste
jusqu'à ce que tu appuies sur le bouton : les archives sont extraites, tout le
reste part dans une seule archive. Le résultat va sur le bureau par défaut, ou à
côté de l'original, ou dans le dossier de ton choix. Sont pris en charge zip,
rar, 7z, tar, tar.gz, tar.bz2, tar.xz et gz ; pour rar et 7z, un petit outil
(~6 Mo) à la signature vérifiée se télécharge la première fois. Hop extrait le
rar mais ne le crée jamais : le format est propriétaire. « Hop par défaut pour les archives »
dans les réglages prend les formats que macOS n'ouvre pas lui-même — rar et 7z
en premier — et les reprend aux apps tierces ; zip et tar restent à Utilitaire
d'archive. Ça marche avec le module masqué, et la carte affiche l'état réel.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/archives.png" width="480" alt="Hop — Archives de fichiers">
</div>

### Documents

Le convertisseur sait faire des documents : markdown → PDF composé par Hop
lui-même, fichiers Word (.docx, .doc, .rtf) → PDF ou markdown, et le texte d'un
PDF en markdown — une page scannée est lue par Vision d'Apple. Natif et hors
ligne, sans suite bureautique embarquée ni téléchargement.

### Pipette à couleurs

Prélève n'importe quelle couleur de l'écran avec la loupe du système : elle
reste dans une liste, chaque ligne portant hex, rgb et hsl dans sa propre
colonne — un clic copie cette notation-là. L'ordre ne change jamais sous le
curseur, le nombre de couleurs gardées et de lignes visibles se règle, et
aucune autorisation d'enregistrement d'écran n'est nécessaire : la loupe rend
une seule couleur.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/colors.png" width="420" alt="Hop — Pipette à couleurs">
</div>

### Reconnaissance de texte

Cadre une zone de l'écran, ou dépose une image dans la fenêtre et colle-en une
avec ⌘V : le texte et les codes QR sortent dans une fenêtre qu'on peut lire,
corriger et copier, et rejoignent en même temps l'historique du presse-papiers.
Les retours à la ligne sont gardés, un tableau reste donc lisible. La
reconnaissance, c'est Vision d'Apple, entièrement sur ce Mac.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/recognition.png" width="480" alt="Hop — Reconnaissance de texte">
</div>

### Verrou clavier

Appuie sur 1, 5 ou 15 minutes — ou ∞ — et tout le clavier cesse de répondre,
pour l'essuyer sans éteindre le Mac ni rabattre l'écran. Un cache explique ce
qui se passe et l'icône de la barre des menus devient un clavier. Quatre
sorties : le bouton du cache, le bouton du panneau, l'ouverture du panneau, ou
échap + maj maintenus cinq secondes. Une pression courte sur la touche d'alimentation
est avalée elle aussi ; la maintenir éteint toujours le Mac, car c'est le
matériel qui s'en charge.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/keyboard.png" width="480" alt="Hop — Verrou clavier">
</div>

### Et le reste

De petits indicateurs d'état sur l'icône de la barre de menus — temps,
anti-veille, alertes et activité torrent, en couleur ou monochromes —, un
test de débit intégré (networkQuality d'Apple), thèmes sombre et clair avec
une texture grain de film, raccourcis globaux, lancement à l'ouverture de
session, et un mode sans échec qui récupère l'app après une boucle de crash.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/system.png" width="280" alt="Moniteur système Hop — graphiques CPU, GPU, mémoire, réseau, disque, batterie">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/converter.png" width="280" alt="Convertisseur de fichiers Hop — conversion par lots d'images, PDF, vidéos et audio">
<img src="https://www.antonshakirov.com/products/hop/screens/fr/settings.png" width="280" alt="Réglages de Hop — thèmes, modules, raccourcis, 18 langues">
</div>

## 18 langues

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — l'app suit la langue de votre système dès
l'installation.

## Soutenir le projet

Hop est gratuit et le restera. S'il mérite sa place dans ta barre des menus, une
contribution volontaire aide à sortir de nouvelles fonctions et à peaufiner
celles qui existent : elle paie le temps que ça prend, rien d'autre.

**[→ Soutenir Hop](https://web.tribute.tg/d/Nvk)**

## Confidentialité — et pourquoi les autorisations sont sans risque

**Hop ne collecte rien. Ni maintenant, ni plus tard.** Pas de serveur à lui, pas
d'analytique, pas de télémétrie, pas de comptes, pas de rapports de plantage.
Chaque autorisation ci-dessous est demandée par macOS uniquement quand la
fonction qui en a besoin est utilisée, et elle sert exactement à ça — rien n'est
collecté au passage. Tu n'as pas à me croire sur parole : l'app est open source,
le code qui collecterait n'existe tout simplement pas. Cherche un SDK de tracking
ou un appel d'analytique dans ce dépôt : tu n'en trouveras aucun.

Tout tourne en local : pas de serveur, pas d'analytics, pas de compte. L'app
ne touche au réseau que pour vérifier les mises à jour, quand vous lancez le
test de débit intégré et — si vous activez le module torrent — pour
récupérer le moteur une seule fois et acheminer le trafic torrent lui-même.
Cette vérification des mises à jour envoie la version que vous utilisez, et
rien qui vous identifie, vous ou votre Mac. Les mises à jour et le moteur
torrent sont livrés sous forme d'archives signées et vérifiés avec une
signature Ed25519 avant l'installation.

## Autorisations

Hop ne demande une autorisation qu'au moment où la fonction concernée est
vraiment utilisée ; la fenêtre d'informations les liste toutes avec leur état :

- **réseau — antonshakirov.com** — chercher et télécharger les mises à jour,
  plus les deux outils optionnels (moteur torrent et archiveur 7-Zip)
- **réseau — torrents, test de débit** — trafic vers les autres pairs quand le
  module torrent est activé ; le test utilise networkQuality de macOS vers les
  serveurs d'Apple
- **accessibilité** — coller dans l'app en dessous, le gestionnaire de fenêtres
  et le verrou clavier
- **enregistrement de l'écran** — uniquement la reconnaissance de texte, et
  seulement au cadrage d'une zone ; la pipette n'en a pas besoin
- **notifications** — l'alerte du minuteur et un torrent terminé
- **mot de passe administrateur** — une fois, pour le mode écran rabattu (pmset
  est réservé à root)
- **ouvrir à la session** — désactivé tant que tu ne l'actives pas

Rien n'est demandé au lancement, et rien n'est demandé pour un module que tu n'as
pas activé. Pas d'analytique, pas de télémétrie, pas de compte, pas de rapport de
plantage : antonshakirov.com n'est contacté que pour demander s'il existe une
version plus récente — et pour la télécharger, ou l'un des deux outils
optionnels, si tu acceptes. Tout le reste reste sur ce Mac : l'historique du
presse-papiers, le temps suivi, la liste de tâches, le texte reconnu, les
couleurs prélevées.

Chaque autorisation ci-dessus sert à faire fonctionner une fonction — et à rien
d'autre. Tu n'as pas à me croire sur parole : Hop est open source, le code qui
collecterait n'existe tout simplement pas — lis-le dans ce dépôt. La fenêtre
d'informations de l'app a un onglet « autorisations de l'app » avec la même
liste et l'état actuel de chacune.

Site web : [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Gratuit, et pourquoi

Hop est entièrement gratuit : pas d'essai, pas de version pro, pas d'achats
intégrés. Pas de publicité, pas de collecte de données, pas de comptes — il
n'y a rien à monétiser ni rien à vendre. C'est un projet personnel : j'ai créé
Hop pour moi, je l'utilise chaque jour et je le partage, tout simplement. S'il
vous est utile, faites-le passer. Et si vous voulez contribuer, il est
désormais possible de soutenir Hop — un simple cadeau, sans contrepartie.

## Compiler depuis les sources

Swift Package Manager, macOS 14+, aucune dépendance externe :

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Le workflow de développement, le pipeline de release et la spécification
comportementale se trouvent dans [docs/development.md](../development.md) et
[docs/spec.md](../spec.md).

## Soutenir le projet

Trois façons, toutes bienvenues :

- **[Soutenir Hop par une contribution](https://web.tribute.tg/d/Nvk)** — elle va
  droit dans les nouvelles fonctions et les correctifs. Volontaire, sans
  contrepartie, rien derrière un paywall : chaque module est le même pour tous.
- **[Mettre une étoile au dépôt](https://github.com/antonyshakirov/hop/stargazers)** —
  c'est par les étoiles que les autres le trouvent.
- **[Ouvrir une issue](https://github.com/antonyshakirov/hop/issues)** — un
  rapport de bug ou une idée valent autant.

## Auteur et licence

Créé par [Anton Shakirov](https://www.antonshakirov.com/en). Publié sous
[licence MIT](../../LICENSE) : utilisez et modifiez librement, conservez la
mention de copyright — présenter l'app comme votre propre travail est une
violation de la licence.
