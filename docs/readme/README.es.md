<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icono de la app Hop — asterisco de cuatro líneas">

# Hop

**Un pequeño compañero de barra de menús para macOS: temporizador,
seguimiento de tiempo, tareas pendientes, modo antisueño, monitor del
sistema, historial del portapapeles, conversor de archivos, gestor de
ventanas y un cliente de torrents ligero — repartidos en hasta cuatro
pestañas del icono. Un clic — y todo lo que necesitas está ahí.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · **Español** · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/es/panel.png" width="420" alt="Panel de Hop — temporizador en la barra de menús con pantalla de matriz de puntos, preajustes y ciclos de trabajo y descanso">

</div>

Hop vive en la barra de menús de tu Mac y sustituye a un puñado de pequeñas
utilidades: un temporizador estilo Pomodoro, un seguimiento de tiempo con
lista de tareas, un bloqueador de reposo al estilo de caffeinate, un monitor
del sistema, un gestor del portapapeles, un conversor de archivos por
arrastrar y soltar, un organizador de ventanas y un cliente de torrents
ligero — una sola app nativa y ligera, con los módulos que usas repartidos en
hasta cuatro pestañas del icono.

## Descarga

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — ábrelo y arrastra `Hop.app` a Aplicaciones (recomendado)
- `Hop-x.y.z.zip` — la misma app como archivo comprimido (lo usa el actualizador integrado); consulta la [última versión](https://github.com/antonyshakirov/hop/releases/latest)
- Espejo rápido: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primer arranque: clic derecho en `Hop.app` → **Abrir** → confirmar
(la app aún no está notarizada). Requiere macOS 14 o posterior.

## Funciones

### Espacios

El icono admite hasta cuatro pestañas, y arrastras cada módulo a la pestaña
que quieras: el temporizador en una, el monitor en otra, lo que abres rara
vez a un lado. Un estante «inactivos» guarda lo que apartas sin borrarlo.

### Temporizador y ciclos

Una cuenta atrás de matriz de puntos que ajustas con un solo gesto: arrastra
los dígitos, teclea la hora como en un microondas o elige un preajuste.
Ciclos de trabajo y descanso (25/5 Pomodoro, 52/17, 90/15 — o los tuyos),
un cronómetro, un almacén que conserva un temporizador en marcha mientras
pruebas otro, y una alerta de final que además puede pausar tus medios. Al
terminar la cuenta atrás suena una sola vez y los dígitos parpadean hasta que
lo reinicias.

### Seguimiento de tiempo y tareas

Lleva el tiempo sobre una lista plana de tareas: cada fila muestra el tiempo
de hoy y un total acumulado, y puedes corregir a mano la cifra de hoy. Si una
corre demasiado, a las ocho horas un aviso te lo recuerda. Al lado hay una
lista de pendientes aparte, donde lo terminado baja al fondo.

### Sin reposo

Mantén el Mac despierto 15 minutos, 8 horas o para siempre — un clic, sin
contraseña. Opcionalmente deja la pantalla encendida, o sigue trabajando
con la tapa cerrada (ideal para descargas, compilaciones largas y pantallas
externas).

### Monitor del sistema

Carga y temperatura de CPU y GPU, memoria y swap, red, disco, salud de la
batería y consumo de energía — valores en vivo con gráficos sparkline,
umbrales de color que defines tú mismo, °C/°F y una línea de tiempo de
actividad. Las lecturas vienen directamente de macOS y solo se actualizan
mientras la pestaña está abierta.

### Historial del portapapeles

Las últimas 100 cosas que copiaste (hasta 300) — texto, imágenes y archivos —
con un clic para volver a copiarlas o pegarlas directamente en la app
anterior. Los archivos copiados se guardan por su nombre (varios a la vez
aparecen como «nombre +N»), y al pegar vuelve el archivo en sí. Las
contraseñas y otras entradas ocultas nunca se guardan.

### Conversor de archivos

Suelta un lote de imágenes, PDF, vídeos o audio sobre el panel: JPEG, PNG,
HEIC, AVIF y WebP de salida; compresión de PDF; reducción de vídeo HEVC con
una estimación de tamaño honesta y en vivo antes de convertir. Todo se
procesa en local.

### Gestor de ventanas

Ajusta las ventanas a mitades, cuartos, tercios y al centro con un clic en
un glifo de zona o con un atajo ⌃⌥ — sin necesidad de otra app.

### Torrents

Un cliente BitTorrent ligero en el mismo panel: suelta un archivo .torrent o
pega un enlace magnet, elige exactamente qué archivos descargar — antes o
incluso durante la descarga —, pausa, reanuda y comparte como seed, con una
parada opcional al llegar al ratio 1.0. El módulo viene desactivado por
defecto; al activarlo se descarga el motor de código abierto como un pequeño
paquete aparte (~26 MB, con firma verificada) que solo se comunica con Hop a
través de un puerto local. Hop también puede convertirse en la app por
defecto para archivos .torrent y enlaces magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/torrents.png" width="420" alt="Torrents de Hop — cliente BitTorrent ligero en el panel de la barra de menús">
</div>

### Y todo lo demás

Pequeños indicadores de estado en el icono de la barra de menús — tiempo,
antisueño, avisos y actividad de torrents, en color o monocromos —, un test
de velocidad integrado (networkQuality de Apple), temas oscuro y claro con
textura de grano de película, atajos globales, arranque al iniciar sesión y
un modo seguro que recupera la app de un bucle de fallos.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/system.png" width="280" alt="Monitor del sistema de Hop — gráficos de CPU, GPU, memoria, red, disco y batería">
<img src="https://www.antonshakirov.com/products/hop/screens/es/converter.png" width="280" alt="Conversor de archivos de Hop — conversión por lotes de imágenes, PDF, vídeo y audio">
<img src="https://www.antonshakirov.com/products/hop/screens/es/settings.png" width="280" alt="Ajustes de Hop — temas, módulos, atajos, 18 idiomas">
</div>

## 18 idiomas

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — la app sigue el idioma de tu sistema desde el
primer momento.

## Privacidad

Todo funciona en local: sin servidor, sin analíticas, sin cuentas. La app
solo toca la red para buscar actualizaciones, cuando ejecutas el test de
velocidad integrado y — si activas el módulo de torrents — para descargar el
motor una única vez y mover el propio tráfico de torrents. Las
actualizaciones y el motor de torrents se entregan como archivos firmados y
se verifican con una firma Ed25519 antes de instalarse.

Sitio web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Gratis, y por qué

Hop es completamente gratis: sin prueba, sin versión pro, sin compras dentro
de la app. Sin anuncios, sin recopilación de datos, sin cuentas: no hay nada
que monetizar ni nada que vender. Es un proyecto personal: hice Hop para mí,
lo uso cada día y simplemente lo comparto. Si te resulta útil, pásalo. Y si
quieres aportar algo, ahora hay una forma de apoyar Hop — puramente un
regalo, sin nada a cambio.

## Compilar desde el código fuente

Swift Package Manager, macOS 14+, sin dependencias externas:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

El flujo de desarrollo, el pipeline de releases y la especificación de
comportamiento están en [docs/development.md](../development.md) y
[docs/spec.md](../spec.md).

## Apoya el proyecto

Si Hop te ahorra un clic o dos, **[dale una estrella al repo](https://github.com/antonyshakirov/hop/stargazers)** —
las estrellas son la forma en que otros lo encuentran. Los informes de
errores y las ideas de funciones son bienvenidos en
[Issues](https://github.com/antonyshakirov/hop/issues).

## Autor y licencia

Creado por [Anton Shakirov](https://www.antonshakirov.com/en). Publicado
bajo la [licencia MIT](../../LICENSE): úsalo y modifícalo libremente,
conserva el aviso de copyright — hacer pasar la app por obra propia es una
violación de la licencia.
