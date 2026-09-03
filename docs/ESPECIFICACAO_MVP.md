# Quetta — especificação do MVP

## 1. Objetivo

Criar um aplicativo open source, nativo para macOS 14 ou posterior, voltado a uso pessoal. O aplicativo acompanha reuniões usando apenas duas fontes de áudio: o microfone escolhido pelo usuário e o áudio reproduzido no desktop. Ele não grava nem persiste áudio bruto.

O produto oferece dois modos:

1. **Transcrição simples** — mostra a transcrição ao vivo, salva a sessão localmente e gera, ao finalizar, um resumo estruturado por IA.
2. **Tradução simultânea** — além da transcrição ao vivo, mostra uma tradução textual de baixa latência em coluna paralela. Ao finalizar, também salva transcrição, tradução e resumo.

O aplicativo vive na barra de menus. Ao iniciar uma sessão, abre um painel flutuante na região inferior central da tela. Esse painel pode ser ocultado sem parar a sessão.

## 2. Escopo fechado do MVP

### Incluído

- macOS 14+;
- aplicação Swift nativa, baseada em SwiftUI e AppKit quando necessário;
- interface em português e inglês; idioma inicial: idioma do sistema quando suportado, senão português;
- aparência `Sistema` como padrão, com opções `Claro` e `Escuro`;
- captura de microfone e áudio do desktop, cada um ativável/desativável antes e durante a sessão;
- transcrição em tempo real, com idioma padrão configurável: português, inglês ou espanhol;
- tradução simultânea em texto entre português, inglês e espanhol;
- histórico local de sessões, com título automático editável;
- visualização de transcrição, tradução e resumo;
- exportação em Markdown;
- exclusão de uma sessão e limpeza total com confirmação;
- onboarding de permissões;
- arquitetura de provedores extensível;
- Apple Speech como mecanismo de transcrição;
- provedor por chave API OpenAI para IA;
- provedor pessoal Codex OAuth, sem depender de outro aplicativo instalado;
- tratamento explícito para ausência de conexão, permissões e falhas de provedor.

### Fora do escopo do MVP

- gravação, reprodução ou exportação de áudio;
- diarização, identificação de participantes ou associação de nomes às falas;
- busca textual, tags, projetos e sincronização/iCloud;
- compartilhamento de sessões, contas de usuários ou backend próprio;
- integração com calendário, Zoom, Meet, Teams ou Slack;
- síntese de voz/tradução falada;
- edição de transcrição, tradução ou resumo;
- PDF, DOCX, TXT e outros formatos de exportação;
- Gemini, Ollama e outros provedores implementados (a arquitetura os suporta, mas não são entregues no MVP).

## 3. Premissas e limites importantes

1. O aplicativo é de uso pessoal. Não expõe um serviço para terceiros, não compartilha a conta do usuário e não inclui credenciais no repositório.
2. O provedor **Codex OAuth** será isolado como integração experimental. Ele fará seu próprio login OAuth e manterá seus tokens somente no Chaveiro do macOS. Não deve ler, copiar ou depender das credenciais, arquivos ou processos do Pi Agent, Codex CLI ou aplicativo ChatGPT.
3. A autenticação por assinatura do Codex não deve ser tratada como substituto garantido de uma API pública genérica. Se o contrato necessário não estiver disponível ou ficar incompatível, o aplicativo deve informar isso claramente e o provedor por API permanece a alternativa estável.
4. A baixa latência de tradução depende da rede, do provedor selecionado e dos limites da conta. A UI deve mostrar estados de processamento e não prometer um atraso fixo.
5. O áudio de microfone e sistema será misturado em uma única linha do tempo. Sobreposição de vozes pode reduzir a qualidade; o MVP não tenta separá-las.
6. Apesar de Apple Speech poder operar localmente em determinadas condições, o requisito do produto é exigir conectividade. Sem conexão, não se inicia nem se continua processando uma sessão.

## 4. Decisões técnicas

| Área | Decisão |
| --- | --- |
| Linguagem/UI | Swift 5.9+, SwiftUI; AppKit para `NSPanel`, posicionamento e barra de menus quando a API SwiftUI não bastar |
| Versão mínima | macOS 14 |
| Dados | SwiftData com armazenamento local persistente (SQLite gerenciado pelo framework) |
| Segredos | Keychain Services; nenhum segredo em `UserDefaults`, SwiftData, logs ou exportações |
| Áudio de sistema | ScreenCaptureKit (`SCStream`) com captura de áudio habilitada e exclusão do processo atual |
| Microfone | AVFoundation (`AVCaptureSession`/`AVCaptureAudioDataOutput`) |
| Reconhecimento | Speech framework (`SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`) |
| Rede | `NWPathMonitor` para disponibilidade; `URLSession` para provedores remotos |
| Painel flutuante | `NSPanel` com `NSHostingController`, nível flutuante, arrastável, não redimensionável no MVP |
| Barra de menus | `MenuBarExtra` e comandos SwiftUI; app sem janela principal obrigatória |
| Localização | `Localizable.xcstrings`, português e inglês |

Não usar dependências externas no primeiro corte, salvo se uma integração oficial exigir uma biblioteca pequena e auditada. O projeto deve compilar e testar no Xcode sem serviços auxiliares instalados na máquina do usuário.

## 5. Jornada do usuário

### 5.1 Primeiro uso

1. O aplicativo abre pela primeira vez e mostra onboarding.
2. Explica que o áudio não será salvo, mas que texto pode ser enviado ao provedor de IA escolhido para tradução ou resumo.
3. Verifica conexão. Sem conexão, apresenta erro e opção de tentar novamente.
4. Solicita, na ordem, acesso ao microfone, reconhecimento de fala e gravação/captura de tela necessária ao ScreenCaptureKit.
5. Para uma permissão negada, mostra estado `Não permitido`, uma explicação curta e botão **Abrir Ajustes do Sistema**.
6. Permite escolher idioma padrão de transcrição, aparência e configurar ao menos um provedor de IA. A configuração de provedor pode ser pulada; nesse caso, só a transcrição fica disponível.
7. Ao concluir, mostra a barra de menus e abre as configurações principais.

### 5.2 Iniciar sessão

1. Usuário abre o menu na barra de status e seleciona **Nova sessão**.
2. Escolhe o modo `Transcrição simples` ou `Tradução simultânea`.
3. Vê e pode ativar/desativar `Microfone` e `Áudio do Mac`. Pelo menos uma fonte deve permanecer ativa.
4. Em tradução simultânea, escolhe idioma de origem e destino (português, inglês ou espanhol; não podem ser iguais), além de um provedor configurado que suporte tradução.
5. Em transcrição simples, é usado o idioma padrão definido nas Preferências; não há seletor por sessão.
6. Em ambos os modos, escolhe o provedor configurado para resumo. Se nenhum estiver disponível, a sessão ainda pode começar, mas a UI informa que não haverá resumo automático.
7. O título inicial é gerado como `Reunião — 03 set. 2026, 10:30` no idioma da interface. Pode ser alterado no detalhe da sessão posteriormente.
8. Ao confirmar, as permissões e a conectividade são checadas novamente, a sessão é criada e o painel é exibido.

### 5.3 Durante uma sessão

- O item da barra de menus usa um indicador visual ativo (por exemplo, ponto vermelho) e o rótulo **Ouvindo**.
- O painel também exibe indicador visual ativo, modo da sessão e duração decorrida.
- A transcrição aparece em blocos de texto estabilizados. Não exibir timestamps no MVP.
- No modo de tradução, a coluna esquerda exibe o trecho original e a direita a tradução correspondente. Um trecho pode temporariamente exibir **Traduzindo…**.
- Controles disponíveis: pausar, retomar, finalizar, ocultar painel e ativar/desativar microfone ou áudio do Mac.
- **Pausar** interrompe captura, reconhecimento e envio ao provedor. A linha do tempo persistida recebe um marcador não editável `Sessão pausada`; retomar adiciona `Sessão retomada`.
- **Ocultar** mantém a sessão ativa, mas fecha apenas o painel. O menu da barra de status oferece **Mostrar painel**.
- A janela é arrastável. Abre centralizada na parte inferior da tela e persiste sua última posição válida. Ao abrir, sua posição é limitada à área visível da tela atual.
- Se a rede cair, a sessão entra em estado `Interrompida por falta de conexão`; toda captura e envio param, a causa fica visível e o usuário pode finalizar. Não fazer tentativa silenciosa de continuar sem confirmação.

### 5.4 Finalizar e resumir

1. Ao finalizar, o app interrompe fontes de áudio, esvazia os buffers pendentes e encerra o reconhecimento.
2. Persiste os textos já produzidos. Nenhum buffer de áudio permanece em disco.
3. Se houver provedor de resumo, a sessão muda para `Gerando resumo`; caso contrário, para `Concluída sem resumo`.
4. O usuário pode fechar/ocultar o painel. O trabalho de resumo continua em tarefa supervisionada pelo aplicativo.
5. Ao sucesso, mostra notificação local e atualiza a sessão para `Concluída`.
6. Ao erro, preserva textos e marca `Resumo indisponível`, com mensagem acionável e opção de tentar novamente no detalhe da sessão.

## 6. Interface

### 6.1 Menu da barra de status

Estados visuais:

- inativo: ícone neutro;
- configurando/iniciando: indicador discreto;
- ativo: ponto vermelho e duração;
- pausado: indicador amarelo;
- erro: indicador vermelho com item **Ver erro**.

Itens do menu, nesta ordem:

1. estado atual;
2. **Nova sessão** (inativo) ou **Mostrar painel** (ativo/pausado);
3. **Pausar/Retomar** e **Finalizar sessão** quando aplicável;
4. **Sessões**;
5. **Configurações**;
6. **Sair**.

Não permitir duas sessões simultâneas no MVP.

### 6.2 Painel flutuante

- Largura fixa sugerida: 760 pt; altura entre 260 e 480 pt conforme o conteúdo.
- Tela inferior central por padrão; arrastável pelo cabeçalho; não redimensionável no MVP.
- Deve aparecer em todos os Spaces enquanto estiver visível e não tomar foco indevidamente.
- Cabeçalho: indicador, título, duração, botões ocultar e finalizar.
- Barra de fontes: controles para microfone e áudio do Mac, com estado ligado/desligado e erro individual.
- Rodapé: pausar/retomar, finalizar e estado de conectividade/provedor.
- Modo simples: uma lista rolável de blocos de transcrição.
- Modo tradução: duas colunas sincronizadas; coluna original à esquerda, tradução à direita. Em largura insuficiente, permitir rolagem horizontal, sem trocar para visual de abas.

### 6.3 Janela de sessões

Lista local ordenada por data decrescente. Cada linha contém título, data, duração, modo e estado. Não há busca no MVP.

Detalhe da sessão:

- título editável;
- metadados de modo, idiomas e duração;
- abas `Transcrição`, `Tradução` (somente quando houver) e `Resumo`;
- ação **Exportar Markdown**;
- ação **Excluir sessão**, com confirmação;
- em erro de resumo, ação **Tentar gerar resumo novamente** se houver um provedor válido.

### 6.4 Configurações

Abas:

1. **Geral** — idioma da interface, aparência, idioma padrão de transcrição, idioma padrão do resumo e opção de enviar texto ao provedor externo, ligada por padrão somente após explicação explícita.
2. **Provedores** — lista, adicionar/remover, testar conexão e escolher padrões para resumo/tradução.
3. **Dados** — número de sessões e espaço usado por dados textuais; botão **Limpar todas as sessões** com confirmação irreversível.
4. **Permissões** — estado de cada permissão, explicação e botão para os Ajustes do Sistema.

## 7. Áudio, transcrição e tradução

### 7.1 Captura

`AudioCaptureService` controla duas fontes independentes:

- `MicrophoneCapture`: dispositivo de entrada padrão do macOS no MVP;
- `SystemAudioCapture`: fluxo de áudio do display principal pelo ScreenCaptureKit.

O `SCStreamConfiguration` precisa capturar somente áudio e excluir áudio produzido pelo próprio processo, evitando realimentação. Os buffers das fontes são convertidos para PCM comum, normalizados, convertidos para mono e mixados apenas em memória pelo `AudioMixer`. A sessão pode ser iniciada quando uma ou ambas fontes estiverem ativas.

Os buffers devem passar diretamente para o reconhecedor e ser descartados após processamento. É proibido escrever `wav`, `caf`, `m4a`, buffers temporários ou logs contendo áudio.

### 7.2 Reconhecimento de fala

`SpeechTranscriptionService` usa o idioma padrão da transcrição para criar o reconhecedor. Deve preferir reconhecimento no dispositivo quando a combinação sistema/idioma o suportar; caso contrário, informar que o mecanismo pode usar rede. Como o produto exige rede em qualquer cenário, uma ausência de conectividade é sempre erro bloqueante.

O serviço deve lidar com reconhecimento contínuo criando novas requisições antes de limites de sessão do framework, preservando uma única ordem de segmentos. Resultados parciais atualizam somente a UI em memória; resultados finais/estáveis são persistidos como `TranscriptSegment`.

Não implementar detecção automática de idioma nem troca automática no MVP. Uma reunião no idioma diferente do padrão configurado poderá ter qualidade inferior; isso deve constar de uma dica na tela de início.

### 7.3 Tradução ao vivo

1. Apenas resultados finais/estáveis são colocados em uma fila serial de tradução.
2. Cada item leva texto, idioma origem, idioma destino, índice da sessão e contexto curto dos últimos segmentos traduzidos, quando o provedor suportar.
3. A fila preserva a ordem. Um erro em trecho individual deve mostrar erro naquele trecho e permitir reprocessamento interno limitado, sem bloquear os seguintes.
4. A interface atualiza a tradução progressivamente quando o provedor suportar streaming; caso contrário, substitui `Traduzindo…` pelo resultado final.
5. Nunca reescrever silenciosamente uma tradução já marcada final. Revisão por contexto é futura funcionalidade.

O aplicativo não envia áudio ao provedor de tradução; envia apenas texto transcrito. O usuário deve confirmar, nas Preferências, que textos de transcrição poderão ser enviados ao provedor escolhido.

## 8. Camada de provedores de IA

### 8.1 Contratos

Criar protocolos de domínio independentes da UI:

```swift
protocol AIProvider {
    var id: UUID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func validateConfiguration() async throws
}

protocol TranslationProvider: AIProvider {
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<TranslationEvent, Error>
}

protocol SummaryProvider: AIProvider {
    func generateSummary(_ request: SummaryRequest) async throws -> MeetingSummary
}
```

`ProviderCapabilities` deve declarar `supportsLiveTranslation`, `supportsStreamingTranslation`, `supportsSummary`, idiomas aceitos e limite recomendado de tamanho. A tela de iniciar sessão só lista provedores compatíveis com a tarefa escolhida.

`AIProviderRegistry` resolve configurações ativas sem expor segredos à UI. `ProviderConfiguration` contém somente metadados não secretos; a chave, refresh token e access token vivem no Keychain sob identificadores da configuração.

### 8.2 Provedores do MVP

#### Apple Speech

Não é um `AIProvider` de texto. É um `TranscriptionEngine` local/sistema selecionado no MVP. A separação impede que a camada de LLM seja acoplada à captura de áudio.

#### OpenAI API Key

- Cadastro por nome opcional e chave fornecida pelo usuário;
- chave guardada no Keychain;
- usado para resumo e/ou tradução, conforme escolha do usuário;
- validação segura, sem exibir a chave;
- chamadas textuais em streaming quando disponível;
- erros de autenticação, limite e rede traduzidos em mensagens compreensíveis.

#### Codex OAuth (pessoal e experimental)

- Login OAuth iniciado pelo próprio aplicativo em navegador seguro e retorno por callback registrado;
- tokens persistidos somente no Keychain e renovados pelo adaptador;
- nenhuma dependência de Pi Agent, Codex CLI ou aplicativo ChatGPT instalado;
- a implementação deve ficar em módulo próprio, atrás de `CodexOAuthProvider` e de uma flag de disponibilidade;
- se a capacidade de texto/streaming necessária não estiver disponível de forma confiável, a configuração deve indicar **Indisponível nesta versão** em vez de simular sucesso;
- não extrair cookies, tokens ou credenciais de outros aplicativos;
- registrar telemetria local mínima e sem conteúdo de reunião para diagnóstico, desabilitada por padrão;
- a documentação do repositório deve deixar claro que é uso pessoal e que o usuário responde pelos termos da assinatura.

### 8.3 Extensões futuras previstas

- `GeminiAPIProvider` (chave API);
- `OllamaProvider` (URL local, modelo e teste de conectividade);
- outros provedores compatíveis com texto/streaming.

Adicionar um provedor novo não pode exigir modificar os modelos de sessão, a UI de transcrição ou o serviço de áudio.

## 9. Resumo e pauta

Após encerrar, o `SummaryProvider` recebe a transcrição textual completa (e, opcionalmente, a tradução para referência), idioma de saída escolhido e instruções fixas. A resposta precisa ser Markdown estruturado nestas seções:

```markdown
# Resumo da reunião

## Resumo executivo

## Pauta discutida

## Decisões

## Pendências e responsáveis

## Perguntas em aberto

## Próximos passos
```

Não inventar responsáveis, decisões ou datas. Quando a informação não estiver explícita, usar linguagem de incerteza ou omitir o item. O idioma padrão do resumo é o idioma da interface; o usuário pode alterar a preferência manualmente nas configurações antes de criar/gerar o resumo.

O resumo é somente leitura no MVP. A aba deve renderizar Markdown e também preservar seu texto fonte para exportação.

## 10. Persistência local

Usar SwiftData em armazenamento privado do aplicativo. O modelo proposto:

### `MeetingSession`

- `id: UUID`;
- `title: String`;
- `createdAt`, `startedAt`, `endedAt`;
- `mode: simple | translation`;
- `status: draft | active | paused | finalizing | generatingSummary | completed | completedWithoutSummary | failed`;
- `transcriptionLanguage: LanguageCode`;
- `sourceLanguage`, `targetLanguage` opcionais;
- `summaryLanguage: LanguageCode`;
- `microphoneEnabled`, `systemAudioEnabled`;
- identificadores não secretos de provedores de tradução e resumo;
- `failureMessage` opcional;
- relações com segmentos e resumo.

### `TranscriptSegment`

- `id`, `sessionId`, `orderIndex`;
- `kind: speech | pausedMarker | resumedMarker`;
- `text`;
- `isFinal`;
- data técnica de criação, sem necessidade de exibi-la ao usuário.

### `TranslationSegment`

- `id`, `sessionId`, `transcriptSegmentId`, `orderIndex`;
- `translatedText`;
- `status: pending | streaming | completed | failed`;
- `failureMessage` opcional.

### `MeetingSummary`

- `id`, `sessionId`;
- `markdown`;
- `generatedAt`;
- provedor/modelo de origem apenas como metadado;
- estado e mensagem de falha, se houver.

### `ProviderConfiguration`

- `id`, `kind`, `displayName`, `isEnabled`, `createdAt`;
- configuração não secreta, como modelo selecionado ou URL local futura;
- referência de Keychain, nunca o segredo.

Excluir sessão remove suas entidades relacionadas e credenciais somente se o usuário excluir também a configuração de provedor. **Limpar todas as sessões** remove apenas dados de sessão, não provedores nem segredos. Ambas ações requerem confirmação explícita.

## 11. Exportação Markdown

Usar `NSSavePanel`. O arquivo deve usar nome derivado do título de sessão e conter:

```markdown
# <título>

- Data: <data local>
- Duração: <duração>
- Modo: <modo>
- Idioma da transcrição: <idioma>

## Transcrição

<segmentos em ordem, sem timestamps>

## Tradução

<pares original/tradução, somente se aplicável>

## Resumo

<markdown do resumo ou aviso de indisponibilidade>
```

O exportador não inclui tokens, chaves, IDs de credenciais ou áudio. Falha ao salvar não altera a sessão.

## 12. Organização de código sugerida

```text
quetta/
  App/
    quettaApp.swift
    AppCoordinator.swift
    AppState.swift
  Domain/
    Models/
    Protocols/
    UseCases/
  Features/
    Onboarding/
    MenuBar/
    SessionSetup/
    FloatingPanel/
    Sessions/
    Settings/
  Services/
    Audio/
      MicrophoneCapture.swift
      SystemAudioCapture.swift
      AudioMixer.swift
    Speech/
      SpeechTranscriptionService.swift
    Providers/
      AIProviderRegistry.swift
      OpenAIAPIProvider.swift
      CodexOAuthProvider.swift
    Persistence/
      PersistenceController.swift
      KeychainStore.swift
    System/
      PermissionService.swift
      ConnectivityService.swift
      NotificationService.swift
      FloatingPanelController.swift
  Resources/
    Localizable.xcstrings
```

`AppCoordinator` é a única fonte de verdade para o ciclo de vida de uma sessão ativa. Views observam modelos de apresentação; não iniciam captura, requisições de IA nem acesso ao banco diretamente.

## 13. Máquina de estados da sessão

```text
draft → active ⇄ paused → finalizing → generatingSummary → completed
  │        │          │         │               └──────→ completedWithoutSummary
  │        │          │         └──────────────────────→ completedWithoutSummary
  │        │          └────────────────────────────────→ failed
  │        └───────────────────────────────────────────→ failed
  └────────────────────────────────────────────────────→ failed
```

- `active`: captura e reconhecimento podem operar; tradução, se aplicável, consome a fila.
- `paused`: não recebe nem envia áudio/texto novo.
- `finalizing`: fecha recursos e persiste resultados finais.
- `generatingSummary`: não captura áudio; permite ocultar a UI.
- `completedWithoutSummary`: sessão válida cuja IA não está configurada ou falhou após preservação dos textos.
- `failed`: erro impeditivo antes de uma sessão utilizável; sempre manter motivo e ação de recuperação.

## 14. Privacidade e segurança

- Nenhum áudio bruto em persistência, cache, diagnóstico ou exportação.
- Apagar buffers de trabalho ao encerrar, pausar por falha ou falhar a inicialização.
- Textos só são enviados externamente quando a configuração de privacidade permitir e houver provedor selecionado.
- Informar o nome do provedor antes do primeiro envio; não alegar processamento local quando não for.
- Chaves e tokens em Keychain; mascarar segredos em UI e logs.
- Os logs de desenvolvimento não devem conter texto de transcrição por padrão.
- Usar HTTPS, validação padrão de certificados e `URLSession`; não criar proxy próprio.
- O aplicativo não deve solicitar permissões além de microfone, reconhecimento de fala, captura de tela/áudio e notificações locais opcionais.

## 15. Erros e mensagens mínimas

| Situação | Comportamento esperado |
| --- | --- |
| Sem internet | bloquear início; durante sessão, interromper processamento e explicar a causa |
| Microfone negado | bloquear apenas se microfone estiver ativo; oferecer Ajustes do Sistema |
| Captura do sistema negada | bloquear apenas se áudio do Mac estiver ativo; oferecer Ajustes do Sistema |
| Fala negada/indisponível | bloquear sessão e explicar que a transcrição não pode iniciar |
| Nenhuma fonte ativa | desabilitar botão de iniciar |
| Nenhum provedor de resumo | permitir modo simples, sinalizando `Sem resumo automático` |
| Nenhum provedor de tradução compatível | impedir o modo tradução até configurar um |
| Falha de autenticação do provedor | preservar sessão, marcar configuração como requer atenção e oferecer reconectar |
| Limite/rate limit | mostrar erro específico, preservar texto e permitir novo resumo depois |
| App encerrado durante sessão | encerrar recursos de forma ordenada; não prometer retomada de áudio após relançar |

## 16. Testes e critérios de aceite

### Testes unitários

- transições válidas e inválidas da máquina de estados;
- mistura e descarte de buffers sem escrita em disco;
- serialização da fila de tradução;
- seleção de provedor por capacidades;
- armazenamento Keychain abstraído com implementação falsa;
- geração do título automático;
- exportador Markdown em ambos os modos;
- limpeza de uma e de todas as sessões;
- localização de strings principais.

### Testes de integração/manuais

1. Em macOS 14+ com permissões concedidas, iniciar transcrição somente com microfone, somente com áudio do Mac e com ambos.
2. Confirmar que desligar uma fonte durante uma sessão interrompe somente essa fonte.
3. Confirmar que o painel abre inferior-central, move-se, é ocultável e retorna à última posição visível.
4. Confirmar que pausa não produz novos segmentos, cria os marcadores e retoma corretamente.
5. Confirmar que áudio não é criado em diretórios do app, temporários ou exportações.
6. No modo tradução, validar os seis pares direcionais PT↔EN, PT↔ES e EN↔ES, com segmentos preservando ordem.
7. Finalizar, ocultar painel, aguardar resumo e receber notificação local.
8. Validar sessão sem provedor de resumo e falha de provedor sem perda de transcrição.
9. Revogar cada permissão e validar a recuperação pela tela de permissões.
10. Desligar a rede antes e durante a sessão, confirmando a mensagem de erro e ausência de continuação silenciosa.

### Critérios de aceite do MVP

- O usuário consegue concluir o onboarding e entender exatamente quais permissões e dados externos estão envolvidos.
- Uma sessão simples transcreve ao vivo, persiste somente texto e gera resumo quando um provedor está configurado.
- Uma sessão de tradução mostra original e tradução lado a lado, em ordem, com provedor escolhido pelo usuário.
- O usuário consegue pausar, retomar, finalizar, ocultar/mostrar o painel e controlar cada fonte de áudio.
- O histórico local permite abrir, renomear, exportar em Markdown e excluir sessões.
- Nenhum áudio é salvo permanentemente.
- O aplicativo funciona em português e inglês e respeita a escolha claro/escuro/sistema.
- O projeto não requer Pi Agent, Codex CLI ou outro software de terceiros instalado para funcionar.

## 17. Ordem de implementação recomendada

1. Configurar estrutura de pastas, SwiftData, Keychain, localização e testes de domínio.
2. Implementar onboarding, permissões, conectividade, configurações e `MenuBarExtra`.
3. Implementar `NSPanel` flutuante, posicionamento persistente e máquina de estados sem áudio real.
4. Implementar microfone, ScreenCaptureKit, mixagem em memória e descarte seguro.
5. Integrar Apple Speech e persistir segmentos finais no modo simples.
6. Implementar lista/detalhe de sessões e exportação Markdown.
7. Implementar contratos de provedores e OpenAI API por chave para resumo.
8. Implementar fila e UI de tradução simultânea.
9. Implementar e validar o adaptador Codex OAuth isoladamente; mantê-lo experimental até passar testes reais de autenticação, renovação, limite e latência.
10. Executar bateria de testes manuais, revisão de privacidade e documentação de instalação open source.

## 18. Risco a validar antes de depender de Codex OAuth

Antes de promover o provedor Codex OAuth como padrão, realizar um _spike_ técnico curto e isolado que valide:

1. login e logout no próprio app;
2. persistência e renovação segura do token;
3. envio textual e resposta de streaming utilizável;
4. comportamento em limite de uso e expiração;
5. latência com frases curtas de tradução;
6. conformidade do fluxo com a documentação e os termos aplicáveis.

Se algum item não puder ser sustentado por contrato compatível, o aplicativo continua plenamente funcional com transcrição Apple Speech e provedor por chave API, e a configuração Codex OAuth fica desabilitada com explicação. Isso evita que uma dependência não estável bloqueie o restante do produto.
