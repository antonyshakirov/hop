<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icône de l'app Hop — astérisque à quatre traits">

# Hop

**Un petit compagnon pour la barre de menus de macOS : minuteur, suivi du
temps, liste de tâches, anti-veille, moniteur système, historique du
presse-papiers, convertisseur de fichiers, gestionnaire de fenêtres et client
torrent léger — répartis sur jusqu'à quatre onglets de l'icône. Un clic — et
tout ce qu'il vous faut est là.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
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

Premier lancement : clic droit sur `Hop.app` → **Ouvrir** → confirmez
(l'app n'est pas encore notariée). Nécessite macOS 14 ou plus récent.

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

### Suivi du temps et tâches

Suivez le temps sur une liste de tâches à plat : chaque ligne montre le temps
du jour et un total cumulé, et vous pouvez corriger le chiffre du jour à la
main. Si l'une tourne trop longtemps, un bandeau vous le rappelle au bout de
huit heures. À côté, une liste de choses à faire distincte, où le terminé
descend en bas.

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

La ligne du module ouvre une fenêtre, et c'est là qu'on dépose. Dépose une
archive et elle s'ouvre là où elle se trouve ; dépose des fichiers ou des
dossiers et une archive apparaît à côté. zip, tar, tar.gz, tar.bz2, tar.xz et
gz fonctionnent tout de suite ; pour rar et 7z, un petit outil (~6 Mo) à la
signature vérifiée se télécharge la première fois. Hop extrait le rar mais ne
le crée jamais : le format est propriétaire. Active « ouvrir les archives avec
Hop » et un double clic les extrait via Hop, que le module soit visible dans le
panneau ou non.

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

### Reconnaissance de texte

Cadre une zone de l'écran, ou dépose une image dans la fenêtre et colle-en une
avec ⌘V : le texte et les codes QR sortent dans une fenêtre qu'on peut lire,
corriger et copier, et rejoignent en même temps l'historique du presse-papiers.
Les retours à la ligne sont gardés, un tableau reste donc lisible. La
reconnaissance, c'est Vision d'Apple, entièrement sur ce Mac.

### Verrou clavier

Appuie sur 1, 5 ou 15 minutes — ou ∞ — et tout le clavier cesse de répondre,
pour l'essuyer sans éteindre le Mac ni rabattre l'écran. Un cache explique ce
qui se passe et l'icône de la barre des menus devient un clavier. Quatre
sorties : le bouton du cache, le bouton du panneau, l'ouverture du panneau, ou
échap maintenu trois secondes. Une pression courte sur la touche d'alimentation
est avalée elle aussi ; la maintenir éteint toujours le Mac, car c'est le
matériel qui s'en charge.

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

## Confidentialité

Tout tourne en local : pas de serveur, pas d'analytics, pas de compte. L'app
ne touche au réseau que pour vérifier les mises à jour, quand vous lancez le
test de débit intégré et — si vous activez le module torrent — pour
récupérer le moteur une seule fois et acheminer le trafic torrent lui-même.
Les mises à jour et le moteur torrent sont livrés sous forme d'archives
signées et vérifiés avec une signature Ed25519 avant l'installation.

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

Si Hop vous économise un clic ou deux, **[mettez une étoile au repo](https://github.com/antonyshakirov/hop/stargazers)** —
c'est grâce aux étoiles que les autres le découvrent. Les rapports de bugs
et les idées de fonctionnalités sont les bienvenus dans les
[Issues](https://github.com/antonyshakirov/hop/issues).

## Auteur et licence

Créé par [Anton Shakirov](https://www.antonshakirov.com/en). Publié sous
[licence MIT](../../LICENSE) : utilisez et modifiez librement, conservez la
mention de copyright — présenter l'app comme votre propre travail est une
violation de la licence.
