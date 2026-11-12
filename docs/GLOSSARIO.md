# Glossário — entenda os nomes usados no relatório

Este documento explica os termos que aparecem no menu, nos manuais e nos CSVs.
Não é necessário decorar as siglas. Consulte a seção correspondente quando um
nome desconhecido aparecer. Para começar a usar o programa, siga o [README](../README.md).

## Arquivos, rede e caminhos

| Termo | Significado e exemplo |
| --- | --- |
| Script | Arquivo com instruções que o PowerShell executa. Neste projeto, é `Relatorio-AcessoPasta.ps1`. |
| PowerShell | Ferramenta do Windows para executar comandos e scripts. Abra como administrador para consultar o log de Segurança quando sua conta tiver essa permissão. |
| Parâmetro | Informação passada ao iniciar um script. Neste manual, use apenas `-Menu`; os demais ajustes são feitos na tela. |
| Servidor de arquivos | Computador que guarda e compartilha pastas para outras pessoas da rede. Exemplo: `SRV-ARQ1`. |
| Estação | Computador usado por uma pessoa para acessar o servidor. Pode aparecer identificado por endereço IP. |
| SMB — Server Message Block | Protocolo usado pelo Windows para acessar arquivos e pastas compartilhados pela rede. Abrir `\\SRV-ARQ1\Financeiro` normalmente usa SMB. O evento 5145 registra uma verificação desse acesso. |
| Compartilhamento / share | Nome pelo qual uma pasta é oferecida na rede. A pasta `E:\Dados\Financeiro` pode ser compartilhada como `Financeiro`. O nome da rede pode ser diferente do nome da pasta no disco. |
| Compartilhamento administrativo | Compartilhamento voltado à administração, como `C$`, `ADMIN$` ou `IPC$`. O relatório os exclui por padrão para reduzir registros que podem não interessar à consulta. |
| Caminho local | Endereço no disco do servidor: `E:\Dados\Financeiro\arquivo.xlsx`. A unidade E: de outro computador pode apontar para um local diferente. |
| UNC — Universal Naming Convention | Forma de escrever um caminho de rede: `\\servidor\compartilhamento\pasta`. As duas barras iniciais indicam um endereço de rede. |
| Caminho relativo | Parte do endereço dentro do compartilhamento. Em `\\SRV\Dados\RH\a.txt`, o relativo ao compartilhamento `Dados` é `RH\a.txt`. |
| FQDN — Fully Qualified Domain Name | Nome completo de um computador no domínio, como `srv-arq1.empresa.local`. O nome curto seria `SRV-ARQ1`. |
| Alias | Nome alternativo para o mesmo servidor. Nem todo nome alternativo é traduzido automaticamente pelo relatório. |
| DFS — Distributed File System | Recurso que apresenta pastas de diferentes servidores em um endereço de rede comum. Esse endereço pode não ser o servidor que gravou o evento. |
| DNS — Domain Name System | Serviço que encontra computadores pelo nome. DNS reverso tenta descobrir um nome a partir de um IP; o resultado pode estar desatualizado. |
| IP | Endereço de rede de um computador, como `192.168.1.20`. O mesmo endereço pode ser reutilizado em outro momento. |
| Porta | Número que identifica uma comunicação de rede. No CSV, a porta vem do evento e não identifica sozinha uma pessoa. |
| RPC — Remote Procedure Call | Mecanismo usado por serviços do Windows para conversar entre computadores. A consulta remota de eventos depende das permissões e das regras de rede correspondentes. |
| Firewall | Controle que permite ou bloqueia comunicações. Para acesso remoto, ajuste as regras necessárias com o administrador; não é preciso desligar toda a proteção. |
| CIM — Common Information Model | Tecnologia de consulta de informações de computadores. O inventário de compartilhamentos pode depender dela, mesmo quando a leitura do log já funciona. |

## Auditoria, permissões e domínio

| Termo | Significado e importância |
| --- | --- |
| Auditoria | Configuração que faz o Windows registrar determinadas ações. Precisa estar ativa antes da ação; não cria histórico retroativo. |
| Log / registro de eventos | Histórico mantido pelo Windows. Um log contém muitos eventos; cada evento representa uma ocorrência registrada. |
| Security / Segurança | Nome do log do Windows usado para os eventos de auditoria deste relatório. Nos comandos, o nome é `Security`, mesmo no Windows em português. |
| Evento / ID do evento | Tipo da ocorrência. `4660`, por exemplo, indica exclusão registrada. Vários registros diferentes podem ter o mesmo ID de evento. |
| Êxito / falha | Resultado de auditoria informado no evento. O significado depende do evento: êxito em uma verificação 5145 não comprova leitura do conteúdo. |
| File Share | Subcategoria de auditoria de compartilhamentos, associada ao evento 5140. |
| Detailed File Share | Auditoria detalhada de compartilhamentos, associada ao 5145. Registra verificações de acesso pela rede. |
| File System | Auditoria do sistema de arquivos. Para eventos como 4663 e 4660, é necessário configurar também a auditoria dos objetos desejados. |
| SACL — System Access Control List | Lista de auditoria de um arquivo ou pasta: define quais usuários e ações devem gerar eventos. Fica em Segurança → Avançado → Auditoria. Não concede acesso à pasta. |
| ACL — Access Control List | Lista de regras de segurança. No uso de permissões, a DACL define acessos permitidos ou negados; a SACL define auditoria. |
| DACL — Discretionary Access Control List | Lista de permissões permitidas e negadas para usuários e grupos em um objeto. |
| NTFS | Sistema de arquivos do Windows que oferece permissões e auditoria por arquivo e pasta. O acesso pela rede também pode depender das permissões do compartilhamento. |
| Herança | Aplicação de regras de uma pasta aos seus arquivos e subpastas. Uma regra pode estar herdada ou ter sido definida diretamente no objeto. |
| Permissão efetiva | Acesso resultante da combinação de regras aplicáveis à conta. A lista de autorizados do relatório não calcula essa combinação. |
| AD — Active Directory | Serviço de diretório que mantém usuários, grupos e computadores de um domínio Windows. |
| Domínio | Conjunto de contas e computadores administrados em uma estrutura comum, como `EMPRESA`. Não é o mesmo que o nome do servidor de arquivos. |
| Controlador de domínio | Servidor que fornece serviços do domínio, como autenticação e consultas ao diretório. |
| ADWS — Active Directory Web Services | Serviço utilizado por ferramentas de administração do AD, incluindo consultas do módulo ActiveDirectory. Sua disponibilidade é um requisito para essas consultas. |
| RSAT — Remote Server Administration Tools | Conjunto de ferramentas administrativas do Windows. O componente de AD fornece o módulo PowerShell `ActiveDirectory`. |
| Módulo | Conjunto de comandos adicionais do PowerShell. `ActiveDirectory` fornece comandos como `Get-ADGroupMember`. |
| Grupo / membro | Grupo reúne contas para organizar acessos. Membro é uma conta ou outro grupo incluído nele. |
| Grupo aninhado / consulta recursiva | Um grupo pode conter outro grupo. A consulta recursiva tenta incluir os membros desses grupos internos. |
| Grupo primário | Grupo especial associado à conta no AD. A consulta usada pela lista de autorizados não cobre todas as formas possíveis de associação, incluindo essa situação. |
| SamAccountName | Nome de conta usado no AD, como `joao` ou `GG_Financeiro`. Nomes iguais podem existir em domínios diferentes. |
| SID — Security Identifier | Identificador de segurança de uma conta ou grupo, como `S-1-5-21-...`. É diferente do nome exibido da conta. |
| GPO — Group Policy Object | Conjunto de políticas aplicadas pelo domínio. Uma GPO pode definir auditoria e tamanho do log, substituindo configurações feitas localmente. |
| Conta de computador | Identidade usada por um computador no domínio; normalmente termina em `$`. Não representa necessariamente uma ação direta de uma pessoa. |
| Conta de serviço | Conta usada por programa, tarefa ou serviço, como uma rotina de backup. Seus acessos podem gerar muitos eventos. |

## Ações e associação de exclusões

| Termo | Significado |
| --- | --- |
| Objeto | Arquivo ou pasta ao qual o evento se refere. Não é necessariamente o processo que fez o acesso. |
| Metadados / atributos | Informações sobre o arquivo, como propriedades. Consultá-las não significa ler o conteúdo do documento. |
| Processo / ProcessId | Programa em execução e seu identificador numérico. Um identificador pode ser reutilizado depois que o processo termina. |
| Sessão / LogonId | Contexto de entrada de uma conta no Windows. Ajuda a separar acessos feitos pela mesma conta em sessões diferentes. |
| Handle / HandleId | Identificador temporário usado por um processo para se referir a um objeto aberto. Pode ser reutilizado; por isso não basta comparar apenas esse número. |
| Handle Manipulation | Subcategoria de auditoria que pode registrar uso e fechamento de identificadores, como o evento 4658. |
| Correlação | Associação de eventos diferentes para reconstruir parte de uma ação. Como o 4660 não traz o nome do arquivo, o script busca esse nome em eventos próximos e compatíveis. |
| Evento de apoio | Registro usado para ajudar a interpretar outro evento. Não entra como linha do relatório só por ter sido lido; precisa também ser um tipo selecionado e passar pelos filtros. |
| AccessMask / máscara de acesso | Número que representa direitos de acesso. Pode combinar vários direitos. O prefixo `0x` indica escrita hexadecimal. |
| Hexadecimal | Forma de escrever números com dígitos de 0 a 9 e letras de A a F. `0x10000` representa o direito DELETE. |
| DELETE | Direito de exclusão. Um 4663 com esse direito é uma evidência de apoio; a exclusão confirmada no relatório exige 4660. |
| DELETE_CHILD | Direito de excluir filhos de uma pasta. Isoladamente não é usado como alternativa para associar o caminho ao 4660. |
| Cache | Memória temporária usada pelo script. Na correlação, guarda informações de objetos abertos, com limite para evitar crescimento sem controle. |

## Arquivos de saída e campos do relatório

| Termo / campo | Como ler |
| --- | --- |
| CSV — Comma-Separated Values | Arquivo de tabela em texto. Neste projeto, as colunas são separadas por ponto e vírgula (`;`). Pode ser aberto ou importado no Excel. |
| UTF-8 / BOM | UTF-8 é uma codificação de texto que suporta acentos. BOM é uma marca inicial que ajuda alguns programas a reconhecer a codificação. |
| EVTX | Formato de arquivo de eventos do Windows. O script consulta o log ativo; não abre arquivos históricos EVTX arquivados. |
| `{data}` | Marcador substituído pela data e hora no nome do CSV, ajudando a separar execuções. |
| `.execucao.csv` | Arquivo de diagnóstico gerado junto do detalhado. Informa contagens, período consultado, duração e limitações por servidor. |
| DataHora / PrimeiroAcesso / UltimoAcesso | Horários do registro ou da primeira e última ocorrência quando há agrupamento. |
| Servidor / RecordId / EventoId | Computador de origem, número do registro naquele log e tipo do evento. `RecordId` não é um identificador global entre servidores ou históricos diferentes. |
| Usuario / UsuarioSid / LogonId | Conta, seu identificador de segurança e o contexto da sessão informado no evento. |
| Resultado / Acao / Evidencia | Resultado informado, classificação feita pelo relatório e explicação do que os dados permitem concluir. Leia os três juntos. |
| IP / Porta / Estacao | Dados de rede do evento e nome obtido por consulta reversa quando habilitada. Alguns tipos de evento não fornecem esses dados. |
| Objeto / CaminhoLocal / Compartilhamento / CaminhoRelativo | Diferentes formas de localizar o arquivo ou pasta. Os campos disponíveis dependem do tipo de evento. |
| Processo / ProcessId / HandleId / TipoObjeto | Dados do programa e do objeto acessado. Campos vazios podem significar que o evento não fornece a informação. |
| Acesso / AccessMask / AccessList | Descrição e dados técnicos dos direitos registrados. Não substituem a leitura da coluna Evidencia. |
| AccessReason / ConcedidoPor | Dados disponíveis sobre a regra relacionada ao acesso. Não identificam quem configurou as permissões da pasta. |
| PermissaoAmpla | Sinalização auxiliar de permissões amplas identificadas nos dados disponíveis; campo vazio não comprova acesso restrito. |
| Ocorrencias | Quantidade de eventos representados pela linha. Sem agrupamento, normalmente é 1. |
| PastaResumo | Referência usada para reunir registros por pasta no resumo. |
| Departamento / Cargo | Informações atuais consultadas no AD quando EnriquecerAD está ativado. |
| Autorizacao | Comparação auxiliar com o CSV da opção 11. Pode ser Autorizado, NAO AUTORIZADO, Indeterminado ou Sem regra. Não equivale à permissão efetiva. |
| RecordIdAbertura / RecordIdAcesso | Registros de abertura 4656 e de acesso 4663 usados como evidência na correlação, quando disponíveis. |
| EventoCorrelacao / RecordIdCorrelacao | Tipo e número do evento que forneceu o caminho da exclusão. |
| InicioConsulta | Início real da leitura, que pode ser cinco minutos anterior ao período pedido para buscar apoio de exclusões. |
| ExclusoesAnterioresComoApoio | Exclusões anteriores ao período lidas como contexto, sem exportação como exclusões do período. |
| EventosAlvoLidos / EventosApoioLidos | Eventos selecionados no período e eventos lidos apenas para apoiar o processamento. |
| EventosAlvoDescartados / FalhasConversao | Alvos que não viraram linhas e falhas ao interpretar eventos. Leia os avisos e filtros para entender a causa. |
| Consulta parcial | Busca interrompida ou limitada antes de cobrir todo o conjunto. O que foi encontrado pode não ser todo o resultado. |
| Agrupar | Reunir ocorrências semelhantes do mesmo tipo no mesmo minuto. Cada linha deixa de representar necessariamente um único evento. |
| Curinga | Símbolo de busca: `*` representa qualquer sequência de caracteres. `*silva*` encontra nomes que contenham “silva”. |
| Nome exato | Busca que exige a grafia correspondente no log, inclusive maiúsculas/minúsculas, nas condições informadas pelo menu. |

## Tamanho, espaço e retenção dos logs

| Termo / campo | Como interpretar |
| --- | --- |
| MB / GB | Unidades de tamanho. Os cálculos do PowerShell usados aqui consideram 1 MB como 1.048.576 bytes e 1 GB como 1.024 desses MB. |
| TamanhoAtualMB | Tamanho atual do arquivo em disco. Pode incluir espaço reservado que ainda não representa eventos úteis. |
| LimiteConfiguradoMB | Tamanho máximo configurado para o log. Não é o espaço livre total do disco. |
| EspacoRestanteMB / OcupacaoPercentual | Diferença até o limite do log e proporção ocupada. Não medem o espaço livre da unidade do Windows. |
| DiasDisponiveis | Intervalo entre o evento mais antigo e o mais recente. Não garante eventos em cada dia nem cobertura contínua. |
| MediaRegistrosPorDia | Quantidade de registros dividida pelo intervalo disponível. É uma média; não é a contagem real de cada dia. |
| MediaEstimadaMBPorDia | Tamanho atual dividido pelo intervalo disponível. Espaço reservado previamente pode distorcer essa conta. |
| Contagem exata por dia | Leitura dos eventos disponíveis e contagem por data. Dias sem registros não são listados; a data é a retornada pelo PowerShell na máquina que executa a consulta. |
| EstimativaDiasTotaisNoLimite | Aproximação de quantos dias caberiam no limite configurado, supondo o mesmo volume médio. Não é uma garantia de retenção futura. |
| EstimativaDiasAteEncher | Aproximação do tempo para usar o espaço restante do log. Zero em log circular cheio não significa que a gravação vai parar. |
| Retenção / ModoRetencao | Regra que define o que acontece com os eventos quando o log chega ao limite. |
| Circular / sobrescrita | O log substitui eventos antigos para acomodar novos quando está cheio. O histórico mais antigo deixa de estar disponível. |
| Arquivamento automático | O Windows salva um arquivo histórico quando o log enche e continua em outro. Os arquivos históricos consomem espaço e precisam de uma política de guarda. |
| Pré-alocação | Reserva antecipada de espaço no arquivo. Como tamanho reservado não é necessariamente conteúdo gravado, pode distorcer estimativas por MB/dia. |
| Limpeza do log | Remoção do histórico do log. Aumentar o tamanho depois não recupera os eventos apagados. |

## Ferramentas citadas na preparação do Windows

`auditpol` consulta ou altera políticas de auditoria; `wevtutil` administra logs;
`Get-WinEvent` lê eventos e informações de logs; `Get-SmbShare` lista
compartilhamentos. Esses comandos de preparação têm funções próprias. Para
abrir o relatório, continue usando apenas `Relatorio-AcessoPasta.ps1 -Menu`.

Política de execução controla como o PowerShell aceita scripts. `RemoteSigned`
pode exigir assinatura em arquivos identificados como baixados; `AllSigned`
exige assinatura conforme a política. `Unblock-File` remove a marca de download,
mas não substitui uma assinatura exigida pela organização. Uma política definida
por GPO pode impedir uma alteração local.
