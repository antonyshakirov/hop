<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icono de la app Hop — asterisco de cuatro líneas">

# Hop

**Un pequeño compañero de barra de menús para macOS: temporizador, modo
antisueño, monitor del sistema, historial del portapapeles, conversor de
archivos y gestor de ventanas. Un clic — y todo lo que necesitas está ahí.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · **Español** · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/es/panel.png" width="420" alt="Panel de Hop — temporizador en la barra de menús con pantalla de matriz de puntos, preajustes y ciclos de trabajo y descanso">

</div>

Hop vive en la barra de menús de tu Mac y sustituye a media docena de
pequeñas utilidades: un temporizador estilo Pomodoro, un bloqueador de
reposo al estilo de caffeinate, un monitor del sistema, un gestor del
portapapeles, un conversor de archivos por arrastrar y soltar y un
organizador de ventanas — una sola app nativa y ligera en lugar de seis.

## Descarga

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — ábrelo y arrastra `Hop.app` a Aplicaciones (recomendado)
- `Hop-x.y.z.zip` — la misma app como archivo comprimido (lo usa el actualizador integrado); consulta la [última versión](https://github.com/antonyshakirov/hop/releases/latest)
- Espejo rápido: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primer arranque: clic derecho en `Hop.app` → **Abrir** → confirmar
(la app aún no está notarizada). Requiere macOS 14 o posterior.

## Funciones

### Temporizador y ciclos

Una cuenta atrás de matriz de puntos que ajustas con un solo gesto: arrastra
los dígitos, teclea la hora como en un microondas o elige un preajuste.
Ciclos de trabajo y descanso (25/5 Pomodoro, 52/17, 90/15 — o los tuyos),
un cronómetro, un almacén que conserva un temporizador en marcha mientras
pruebas otro, y una alerta de final que además puede pausar tus medios.

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

Las últimas 100 cosas que copiaste (hasta 300), con un clic para volver a
copiarlas o pegarlas directamente en la app anterior. Las contraseñas y
otras entradas ocultas nunca se guardan.

### Conversor de archivos

Suelta un lote de imágenes, PDF, vídeos o audio sobre el panel: JPEG, PNG,
HEIC, AVIF y WebP de salida; compresión de PDF; reducción de vídeo HEVC con
una estimación de tamaño honesta y en vivo antes de convertir. Todo se
procesa en local.

### Gestor de ventanas

Ajusta las ventanas a mitades, cuartos, tercios y al centro con un clic en
un glifo de zona o con un atajo ⌃⌥ — sin necesidad de otra app.

### Y todo lo demás

Test de velocidad integrado (networkQuality de Apple), temas oscuro y claro
con textura de grano de película, atajos globales, arranque al iniciar
sesión y un modo seguro que recupera la app de un bucle de fallos.

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
solo toca la red para buscar actualizaciones y cuando ejecutas el test de
velocidad integrado. Las actualizaciones se entregan como archivos firmados
y se verifican con una firma Ed25519 antes de instalarse.

Sitio web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

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
