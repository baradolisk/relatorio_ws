# Relatório de acessos a arquivos

Veja quais eventos de acesso e exclusão o Windows registrou e salve o resultado
em uma tabela que pode ser aberta no Excel. Você escolhe servidor, período,
pasta e usuário pelo menu, sem precisar montar comandos com vários parâmetros.

Se encontrar uma sigla desconhecida, consulte o [glossário](docs/GLOSSARIO.md).
Para uma primeira consulta, siga o passo a passo abaixo.

## Começar pelo menu

1. Baixe o [script](Relatorio-AcessoPasta.ps1) ou use **Code → Download ZIP**.
2. Extraia o ZIP, se necessário, e localize `Relatorio-AcessoPasta.ps1`.
3. Abra o PowerShell como administrador. Entre na pasta onde salvou o script;
   por exemplo, use `cd C:\Scripts` se ele estiver nessa pasta.
4. Confira a [auditoria necessária](docs/AUDITORIA-WINDOWS.md) e execute:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

**O que deve aparecer:** uma tela com o título do relatório, a opção **L** para
consultar os logs e opções numeradas para preparar a busca. Se aparecer um erro
antes dessa tela, consulte [Resolver problemas](docs/SOLUCAO-DE-PROBLEMAS.md).

O menu começa com o último dia, todas as pastas/usuários e CSVs em `C:\Relatorios`, na unidade do Windows. Altere o que precisar. **E** executa; **Q** sai; **Enter** mantém; **`-`** limpa um filtro ou desativa um CSV.

Se o arquivo estiver bloqueado, veja [como liberar](docs/SOLUCAO-DE-PROBLEMAS.md#script-bloqueado).

## Detalhes dos logs

Execute `.\Relatorio-AcessoPasta.ps1 -Menu` e escolha **L — Detalhes dos logs**, no início do menu.
Informe o servidor (ou vários separados por vírgula) e o nome do log; `Security`
é o padrão. A consulta mostra tamanho atual, limite, espaço restante, ocupação,
quantidade de registros, primeiro/último evento, dias disponíveis, médias diárias
e estimativas de dias totais e até encher. Campos sem dados suficientes ficam vazios.

Para ver **registros por dia**, responda `S` à pergunta após o resumo. Essa
contagem lê todo o log e pode demorar; usa as datas retornadas pelo PowerShell
na máquina de execução e não lista dias sem eventos. A rotina volta ao menu,
sem executar o relatório de acessos nem gerar seus CSVs.

As estimativas pressupõem volume constante e podem ser distorcidas pela
pré-alocação do arquivo. Em log circular cheio, novos eventos substituem os
antigos. O intervalo disponível é uma referência de retenção, sem garantir
atividade em todos os dias. Execute com acesso de leitura ao log; consultas
remotas dependem também das permissões e das regras de firewall/RPC do Windows.

## Qual evento escolher?

| Evento | Uso |
| --- | --- |
| **5145** — padrão | Verificações de acesso pela rede SMB; não comprova leitura do conteúdo |
| **4663** | Direitos utilizados no objeto: leitura, gravação/criação, atributos e DELETE |
| **4660** | Exclusões; consulta automaticamente os eventos de apoio para identificar o caminho |
| **5140** | Conexões ao compartilhamento, sem detalhe de cada arquivo |

Na opção **2** do menu, informe um ou mais IDs ou opções separados por vírgula
(ex.: `5145,4663,4660` ou `1,2,4`). **Enter** mantém a seleção.
Todos os eventos selecionados entram no mesmo CSV, identificados pela coluna
`EventoId`. O resumo soma os eventos selecionados; eventos diferentes da mesma
operação podem representar mais de uma evidência, não operações únicas.

Opções disponíveis: **1 = 5145**, **2 = 4663**, **3 = 5140**, **4 = 4660**.

## Configurar a consulta pelo menu

1. **1 — Servidor(es):** informe o servidor de arquivos; para vários, use `SRV1,SRV2`.
2. **2 — Evento:** selecione um ou mais eventos separados por vírgula.
3. **3 — Período:** escolha últimos dias ou informe início e fim.
4. **4 — Pasta:** informe um trecho ou caminho; `-` consulta todas as pastas.
5. **5 — Usuário:** informe o nome ou `*` para todos. Se ativar nome exato,
   copie a grafia do log, incluindo maiúsculas e minúsculas.
6. **9 e 10 — CSVs:** confira os destinos do detalhado e do resumo.
7. Digite **E** e confirme a execução. Ao terminar, **Enter** volta ao menu.

Na opção **8**, você pode incluir contas de computador e compartilhamentos
administrativos, desativados por padrão, e ajustar as demais opções.

A **opção 11** compara os acessos com um CSV `Pasta;Grupo` e exige
ActiveDirectory/RSAT e acesso ao domínio. Veja [pré-requisitos e configuração](docs/LISTA-AUTORIZADOS.md).

## Arquivos gerados

| Arquivo | Conteúdo |
| --- | --- |
| **9 — CSV detalhado** | Detalhado: usuário, caminho, horário, ação e evidência |
| **10 — CSV resumo** | Resumo por usuário e pasta |
| `<arquivo-detalhado>.execucao.csv` | Contagens, período efetivamente lido, limite e estado da consulta |

`{data}` acrescenta data/hora ao nome. Os CSVs usam `;` como separador. Proteja a pasta de saída: contém dados de usuários e do ambiente.

## Interpretar sem confundir

- **Zero durante o progresso não é o resultado final.** Confira o horário processado e a quantidade do evento escolhido, separados dos eventos de apoio.
- **Gravação ou criação** não distingue com segurança “novo” de “editado”.
- **4660 confirma a exclusão**; o caminho é associado a um 4656 válido ou a um 4663 com DELETE próximo. Sem evidência suficiente, fica vazio.
- O modo 4660 lê cinco minutos anteriores para apoio, sem exportar exclusões anteriores ao período pedido. Isso pode aumentar a leitura.
- O script consulta o log ativo, não arquivos `.evtx` arquivados. Auditoria não recupera eventos anteriores à habilitação.

## Como continuar a leitura

Para usar pela primeira vez, abra [Exemplos pelo menu](docs/EXEMPLOS.md).
Para entender cada campo, consulte [Opções do menu](docs/PARAMETROS.md).
Se o Windows ainda não grava os eventos, siga [Preparar auditoria](docs/AUDITORIA-WINDOWS.md).
Quando uma palavra ou sigla não estiver clara, use o [Glossário](docs/GLOSSARIO.md).

## Guias

[Exemplos](docs/EXEMPLOS.md) · [Opções do menu](docs/PARAMETROS.md) · [Configurar auditoria e logs](docs/AUDITORIA-WINDOWS.md) · [Resolver problemas](docs/SOLUCAO-DE-PROBLEMAS.md)

Requisitos: Windows Server, PowerShell 5.1 ou posterior e acesso ao log de Segurança. ActiveDirectory/RSAT é opcional para consultas de grupos/cadastro; interface gráfica é opcional para GridView. O relatório apenas consulta dados: não muda auditoria nem permissões. Testes automatizados usam PowerShell 7 e fontes simuladas; valide a configuração no seu servidor.

**Atualizando uma instalação antiga?** O único relatório agora é `Relatorio-AcessoPasta.ps1`, na raiz. Use o arquivo da raiz para abrir o menu. Versões alternativas foram removidas; o histórico permanece nos commits do Git.

[Alterações](CHANGELOG.md) · [Contribuir](CONTRIBUTING.md)
