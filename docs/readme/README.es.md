<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Icono de la app Hop — asterisco de cuatro líneas">

# Hop

**Un pequeño compañero de barra de menús para macOS: temporizador,
seguimiento de tiempo, tareas pendientes, modo antisueño, monitor del
sistema, historial del portapapeles, conversor de archivos, gestor de
ventanas y un cliente de torrents ligero — repartidos en hasta cuatro
pestañas del icono. Un clic — y todo lo que necesitas está ahí.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · **Español** · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/es/overview.png" width="360" alt="Panel de Hop — temporizador en la barra de menús con pantalla de matriz de puntos, preajustes y ciclos de trabajo y descanso">

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
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — la misma app como archivo comprimido (lo usa el actualizador integrado); consulta la [última versión](https://github.com/antonyshakirov/hop/releases/latest)
- Espejo rápido: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primer arranque en macOS 15 o posterior: intenta abrir Hop una vez, ve a
**Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente** y
confirma **Abrir**. Hop no está notarizada porque el autor no dispone de una
membresía del Apple Developer Program. El código fuente es público y las
actualizaciones integradas se verifican con Ed25519. Requiere macOS 14 o
posterior.

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

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/timer.png" width="420" alt="Hop — Temporizador y ciclos">
</div>

### Seguimiento de tiempo y tareas

Lleva el tiempo sobre una lista plana de tareas: cada fila muestra el tiempo
de hoy y un total acumulado, y puedes corregir a mano la cifra de hoy. Si una
corre demasiado, a las ocho horas un aviso te lo recuerda. Al lado hay una
lista de pendientes aparte, donde lo terminado baja al fondo.

Haz clic en una tarea y la fila se abre: el texto completo en la primera línea,
una descripción debajo y una estrella para los favoritos. Un pendiente puede
llevar un recordatorio — día, hora y los días de la semana que quieras — y Hop
avisa: un aviso con «posponer» y «hecho», un sonido, una marca en la barra de
menús; cada uno se activa por separado.

**Tu propio agente de IA también puede añadir tareas.** La lista es un archivo
JSON normal y Hop recoge los cambios mientras funciona. Hop también ejecuta
órdenes desde un archivo y entiende enlaces `hop://`: ese mismo agente, o un
atajo construido sobre uno de esos enlaces, puede iniciar un temporizador, añadir
una tarea con recordatorio o consultar qué está en marcha. Ver
[docs/automation.md](../automation.md).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/tracker.png" width="420" alt="Hop — Seguimiento de tiempo y tareas">
</div>

### Sin reposo

Mantén el Mac despierto 15 minutos, 8 horas o para siempre — un clic, sin
contraseña. Opcionalmente deja la pantalla encendida, o sigue trabajando
con la tapa cerrada (ideal para descargas, compilaciones largas y pantallas
externas).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/awake.png" width="420" alt="Hop — Sin reposo">
</div>

### Monitor del sistema

Carga y temperatura de CPU y GPU, memoria y swap, red, disco, salud de la
batería y consumo de energía — valores en vivo con gráficos sparkline,
umbrales de color que defines tú mismo, °C/°F y una línea de tiempo de
actividad. Las lecturas vienen directamente de macOS y solo se actualizan
mientras la pestaña está abierta. La fila de memoria también avisa cuando
mucha memoria ha ido al disco, y no solo cuando macOS informa de que va justo.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/system.png" width="420" alt="Hop — Monitor del sistema">
</div>

### Historial del portapapeles

Las últimas 100 cosas que copiaste (hasta 300) — texto, imágenes y archivos —
con un clic para volver a copiarlas o pegarlas directamente en la app
anterior. Los archivos copiados se guardan por su nombre (varios a la vez
aparecen como «nombre +N»), y al pegar vuelve el archivo en sí. Las
contraseñas y otras entradas ocultas nunca se guardan.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/clipboard.png" width="420" alt="Hop — Historial del portapapeles">
</div>

### Conversor de archivos

Suelta un lote de imágenes, PDF, vídeos o audio sobre el panel: JPEG, PNG,
HEIC, AVIF y WebP de salida; compresión de PDF; reducción de vídeo HEVC con
una estimación de tamaño honesta y en vivo antes de convertir. Todo se
procesa en local.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/converter.png" width="480" alt="Hop — Conversor de archivos">
</div>

### Gestor de ventanas

Ajusta las ventanas a mitades, cuartos, tercios y al centro con un clic en
un glifo de zona o con un atajo ⌃⌥ — sin necesidad de otra app.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/windows.png" width="420" alt="Hop — Gestor de ventanas">
</div>

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

### Archivos comprimidos

La fila del módulo abre una ventana, y ahí es donde se sueltan las cosas — ⌘V
también funciona, con varios archivos a la vez. Lo que añades espera en una
lista hasta que pulsas el botón: los comprimidos se extraen y todo lo demás se
junta en un comprimido. El resultado va al escritorio por defecto, o junto al
original, o a la carpeta que elijas. Se admiten zip, rar, 7z, tar, tar.gz,
tar.bz2, tar.xz y gz; para rar y 7z se descarga la primera vez un pequeño
ayudante (~6 MB) con la firma verificada. Hop extrae rar pero nunca lo crea: el
formato es propietario. «Hop por defecto para archivos comprimidos» en los ajustes
solo ofrece rar cuando ninguna app de Apple lo abre, y puede quitárselo a apps de
terceros; zip, 7z y los formatos nativos se quedan con Utilidad de Archivo.
Funciona con el módulo oculto, y la tarjeta muestra el estado real. Un doble clic en un comprimido desde Finder lo abre justo al lado del archivo, en su propia ventana de progreso, y un fallo no deja nada oculto detrás. Los archivos que abre Hop llevan su propio icono con el formato escrito encima, así una carpeta se lee de un vistazo.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/archives.png" width="480" alt="Hop — Archivos comprimidos">
</div>

### Documentos

El conversor aprendió documentos: markdown → PDF compuesto por el propio Hop,
archivos de Word (.docx, .doc, .rtf) → PDF o markdown, y el texto de un PDF
como markdown — una página escaneada la lee Vision de Apple. Nativo y sin
conexión, sin suite ofimática incluida ni descargas.

### Selector de color

Toma cualquier color de la pantalla con la lupa del sistema y queda en una
lista: cada fila lleva hex, rgb y hsl en su propia columna y al pulsar una se
copia esa notación. El orden nunca cambia bajo el cursor, cuántos colores
guardar y cuántas filas ver son ajustes, y no hace falta permiso de grabación
de pantalla: la lupa devuelve un color y nada más.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/colors.png" width="420" alt="Hop — Selector de color">
</div>

### Reconocimiento de texto

Encuadra un área de la pantalla, o suelta una imagen en la ventana y pega otra
con ⌘V: el texto y los códigos QR salen en una ventana que puedes leer, editar
y copiar, y llegan a la vez al historial del portapapeles. Los saltos de línea
se conservan, así que una tabla sigue legible. El reconocimiento es Vision, de
Apple, todo en este Mac.

Si el resultado contiene una dirección web aparece el botón «abrir enlace»: el
enlace de un código QR de una factura se abre directamente en el navegador,
sin tocar el teléfono. Solo direcciones web: un código escaneado es entrada
ajena, así que un teléfono, una contraseña de Wi-Fi o una tarjeta de contacto
siguen siendo texto normal.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/recognition.png" width="480" alt="Hop — Reconocimiento de texto">
</div>

### Bloqueo del teclado

Pulsa 1, 5 o 15 minutos — o ∞ — y todo el teclado deja de responder, para
limpiarlo sin apagar el Mac ni cerrar la tapa. Una cubierta explica qué pasa y
el icono de la barra de menús se convierte en un teclado. Cuatro salidas: el
botón de la cubierta, el botón del panel, abrir el panel o mantener esc + shift cinco
segundos. Una pulsación corta del botón de encendido también se traga;
mantenerlo pulsado sigue apagando el Mac, porque de eso se encarga el hardware.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/keyboard.png" width="480" alt="Hop — Bloqueo del teclado">
</div>

### Test de velocidad

Un toque mide la conexión con el propio networkQuality de macOS contra los servidores de Apple — bajada, subida y respuesta, y el último resultado se queda en la fila.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/speed.png" width="420" alt="Hop — Test de velocidad">
</div>

### El icono de la barra de menús

El icono lleva marcas pequeñas: el tiempo en marcha, el modo sin reposo, un
recordatorio que sonó, un punto mientras hay una VPN activa (naranja si deja de pasar
algo) y flechas mientras se mueven los torrents — en color o monocromo, cada una
desactivable. Las ventanas propias de Hop aparecen en el Dock mientras están abiertas,
así un clic devuelve una en vez de abrir el panel, y el icono se va con la última
ventana.

### Temas, atajos y modo seguro

Temas oscuro y claro con textura de grano de película, atajos globales, arranque al iniciar sesión y un modo seguro que saca la app de un bucle de fallos — todo en una ventana de ajustes.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/settings.png" width="480" alt="Hop — Ajustes">
</div>

### VPN

Todas las VPN que conoce tu Mac, cada una con su interruptor, sea del proveedor
que sea. Hop lee la lista directamente de los ajustes del sistema: un cliente que
instalaste ayer aparece solo, y uno que quitaste desaparece. Aquí no hay nada que
añadir ni que configurar.

Conecta y desconecta sin abrir nada. Mientras un túnel está activo, un pequeño punto
se enciende en la esquina del icono de la barra de menús, junto a los demás
indicadores: verde mientras pasa algo, naranja cuando el túnel está activo pero no
vuelve nada por él. Una conexión que murió en silencio deja de parecer sana, y el
panel señala la fila de la que se trata. Pulsa el nombre y se abre la ventana de esa
VPN para cuando la necesites; al cerrarla, Hop cierra la app. La conexión se mantiene:
el túnel lo sostiene el sistema, no la app.

La fila muestra lo que informa el propio cliente: su nombre y, entre paréntesis,
lo que añade la configuración, normalmente el país. Hop nunca deduce el país de
la dirección del servidor: el registro dice dónde está registrado el rango, no
dónde está la máquina.

El punto se puede apagar en los ajustes: el módulo y sus interruptores siguen funcionando sin él.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/vpn.png" width="420" alt="Hop — Interruptores de VPN">
</div>

### Apps

Una cuadrícula con los programas que abres todo el día, a un clic y sin pasar
por la carpeta de aplicaciones. Pulsa + y elígelos, o arrástralos desde el
Finder; caben nueve por fila, hasta ocho filas.

Arrastra un icono para moverlo: una línea amarilla muestra entre qué dos iconos
caerá y los demás se apartan, como en una pantalla de inicio. El botón de
edición inicia el balanceo, cada icono recibe una ✕ y la cuadrícula puede tener
su propio nombre; ahí mismo se apagan los nombres bajo los iconos, si reconoces
tus apps de vista. Puedes tener tantas cuadrículas como quieras — el trabajo en
un espacio, lo demás en otro — cada una con sus apps.

Las cuadrículas se crean y se borran donde ordenas los módulos: en ajustes o en
la propia tabla de módulos, donde la ✕ del chip de una cuadrícula la elimina
para siempre. Una cuadrícula nueva empieza vacía y lo dice hasta que la llenas.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/apps.png" width="420" alt="Hop — Cuadrícula de apps">
</div>

### Eliminar apps

Suelta una app en la fila, o elígela de la lista de todo lo instalado, y se va junto con lo que dejó en una treintena de sitios: application support, cachés, preferencias, contenedores, launch agents, plug-ins, recibos y lo demás. Cada app de la lista muestra cuánto pesa, el paquete y sus datos por separado. Una app que ya está en la papelera también se reconoce: el identificador sale del paquete que hay allí, o se deduce de los restos que lo nombran.

No se borra nada. Todo va a la papelera, así que un error cuesta una restauración y no un archivo, y lo que macOS no entrega se nombra con su motivo en vez de saltárselo en silencio.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/uninstall.png" width="480" alt="Hop — Eliminar una app con todo lo que dejó">
</div>

El mismo módulo limpia sin eliminar nada: cada app que guarda caché, las mayores primero; instaladores en Descargas, Escritorio y Documentos; datos de apps eliminadas hace años; y la papelera con su tamaño. Una casilla se lleva una sección entera. Lo que deja en paz a propósito también aparece — un contenedor donde caché y datos comparten carpeta, los veinte gigas de un mensajero entre ellos: solo esa app sabe qué mitad sobra.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/es/clean.png" width="480" alt="Hop — Limpiar cachés, instaladores, restos y la papelera">
</div>

## 22 idiomas

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — la app sigue el idioma de tu sistema desde el
primer momento.

## Apoya el proyecto

Hop es gratis y lo seguirá siendo. Si se gana un sitio en tu barra de menús, una
aportación voluntaria ayuda a sacar funciones nuevas y a pulir las que ya están:
paga el tiempo que lleva, nada más.

**[→ Apoyar Hop](https://web.tribute.tg/d/Nvk)**

## Privacidad — y por qué los permisos se pueden dar sin miedo

**Hop no recopila nada. Ni ahora ni después.** Sin servidor propio, sin
analítica, sin telemetría, sin cuentas, sin informes de fallos. Cada permiso de
abajo lo pide macOS solo cuando usas la función que lo necesita, y existe
precisamente para que esa función trabaje: no se recopila nada de paso. No hace
falta creerlo: la app es de código abierto, y el código que recopilaría
sencillamente no existe. Busca en este repositorio un SDK de tracking o una
llamada de analítica y no la encontrarás.

Todo funciona en local: sin servidor, sin analíticas, sin cuentas. La app
solo toca la red para buscar actualizaciones, cuando ejecutas el test de
velocidad integrado y — si activas el módulo de torrents — para descargar el
motor una única vez y mover el propio tráfico de torrents. Esa comprobación
de actualizaciones envía la versión que usas, y nada que te identifique a ti
ni a tu Mac. Las actualizaciones y el motor de torrents se entregan como
archivos firmados y se verifican con una firma Ed25519 antes de instalarse.

## Permisos

Hop pide un permiso solo cuando usas la función que lo necesita, y la ventana
de información los enumera todos con su estado actual:

- **red — antonshakirov.com** — buscar y descargar actualizaciones, más los dos
  ayudantes opcionales (motor de torrents y archivador 7-Zip)
- **red — torrents, test de velocidad** — tráfico con otros pares con el módulo
  de torrents activo; el test usa networkQuality de macOS contra los servidores
  de Apple
- **accesibilidad** — pegar en la app de debajo, el gestor de ventanas y el
  bloqueo del teclado
- **grabación de pantalla** — solo el reconocimiento de texto, y solo al
  encuadrar un área; el selector de color no la necesita
- **notificaciones** — el aviso del temporizador y un torrent terminado
- **contraseña de administrador** — una vez, para el modo con la tapa cerrada
  (pmset solo funciona como root)
- **abrir al iniciar sesión** — desactivado hasta que lo enciendas

Al arrancar no se pide nada, y nada se pide por un módulo que no hayas activado.
No hay analítica, ni telemetría, ni cuentas, ni informes de fallos: se contacta
con antonshakirov.com solo para preguntar si existe una versión más nueva, y
para descargarla —o uno de los dos ayudantes opcionales— si dices que sí. Todo
lo demás se queda en este Mac: el historial del portapapeles, el tiempo
registrado, la lista de tareas, el texto reconocido y los colores tomados.

Cada permiso de arriba existe para que una función pueda trabajar, y para nada
más. No hace falta creerlo: Hop es de código abierto, y el código que tendría
que recopilar sencillamente no existe — léelo en este repositorio. La ventana de
información de la app tiene una pestaña «permisos de la app» con la misma lista
y el estado actual de cada permiso.

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

Tres formas, y las tres se agradecen:

- **[Apoyar Hop con una aportación](https://web.tribute.tg/d/Nvk)** — va directa
  a funciones nuevas y arreglos. Voluntaria, sin recompensas, sin nada de pago:
  todos los módulos son iguales para todos.
- **[Dar una estrella al repo](https://github.com/antonyshakirov/hop/stargazers)** —
  por las estrellas lo encuentran otros.
- **[Abrir un issue](https://github.com/antonyshakirov/hop/issues)** — un informe
  de error o una idea valen lo mismo.

## Autor y licencia

Creado por [Anton Shakirov](https://www.antonshakirov.com/en). Publicado
bajo la [licencia MIT](../../LICENSE): úsalo y modifícalo libremente,
conserva el aviso de copyright — hacer pasar la app por obra propia es una
violación de la licencia.
