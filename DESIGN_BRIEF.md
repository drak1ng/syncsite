# SyncSite - briefing para redesign de interface macOS

## Objetivo do app

SyncSite é um aplicativo macOS para sincronizar arquivos de sites locais com um servidor FTP. Ele foi criado para substituir um fluxo manual de terminal por uma interface gráfica simples, moderna e segura.

O app identifica arquivos criados, alterados, removidos ou pendentes desde uma base salva, mostra uma revisão antes do envio e faz upload para FTP com progresso, velocidade, tempo restante, retomada automática e mensagens de erro compreensíveis.

## Público-alvo

- Desenvolvedores freelancers.
- Designers que mantêm sites simples.
- Pequenas agências.
- Usuários técnicos leves que precisam subir arquivos para FTP sem usar terminal.

O app deve parecer profissional, confiável e fácil de usar. Deve ter cara de ferramenta nativa de macOS, não de dashboard web.

## Plataforma

- macOS
- SwiftUI
- Interface desktop
- Janela principal com sidebar e área de detalhe
- Modo escuro como prioridade visual

## Proposta de valor

O usuário configura um ou mais sites locais, informa os dados de FTP e usa o app para:

- Criar uma base inicial.
- Verificar arquivos alterados.
- Enviar alterações para FTP.
- Retomar uploads interrompidos.
- Ver erros de forma clara.
- Importar e exportar a lista de syncs configurados.

## Funcionalidades principais

### 1. Lista de syncs configurados

A lateral esquerda deve exibir todos os sites/syncs configurados.

Cada item da lista deve mostrar:

- Nome do sync.
- Caminho local do projeto.
- Estado visual discreto, quando útil.

No topo da lateral devem existir botões para:

- Adicionar novo sync.
- Remover sync selecionado.
- Importar syncs.
- Exportar syncs.

Esses botões devem ser compactos, com ícones claros e tooltips. A lista deve ficar abaixo desses botões.

### 2. Wizard para adicionar novo sync

Fluxo passo a passo:

1. Nome do site.
2. Pasta local do projeto.
3. Dados do FTP.
4. Revisão final.

Campos necessários:

- Nome do site.
- Pasta local.
- Servidor FTP.
- Login.
- Senha.
- Diretório raiz no servidor.

O wizard deve ser limpo, com pouca fricção, e mostrar claramente em que etapa o usuário está.

### 3. Configuração FTP

Tela principal deve permitir editar:

- Servidor.
- Login.
- Senha.
- Diretório raiz.

Deve haver um botão para salvar configuração.

O app deve mostrar se o FTP está configurado corretamente ou se falta informação.

### 4. Criar base inicial

A base inicial registra o estado atual dos arquivos locais. Depois disso, o app passa a identificar apenas alterações futuras.

Essa ação deve ser tratada como importante, pois define o ponto inicial da sincronização.

### 5. Verificar arquivos alterados

Ao clicar em "Verificar arquivos alterados", o app abre um modal com:

- Título claro.
- Botão de fechar.
- Total de arquivos e pastas encontrados.
- Opção de filtrar por data e hora.
- Lista dos arquivos encontrados.
- Botões:
  - Enviar agora.
  - Sair.

Também deve detectar:

- Arquivos novos.
- Arquivos modificados.
- Arquivos removidos.
- Pastas novas.
- Arquivos dentro de pastas novas.

### 6. Enviar alterações

Ao enviar, o app deve abrir um modal de progresso.

O modal deve mostrar:

- Barra de progresso verde.
- Arquivo atual.
- Contador no formato `12/320`.
- Velocidade de transferência.
- Tempo restante em horas, minutos e segundos.
- Botão cancelar em vermelho.

O tempo restante deve ser fácil de ler:

- Menos de 1 minuto: mostrar segundos.
- Menos de 1 hora: mostrar minutos e segundos.
- Mais de 1 hora: mostrar horas, minutos e segundos.

### 7. Retomada automática

Se o upload falhar, o app deve tentar retomar automaticamente até 3 vezes.

Enquanto isso, o usuário não deve ser interrompido com erro.

Somente depois de 3 falhas consecutivas o app deve mostrar o erro na tela.

O app deve garantir que:

- Arquivos já enviados não sejam reenviados desnecessariamente.
- Arquivos pendentes continuem na fila.
- Nenhum arquivo seja perdido.

### 8. Tratamento de erros

Erros devem ser explicados em linguagem humana.

Exemplos:

- Login recusado.
- Servidor não encontrado.
- Conexão recusada.
- Código FTP 550.
- Pasta inexistente.
- Permissão insuficiente.
- Arquivo remoto já removido.

O erro técnico pode aparecer em uma área secundária, mas a mensagem principal deve explicar o que provavelmente aconteceu e o que o usuário pode fazer.

### 9. Histórico de atividades

O app deve ter um botão para abrir histórico.

O histórico deve mostrar:

- Sucessos.
- Avisos.
- Erros.
- Testes de FTP.
- Verificações de arquivos.
- Envios concluídos.

Também deve existir opção para limpar o histórico.

### 10. Importar e exportar syncs

O usuário deve poder exportar a lista de syncs configurados para um arquivo JSON.

Importante:

- Não exportar senha FTP.
- Não exportar credenciais sensíveis.
- Exportar apenas nome, pasta local e preferências seguras.

## Telas principais

### Janela principal

Layout sugerido:

- Sidebar à esquerda.
- Conteúdo do sync selecionado à direita.
- Cabeçalho com nome do sync e caminho local.
- Bloco de configuração FTP.
- Bloco de ações.
- Bloco de resumo/status.

### Sidebar

Deve ter:

- Barra superior com botões de ação.
- Lista dos syncs configurados.
- Seleção clara do sync ativo.
- Visual elegante, nativo e compacto.

Referência estética:

- Sidebar escura.
- Itens com ícones discretos.
- Seleção com fundo sutil.
- Tipografia clara.
- Sem excesso de cards dentro de cards.

### Modal de verificação

Deve parecer uma etapa de revisão antes do envio.

Precisa deixar claro:

- Quantos arquivos serão enviados/removidos.
- Quais arquivos serão afetados.
- Se o filtro por data está ativo.

### Modal de progresso

Deve parecer uma operação em andamento.

Prioridades:

- Progresso visível.
- Estado atual.
- Possibilidade de cancelar.
- Erros claros quando necessário.
- Botão de retomar envio quando aplicável.

## Direção visual desejada

Estilo:

- macOS moderno.
- Profissional.
- Limpo.
- Escuro.
- Compacto, mas confortável.
- Sem aparência de landing page.
- Sem excesso de cards.
- Sem cores demais.

Evitar:

- Botões muito coloridos.
- Muitos blocos dentro de blocos.
- Layout com aparência web/SaaS genérico.
- Gradientes exagerados.
- Texto explicativo demais na tela.
- Hero section.

Preferir:

- Sidebar bem desenhada.
- Ícones consistentes.
- Separadores sutis.
- Hierarquia tipográfica clara.
- Espaçamento respirado.
- Estados visuais elegantes.
- Modais bonitos e objetivos.

## Componentes necessários

- Sidebar.
- Botões de ícone no topo da sidebar.
- Lista de syncs.
- Campos de formulário.
- Botões primários e secundários.
- Botão destrutivo.
- Modal de wizard.
- Modal de revisão.
- Modal de progresso.
- Toasts/alertas.
- Histórico de atividades.
- Barra de progresso.
- Lista de arquivos alterados.
- Estados vazios.
- Estados de erro.
- Estados de sucesso.
- Estados desabilitados.

## Ícones sugeridos

Usar SF Symbols ou ícones equivalentes:

- Adicionar: `plus`
- Remover: `trash`
- Importar: `square.and.arrow.down`
- Exportar: `square.and.arrow.up`
- Sync: `arrow.triangle.2.circlepath`
- FTP configurado: `checkmark.seal.fill`
- Aviso: `exclamationmark.triangle.fill`
- Histórico: `clock`
- Enviar: `arrow.up.circle.fill`
- Verificar arquivos: `doc.text.magnifyingglass`
- Cancelar: `xmark.circle.fill`

## Tom de texto

Idioma: português brasileiro.

Usar frases curtas e claras.

Exemplos:

- "Verificar arquivos alterados"
- "Enviar alterações"
- "Criar base inicial"
- "Testar FTP"
- "FTP conectado"
- "Nenhuma alteração encontrada"
- "Envio interrompido"
- "Retomar envio"
- "Sincronização concluída"

## Prompt pronto para IA de design

Crie uma interface macOS moderna para um aplicativo chamado SyncSite.

O app sincroniza arquivos locais de sites com servidores FTP. Ele permite configurar vários syncs, verificar arquivos alterados, revisar a lista de arquivos, enviar alterações com barra de progresso, retomar uploads interrompidos e exibir erros de forma clara.

Faça uma janela desktop em modo escuro, com uma sidebar à esquerda e área de detalhe à direita. A sidebar deve ter no topo quatro botões compactos com ícones: adicionar, remover, importar e exportar. Abaixo, mostre a lista de syncs configurados com nome e caminho local. O item selecionado deve ter destaque sutil e elegante.

Na área principal, mostre o sync selecionado com cabeçalho, caminho local, configuração FTP, ações principais e resumo/status. As ações principais são: Criar base inicial, Testar FTP, Verificar arquivos alterados e Enviar alterações.

Crie também os modais de:

1. Adicionar sync com wizard em 4 etapas.
2. Verificar arquivos alterados com filtro por data, contagem de arquivos/pastas e lista de arquivos.
3. Enviar alterações com barra de progresso verde, arquivo atual, contador `12/320`, velocidade, tempo restante e botão cancelar.
4. Erro após falha de upload, com botão de retomar envio.
5. Histórico de atividades.

Estilo visual desejado: nativo de macOS, escuro, refinado, compacto, sem excesso de cards, sem botões muito coloridos, sem aparência de dashboard web. Use tipografia clara, separadores sutis, ícones consistentes e boa hierarquia visual. O app deve parecer confiável, profissional e fácil para freelancers e pequenas agências.

## Sugestão de IA/ferramenta para criar o layout

Minha recomendação principal: Figma com recursos de IA.

Motivo:

- Figma é uma ferramenta madura e colaborativa para design de interfaces.
- Permite editar tudo manualmente depois.
- É mais adequada para gerar um layout bonito e refinado do que ferramentas focadas apenas em código.
- Você pode passar este briefing para gerar telas, depois ajustar visualmente e usar como referência no Xcode/SwiftUI.

Alternativas:

- Vercel v0: boa para gerar ideias rápidas de UI, mas tende a criar interfaces web/React, não macOS nativo.
- ChatGPT/Codex: bom para transformar um design aprovado em SwiftUI.
- Sketch: excelente para macOS/UI design, mas menos forte em geração por IA.
- Adobe Firefly/Creative Cloud: bom para identidade visual, ícones e assets, mas não é minha primeira escolha para desenhar toda a interface de app.

Fluxo recomendado:

1. Use este arquivo como briefing no Figma AI ou em uma IA de design.
2. Peça 2 ou 3 variações visuais.
3. Escolha uma direção.
4. Peça refinamento dos estados: vazio, erro, upload em andamento e seleção na sidebar.
5. Use o design final como referência para implementar em SwiftUI.
