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

- No primeiro envio, o script usa automaticamente `git ftp init` quando o servidor ainda nao tem o historico do `git-ftp`.
- Nos envios seguintes, o script usa `git ftp push` para enviar apenas os arquivos alterados.
- O progresso mostrado e baseado na quantidade de arquivos processados, nao no tamanho em bytes.
