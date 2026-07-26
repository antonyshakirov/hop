<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Ícone do app Hop — asterisco de quatro linhas">

# Hop

**Um pequeno companheiro de barra de menus para macOS: timer, controle de
tempo, lista de tarefas, modo antissuspensão, monitor do sistema, histórico
da área de transferência, conversor de arquivos, gerenciador de janelas e um
cliente de torrents leve — distribuídos em até quatro abas no ícone. Um
clique — e tudo o que você precisa está ali.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls)](https://www.antonshakirov.com/api/hop/installs)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · **Português** · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/pt/panel.png" width="420" alt="Painel do Hop — timer na barra de menus com display de matriz de pontos, predefinições e ciclos de trabalho e descanso">

</div>

O Hop mora na barra de menus do seu Mac e substitui um punhado de pequenos
utilitários: um timer estilo Pomodoro, um controle de tempo com lista de
tarefas, um bloqueador de suspensão à la caffeinate, um monitor do sistema,
um gerenciador da área de transferência, um conversor de arquivos por
arrastar e soltar, um organizador de janelas e um cliente de torrents leve —
um único app nativo e leve, com os módulos que você usa distribuídos em até
quatro abas no ícone.

## Download

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — abra e arraste o `Hop.app` para Aplicativos (recomendado)
- `Hop-x.y.z.zip` — o mesmo app como um arquivo simples (usado pelo atualizador integrado); veja a [versão mais recente](https://github.com/antonyshakirov/hop/releases/latest)
- Espelho rápido: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Primeira abertura: clique com o botão direito em `Hop.app` → **Abrir** →
confirme (o app ainda não é notarizado). Requer macOS 14 ou mais recente.

## Recursos

### Espaços

O ícone comporta até quatro abas, e você arrasta cada módulo para a aba que
quiser: o timer em uma, o monitor em outra, o que abre raramente para o lado.
Uma prateleira «inativos» guarda o que você põe de lado, sem apagar.

### Timer e ciclos

Uma contagem regressiva em matriz de pontos que você ajusta com um único
gesto: arraste os dígitos, digite o tempo como em um micro-ondas ou escolha
uma predefinição. Ciclos de trabalho e descanso (25/5 Pomodoro, 52/17,
90/15 — ou os seus próprios), um cronômetro, um cofre que guarda um timer
em andamento enquanto você experimenta outro, e um alerta de término que
também pode pausar suas mídias. Quando a contagem termina, toca um som único
e os dígitos piscam até você zerar.

### Controle de tempo e tarefas

Acompanhe o tempo por uma lista plana de tarefas: cada linha mostra o tempo
de hoje e um total acumulado, e você pode corrigir o valor de hoje à mão. Se
uma correr demais, um aviso lembra você após oito horas. Ao lado há uma lista
de tarefas separada, em que o que foi concluído desce para o fim.

### Sem suspensão

Mantenha o Mac acordado por 15 minutos, 8 horas ou para sempre — um clique,
sem senha. Opcionalmente mantenha a tela ligada, ou continue trabalhando com
a tampa fechada (ótimo para downloads, builds longos e telas externas).

### Monitor do sistema

Carga e temperatura de CPU e GPU, memória e swap, rede, disco, saúde da
bateria e consumo de energia — valores ao vivo com gráficos sparkline,
limites de cor definidos por você, °C/°F e uma linha de uptime. As leituras
vêm direto do macOS e só são atualizadas enquanto a aba está aberta.

### Histórico da área de transferência

As últimas 100 coisas que você copiou (até 300) — texto, imagens e arquivos —
com um clique para copiar de novo ou colar direto no app anterior. Arquivos
copiados são guardados pelo nome (vários de uma vez aparecem como
«nome +N»), e ao colar o arquivo em si volta. Senhas e outras entradas
ocultas nunca são armazenadas.

### Conversor de arquivos

Solte um lote de imagens, PDFs, vídeos ou áudios no painel: JPEG, PNG, HEIC,
AVIF e WebP na saída; compressão de PDF; redução de vídeo HEVC com uma
estimativa de tamanho honesta e ao vivo antes de converter. Tudo é
processado localmente.

### Gerenciador de janelas

Encaixe janelas em metades, quartos, terços e no centro com um clique em um
glifo de zona ou um atalho ⌃⌥ — sem precisar de outro app.

### Torrents

Um cliente BitTorrent leve no mesmo painel: solte um arquivo .torrent ou
cole um link magnet, escolha exatamente quais arquivos baixar — antes ou até
durante o download —, pause, retome e faça seed, com uma parada opcional ao
atingir o ratio 1.0. O módulo vem desativado por padrão; ao ativá-lo, o
motor de código aberto é baixado como um pequeno pacote separado (~26 MB,
com assinatura verificada) que só conversa com o Hop por uma porta local. O
Hop também pode virar o app padrão para arquivos .torrent e links magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/pt/torrents.png" width="420" alt="Torrents do Hop — cliente BitTorrent leve no painel da barra de menus">
</div>

### Arquivos compactados

A linha do módulo abre uma janela, e é nela que você solta as coisas — ⌘V também
funciona, com vários arquivos de uma vez. O que você adiciona espera numa lista
até você apertar o botão: os compactados são extraídos e todo o resto vira um
compactado só. O resultado vai para a mesa por padrão, ou ao lado do original,
ou para a pasta que você escolher. Valem zip, rar, 7z, tar, tar.gz, tar.bz2,
tar.xz e gz; para rar e 7z, na primeira vez, baixa um ajudante pequeno (~6 MB)
com assinatura verificada. O Hop extrai rar mas nunca cria: o formato é
proprietário. «Hop como padrão para compactados» nos ajustes assume os
formatos que o macOS não abre sozinho — sobretudo rar e 7z — e os toma de volta
de apps de terceiros; zip e tar ficam com o Utilitário de Arquivos. Funciona com
o módulo oculto, e o cartão mostra o estado real.

### Documentos

O conversor aprendeu documentos: markdown → PDF diagramado pelo próprio Hop,
arquivos do Word (.docx, .doc, .rtf) → PDF ou markdown, e o texto de um PDF
como markdown — uma página digitalizada é lida pelo Vision da Apple. Nativo e
offline, sem pacote de escritório embutido e sem downloads.

### Seletor de cor

Pegue qualquer cor da tela com a lupa do sistema e ela fica numa lista: cada
linha traz hex, rgb e hsl na própria coluna, e clicar em uma copia aquela
notação. A ordem nunca muda sob o cursor, quantas cores guardar e quantas
linhas mostrar são ajustes, e não é preciso permissão de gravação de tela: a
lupa devolve uma cor e nada além.

### Reconhecimento de texto

Enquadre uma área da tela, ou solte uma imagem na janela e cole outra com ⌘V:
o texto e os códigos QR saem numa janela que dá para ler, editar e copiar, e
entram ao mesmo tempo no histórico da área de transferência. As quebras de
linha ficam, então uma tabela continua legível. O reconhecimento é o Vision da
Apple, inteiramente neste Mac.

### Bloqueio do teclado

Toque 1, 5 ou 15 minutos — ou ∞ — e o teclado inteiro para de responder, para
limpá-lo sem desligar o Mac nem fechar a tampa. Uma cobertura explica o que
está acontecendo e o ícone da barra de menus vira um teclado. Quatro saídas: o
botão da cobertura, o botão do painel, abrir o painel ou segurar esc + shift por cinco
segundos. Um toque curto no botão de força também é engolido; segurá-lo ainda
desliga o Mac à força, porque isso é feito no hardware.

### E o resto

Pequenos indicadores de status no ícone da barra de menus — tempo,
antissuspensão, avisos e atividade de torrents, coloridos ou monocromáticos —,
um teste de velocidade integrado (networkQuality da Apple), temas escuro e
claro com textura de grão de filme, atalhos globais, abertura no login e um
modo seguro que recupera o app de um loop de travamentos.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/pt/system.png" width="280" alt="Monitor do sistema do Hop — gráficos de CPU, GPU, memória, rede, disco e bateria">
<img src="https://www.antonshakirov.com/products/hop/screens/pt/converter.png" width="280" alt="Conversor de arquivos do Hop — conversão em lote de imagens, PDFs, vídeo e áudio">
<img src="https://www.antonshakirov.com/products/hop/screens/pt/settings.png" width="280" alt="Ajustes do Hop — temas, módulos, atalhos, 18 idiomas">
</div>

## 18 idiomas

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — o app segue o idioma do seu sistema desde o
primeiro momento.

## Privacidade

Tudo roda localmente: sem servidor, sem analytics, sem contas. O app só
acessa a rede para verificar atualizações, quando você executa o teste de
velocidade integrado e — se você ativar o módulo de torrents — para baixar o
motor uma única vez e transportar o próprio tráfego de torrents. Essa
verificação de atualizações envia a versão que você usa, e nada que
identifique você ou o seu Mac. As atualizações e o motor de torrents chegam
como arquivos assinados e são verificados com uma assinatura Ed25519 antes
da instalação.

## Permissões

O Hop pede uma permissão só quando você usa o recurso que precisa dela, e a
janela de informações lista todas com o estado atual:

- **rede — antonshakirov.com** — procurar e baixar atualizações, mais os dois
  ajudantes opcionais (motor de torrent e arquivador 7-Zip)
- **rede — torrents, teste de velocidade** — tráfego com outros pares com o
  módulo de torrent ligado; o teste usa o networkQuality do macOS contra os
  servidores da Apple
- **acessibilidade** — colar no app de baixo, o gerenciador de janelas e o
  bloqueio do teclado
- **gravação de tela** — só o reconhecimento de texto, e só ao enquadrar uma
  área; o seletor de cor não precisa
- **notificações** — o aviso do timer e um torrent concluído
- **senha de administrador** — uma vez, para o modo de tampa fechada (o pmset só
  roda como root)
- **abrir ao iniciar sessão** — desligado até você ligar

Nada é solicitado ao abrir, e nada é pedido por um módulo que você não ligou.
Não há analytics, telemetria, contas nem relatórios de erro: o antonshakirov.com
é contatado apenas para perguntar se existe uma versão mais nova — e para
baixá-la, ou um dos dois ajudantes opcionais, se você concordar. Todo o resto
fica neste Mac: o histórico da área de transferência, o tempo registrado, a
lista de tarefas, o texto reconhecido e as cores capturadas.

Cada permissão acima existe para que uma função funcione — e para mais nada.
Não precisa acreditar na palavra: o Hop é open source, e o código que faria essa
coleta simplesmente não existe — leia neste repositório. A janela de informações
do app tem uma aba «permissões do app» com a mesma lista e o estado atual de
cada uma.

Site: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Grátis, e por quê

O Hop é totalmente grátis: sem teste, sem versão pro, sem compras no app. Sem
anúncios, sem coleta de dados, sem contas — não há nada para monetizar nem nada
para vender. É um projeto pessoal: criei o Hop para mim, uso todos os dias e
simplesmente compartilho. Se for útil, passe adiante. E se quiser contribuir,
agora há uma forma de apoiar o Hop — puramente um presente, sem nada em troca.

## Compilando a partir do código-fonte

Swift Package Manager, macOS 14+, sem dependências externas:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

O fluxo de desenvolvimento, o pipeline de releases e a especificação de
comportamento estão em [docs/development.md](../development.md) e
[docs/spec.md](../spec.md).

## Apoie o projeto

Se o Hop economiza um clique ou dois para você, **[dê uma estrela ao repositório](https://github.com/antonyshakirov/hop/stargazers)** —
é pelas estrelas que outras pessoas o encontram. Relatos de bugs e ideias de
recursos são bem-vindos em [Issues](https://github.com/antonyshakirov/hop/issues).

## Autor e licença

Feito por [Anton Shakirov](https://www.antonshakirov.com/en). Publicado sob
a [licença MIT](../../LICENSE): use e modifique livremente, mantenha o aviso
de copyright — apresentar o app como trabalho seu é uma violação da licença.
