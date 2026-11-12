# Opções do menu

Abra o PowerShell como administrador na pasta do script e execute:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

Este guia acompanha os nomes que aparecem na tela. Você não precisa preencher
todas as opções: comece conferindo o servidor, os eventos e o período. Os demais
campos servem para reduzir a busca ou escolher como salvar o resultado.
Veja também o [glossário de termos](GLOSSARIO.md).

Configure a consulta na tela. **Enter** mantém o valor; **`-`** limpa um filtro
ou desativa um caminho de CSV. **E** executa o relatório; **Q** sai.

| Opção | Como usar |
| --- | --- |
| **L — Detalhes dos logs** | Consulta independente: tamanho, limite, espaço restante, quantidade de registros, período disponível e estimativas. Informe servidor e nome do log; `Security` é o padrão. Responda `S` para contar registros por dia; essa leitura pode demorar. |
| **1 — Servidor(es)** | Computador local por padrão. Para vários, digite `SRV1,SRV2`. Não descobre servidores automaticamente. |
| **2 — Evento** | Padrão 5145. Aceita vários IDs (`5145,4663,4660`) ou opções (`1,2,4`). No seletor: 1 = 5145, 2 = 4663, 3 = 5140, 4 = 4660. Todos entram no mesmo relatório; 4660 lê apoio para correlacionar o caminho. |
| **3 — Período** | Escolha últimos N dias (1 a 3650) ou período específico. No período específico, Enter aceita a data sugerida; fim vazio significa até agora e `-` apaga um fim preenchido. |
| **4 — Pasta/compartilhamento** | Trecho ou caminho local/UNC. `-` remove o filtro. Busca por trecho pode incluir nomes parecidos. |
| **5 — Usuário** | Nome, curinga (`*silva*`) ou `DOMINIO\usuario`; `*` consulta todos. Para nome sem curingas, a tela oferece nome exato, sensível a maiúsculas/minúsculas. |
| **6 — Resultado** | Todos, somente êxito ou somente falha. |
| **7 — Excluir usuários** | Contas ou padrões separados por vírgula, como `svc-backup,svc-av*`; `-` limpa a lista. |
| **8 — Opções** | Digite os números exibidos nessa tela para marcar/desmarcar; Enter volta ao menu principal. Veja os efeitos abaixo. |
| **9 — CSV detalhado** | Destino do arquivo com os registros e evidências; `-` desativa. |
| **10 — CSV resumo** | Destino do agregado por usuário e pasta; `-` desativa. |
| **11 — Lista de autorizados** | Caminho do CSV `Pasta;Grupo`; `-` desativa. Requer AD/RSAT. Veja [pré-requisitos](LISTA-AUTORIZADOS.md). |
| **12 — Limite de diagnóstico** | Máximo de eventos lidos por servidor antes dos filtros locais. Zero não limita. Em 4660, conta também os eventos de apoio. Atingir o limite pode deixar a consulta parcial. |

Os CSVs usam `;` e aceitam `{data}` no nome. No menu, os destinos iniciais são
`C:\Relatorios\acessos-{data}.csv` e `C:\Relatorios\resumo-{data}.csv`, usando a
unidade do Windows quando diferente de C:.

## Opções adicionais — tela 8

| Nome exibido | Efeito |
| --- | --- |
| IgnorarAtributos | Descarta acessos considerados ruído; pode remover atividade relevante. |
| Agrupar | Consolida eventos semelhantes do mesmo tipo no mesmo minuto; desative para preservar cada evento. |
| IncluirContasComputador | Inclui contas terminadas em `$`. |
| IncluirCompartilhamentosEspeciais | Inclui IPC$, ADMIN$, print$ e compartilhamentos como C$. |
| ListarCompartilhamentos | Consulta o inventário dos servidores informados; depende de CIM. |
| EnriquecerAD | Acrescenta departamento e cargo; requer AD/RSAT. |
| ResolverSids | Traduz SIDs usando o domínio; pode demorar. Sem isso, o identificador permanece no relatório. |
| ResolverIP | Consulta DNS reverso; pode ser lento ou não refletir o nome real da estação. |
| Silencioso | Ativado por padrão. Oculta tabelas, mas mantém avisos e progresso. |
| GridView | Mostra o resultado em uma janela; requer interface gráfica e Out-GridView. |
| PassThru | Retorna objetos do relatório ao PowerShell. Para consultar e exportar pelo menu, pode permanecer desativado. |

As demais opções da tela 8 começam desativadas. A lista de autorizados é uma
comparação auxiliar por grupo e trecho do caminho; não comprova permissões efetivas.

## Como preencher sem perder a configuração

Ao entrar em uma opção, o valor atual aparece entre colchetes quando aplicável.
Se ele estiver correto, pressione Enter. Para mudar, digite o novo valor e
confirme com Enter. Depois, a tela principal mostra a configuração atualizada.

O símbolo `-` tem função de limpeza em campos que permitem isso. Por exemplo,
na opção 4 remove a restrição de pasta; na opção 9 desativa a exportação do
detalhado. Ele não significa “voltar” em todas as telas. Leia a pergunta antes
de responder. Para voltar da tela de opções adicionais, use Enter.

Depois de ajustar a opção 3, confira a descrição do período na tela principal.
Ela deve refletir a janela que você quer consultar. Em período específico,
use o formato de data e hora solicitado na tela; Enter mantém a data sugerida.

## O que acontece quando você escolhe E

O programa mostra um comando equivalente à configuração e pede confirmação.
Para o uso descrito neste manual, você pode continuar pelo próprio menu:
confirme com S ou Enter, ou responda N para revisar os campos antes de executar.
Não é necessário copiar o comando exibido.

Durante a busca, o programa informa o andamento. Aguarde a mensagem de término
antes de interpretar a quantidade de linhas. Ao concluir, confira os caminhos
dos CSVs e os avisos, pressione Enter e escolha outra consulta ou Q para sair.
A opção L faz uma consulta separada e não executa a busca de acessos preparada
nas opções numeradas.
