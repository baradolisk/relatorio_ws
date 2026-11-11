# Opção 11 — Lista de autorizados

Essa opção compara os usuários dos eventos com os membros de grupos do Active
Directory indicados por você. Não cria permissões nem configura auditoria.

## O que é necessário

1. Execute no Windows com acesso ao domínio e ao log de Segurança do servidor.
2. Tenha o módulo **ActiveDirectory**, fornecido pelo RSAT, na máquina onde
   executa o script. Não é necessário habilitar `EnriquecerAD` para esta opção.
3. Use uma conta que consiga consultar os grupos e seus membros no domínio.
   A consulta usa a identidade atual, sem parâmetro próprio de credenciais ou
   seleção de controlador de domínio. DNS e conectividade com o AD, incluindo
   Active Directory Web Services, precisam funcionar.
4. Prepare um CSV UTF-8 separado por ponto e vírgula, com cabeçalho `Pasta;Grupo`.
   O caminho deve ser acessível pela máquina que executa o script.

No Windows Server, um administrador pode instalar o módulo:

```powershell
Install-WindowsFeature RSAT-AD-PowerShell
```

No Windows 10/11, use PowerShell elevado:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

Antes de executar o relatório, confirme:

```powershell
Get-Module -ListAvailable ActiveDirectory
Import-Module ActiveDirectory
Get-ADGroup -Identity 'GG_Financeiro'
Get-ADGroupMember -Identity 'GG_Financeiro' -Recursive |
    Select-Object SamAccountName, ObjectClass
```

## Preparar e selecionar a lista

Copie e adapte `examples/ListaAutorizados-exemplo.csv`, por exemplo:

```csv
Pasta;Grupo
E:\Dados\Financeiro;GG_Financeiro
E:\Dados\Financeiro\Folha;GG_Folha
```

Prefira o `SamAccountName` do grupo. O script remove o prefixo `DOMINIO\` ao
consultar o grupo; esse prefixo não seleciona outro domínio.

Em `Pasta`, use um trecho presente em `Objeto` ou `CaminhoLocal` do relatório.
Para misturar 5145/5140 com 4663/4660, prefira o caminho local registrado nos
eventos: 4663 e 4660 não fornecem necessariamente o caminho UNC. Uma regra UNC
não corresponde automaticamente ao caminho local equivalente.

No menu, escolha **11** e informe o caminho do CSV. `-` desativa a lista.
Também pode executar diretamente:

```powershell
.\Relatorio-AcessoPasta.ps1 -EventoId 5145,4663,4660 `
    -ListaAutorizados 'C:\Relatorios\autorizados.csv' `
    -CsvSaida 'C:\Relatorios\acessos.csv'
```

## Como interpretar

- `Autorizado`: o usuário consta em pelo menos um grupo aplicável lido.
- `NAO AUTORIZADO`: todos os grupos aplicáveis foram lidos e o usuário não consta neles.
- `Indeterminado`: algum grupo aplicável não pôde ser lido e nenhuma associação foi confirmada.
- `Sem regra`: nenhum trecho do CSV corresponde ao registro.

A regra com o trecho mais longo vence; regras igualmente específicas permitem
qualquer um dos grupos indicados. A busca é por trecho, não por fronteira de
diretório: revise caminhos com nomes parecidos. A comparação de usuários usa
`SamAccountName`, sem distinguir domínios com nomes de usuário iguais.

Essa classificação usa a associação **atual** aos grupos, inclusive membros
aninhados retornados por `Get-ADGroupMember -Recursive`. Não reconstitui grupos
na data histórica do evento nem avalia ACLs, negações, herança, associação por
grupo primário ou todas as condições de acesso. Confirme permissões efetivas
separadamente. Se houver aviso de grupo não lido, resolva a consulta ao AD antes
de usar a classificação para decisões.
