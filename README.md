# syncsite

Script de terminal para sincronizar arquivos alterados com FTP usando Git e `git-ftp`.

## Comandos

### `./syncsite --start`

Prepara o projeto para sincronizacao.

Ele verifica ou instala:

- Git
- git-ftp
- curl

Tambem inicia o repositorio Git quando necessario, cria o arquivo `.syncsite` com os dados do FTP e adiciona `.syncsite` e `syncsite` no `.gitignore`.

### `./syncsite --test`

Valida se tudo foi criado corretamente.

Ele confere:

- Git instalado
- git-ftp instalado
- curl instalado
- repositorio Git iniciado
- arquivo `.syncsite`
- entradas no `.gitignore`
- conexao real com o FTP sem enviar arquivos

### `./syncsite --config`

Recria o arquivo `.syncsite`.

Use este comando para trocar dados de acesso ou corrigir uma configuracao errada. Se o arquivo `.syncsite` ja existir, o script pede confirmacao antes de substituir.

### `./syncsite --upload`

Envia os arquivos alterados para o FTP.

Antes de enviar, o script:

- mostra os arquivos locais alterados
- faz commit automatico com data
- simula o envio com `git-ftp`
- lista os arquivos que serao enviados
- pede confirmacao `[y/n]`
- mostra progresso em porcentagem por arquivo processado
- no primeiro uso, cria uma base no servidor sem enviar todos os arquivos do projeto

### `./syncsite --help`

Mostra a ajuda no terminal.

## Fluxo recomendado

```bash
./syncsite --start
./syncsite --test
./syncsite --upload
```

Para refazer a configuracao:

```bash
./syncsite --config
```

## Arquivo `.syncsite`

O arquivo `.syncsite` guarda as configuracoes privadas do FTP.

Exemplo:

```bash
FTP_HOST="ftp.seusite.com"
FTP_USER="usuario"
FTP_PASSWORD="senha"
FTP_ROOT="/public_html"
```

Esse arquivo nao deve ser enviado para o Git. O proprio script adiciona `.syncsite` no `.gitignore`.

## Observacoes

- No primeiro uso, o script usa `git ftp catchup` para criar a base do `git-ftp` sem enviar todos os arquivos do projeto.
- Depois da base criada, o script usa `git ftp push` para enviar apenas os arquivos alterados.
- Se ainda nao existir um commit anterior para comparar, o primeiro `--upload` apenas cria a base. Altere arquivos e rode `./syncsite --upload` novamente para enviar as mudancas.
- O progresso mostrado e baseado na quantidade de arquivos processados, nao no tamanho em bytes.

## App macOS

O projeto tambem tem uma primeira interface grafica em SwiftUI:

```bash
SyncSiteApp.xcodeproj
```

Para abrir no Xcode:

```bash
open SyncSiteApp.xcodeproj
```

No app, voce pode manter uma lista de sites configurados. Use o botao **Adicionar** para abrir um wizard passo a passo:

1. Nome do site
2. Pasta local do projeto
3. Dados do FTP
4. Revisao e conclusao

Depois de adicionar um site, selecione ele na lista lateral e use os botoes:

- Criar base inicial
- Testar FTP
- Ver alteracoes
- Enviar alteracoes

A interface grafica tem motor proprio para comparar arquivos e enviar por FTP. Ela nao depende de Git nem de `git-ftp` para sincronizar sites.

O app cria um snapshot local por site, compara novos hashes dos arquivos com o ultimo estado salvo e descobre automaticamente:

- arquivos novos
- arquivos alterados
- arquivos removidos

Durante o envio, a interface mostra barra de progresso, arquivo atual e estimativa de tempo restante. O macOS normalmente ja inclui `curl`, usado internamente pelo app para executar as operacoes FTP.
