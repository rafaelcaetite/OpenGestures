# OpenGestures

Gestos personalizados para o trackpad e o Magic Mouse no macOS, incluindo
gestos contínuos, que continuam agindo enquanto os dedos se movem: deslize
quatro dedos para cima para aumentar o volume, para os lados para trocar de
aba, e assim por diante.

O OpenGestures é um app pequeno de barra de menus, configurado por um arquivo
de texto. Ele lê os toques diretamente do trackpad, reconhece toques, toques
duplos, passadas, deslizes, combinações de segurar e tocar, sequências de
dedos e cliques nos cantos e nas bordas, e transforma tudo isso em atalhos de
teclado, teclas de mídia, URLs, comandos de menu, scripts e mais.

[English](README.md)

## Destaques

- **Gestos contínuos.** Um deslize dispara um passo a cada poucos milímetros
  de movimento, nos dois sentidos, enquanto os dedos estiverem no trackpad.
  Volume, brilho, zoom, abas, desfazer e mesas já vêm prontos, e qualquer par
  de ações pode ser combinado.
- **75 gestos** no trackpad e no Magic Mouse.
- **Atalhos por aplicativo**, atalhos que só valem com Fn pressionado e
  sequências de vários passos.
- **Configuração ao vivo.** O arquivo é recarregado assim que você salva. Um
  erro é informado com o número da linha, e a última configuração válida
  continua ativa.
- **Leve.** Binário universal de 1,3 MB, sem dependências. Reconhecer um
  frame leva cerca de um quarto de microssegundo, nada é alocado enquanto os
  dedos se movem e o app não usa CPU com o trackpad parado.

## Requisitos

- macOS 13 Ventura ou mais novo, em Apple Silicon ou Intel
- Trackpad embutido, Magic Trackpad ou Magic Mouse
- Xcode ou as Command Line Tools (`xcode-select --install`) para compilar

## Instalação

```sh
git clone https://github.com/rafaelcaetite/OpenGestures.git
cd OpenGestures
make install
```

Isso compila o app, instala `OpenGestures.app` em `~/Applications`, abre o
app e o registra para abrir no login. Use `make install ARCHS="arm64 x86_64"`
para um binário universal.

Na primeira execução o macOS pede a permissão de **Acessibilidade**, necessária
para enviar atalhos e tratar cliques. Ative em Ajustes do Sistema >
Privacidade e Segurança > Acessibilidade. A permissão fica ligada ao
identificador do app e continua valendo depois de recompilar.

## Primeiros passos

A configuração fica em `~/.config/opengestures/config.toml` e é criada, toda
comentada, na primeira execução. Abra pelo ícone da barra de menus em
**Edit Configuration…**:

```toml
[TRACKPAD]
four-finger-slide = "volume"                 # Deslize para cima ou para baixo
three-finger-double-tap = "play-pause"
hold-left-tap-right = "next-tab"             # Apoie um dedo e toque à direita
bottom-right-corner-click = "show-desktop"
fn+four-finger-slide = "brightness"          # O mesmo deslize segurando Fn

[TRACKPAD."Safari, Google Chrome"]
four-finger-slide = "tabs"
```

Salve o arquivo e os novos gestos passam a valer na hora.

### Gestos que o macOS já usa

O OpenGestures observa o trackpad, mas não impede o macOS de reagir ao mesmo
movimento. Se você usar um gesto que o macOS também usa, como passar quatro
dedos na vertical para o Mission Control, desligue o gesto do macOS em
Ajustes do Sistema > Trackpad > Mais Gestos. O comando `OpenGestures check`
lista todas as sobreposições.

## Linha de comando

```
OpenGestures check [arquivo]  Valida a configuração e lista conflitos com gestos do macOS
OpenGestures trace [--all]    Mostra os gestos reconhecidos, sem executar ações
OpenGestures gestures         Lista todos os gestos
OpenGestures actions          Lista ações, presets e prefixos
```

A referência completa está em [docs/configuration.md](docs/configuration.md)
(em inglês).

## Desinstalação

```sh
make uninstall
```

A configuração em `~/.config/opengestures` é mantida. Remova também o
OpenGestures de Ajustes do Sistema > Privacidade e Segurança > Acessibilidade.

## Licença

[MIT](LICENSE)
