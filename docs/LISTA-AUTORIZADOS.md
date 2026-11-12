# Opção 11 — Lista de autorizados

Use esta opção quando você já tem uma regra de negócio como: “a pasta
Financeiro deve ser acessada por pessoas do grupo GG_Financeiro”. Você informa
essa regra em um arquivo e o programa compara os usuários encontrados nos
eventos com os membros atuais do grupo no Active Directory.

Essa comparação ajuda a separar registros para revisão. Ela não concede nem
remove acesso e não substitui a conferência das permissões da pasta. Se o
termo Active Directory ou outra sigla for novo para você, consulte o
[glossário](GLOSSARIO.md).

## O que é necessário

1. Execute no Windows com acesso ao domínio e ao log de Segurança do servidor.
2. Tenha o módulo **ActiveDirectory**, fornecido pelo RSAT, na máquina onde
   executa o script. Não é necessário marcar `EnriquecerAD` na opção **8** para esta opção.
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

## Verificar se a consulta ao grupo funciona

Execute os comandos abaixo na mesma máquina e com a mesma conta que usará no
relatório. Troque `GG_Financeiro` pelo nome de um grupo real da sua empresa.
O primeiro comando deve encontrar o módulo; o segundo carrega suas ferramentas;
o terceiro procura o grupo; o último lista os membros, incluindo grupos internos.
Se alguma etapa falhar, resolva essa etapa antes de usar a classificação do relatório.

```powershell
Get-Module -ListAvailable ActiveDirectory
Import-Module ActiveDirectory
Get-ADGroup -Identity 'GG_Financeiro'
Get-ADGroupMember -Identity 'GG_Financeiro' -Recursive |
    Select-Object SamAccountName, ObjectClass
```

**Resultado esperado:** o grupo é encontrado e os membros são listados sem
mensagem de erro. Um grupo válido pode não ter membros; isso é diferente de uma
falha de consulta. Se aparecer “grupo não encontrado”, confira o nome e o domínio.
Se aparecer erro de conexão, peça a conferência do DNS e do acesso ao AD.

## Preparar e selecionar a lista

1. Copie o [modelo de lista](../examples/ListaAutorizados-exemplo.csv) para uma
   pasta em que sua conta tenha acesso, por exemplo `C:\Relatorios`.
2. Abra a cópia em um editor de texto. Preserve a primeira linha `Pasta;Grupo`.
3. Substitua os caminhos e grupos pelos valores reais. Cada linha associa um
   caminho a um grupo. Para permitir dois grupos na mesma pasta, crie duas
   linhas com o mesmo caminho e um grupo em cada uma.
4. Salve em UTF-8, com extensão `.csv` e separador ponto e vírgula. Se usar
   Excel, confirme esses detalhes ao salvar ou importar.

Exemplo:

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

Abra o menu:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

Escolha **11** e informe o caminho do CSV, por exemplo
`C:\Relatorios\autorizados.csv`. `-` desativa a lista. Em **2**, selecione os
eventos desejados, por exemplo `5145,4663,4660`; confira os destinos em **9** e
**10** e execute com **E**.

### Conferir o resultado da consulta

Durante a execução, o programa informa quantas regras foram carregadas e quantos
grupos conseguiu ler. Compare esses números com o arquivo preparado. Se algum
grupo não puder ser lido, um aviso explica a falha; o relatório pode continuar,
mas a classificação desse grupo ficará limitada.

No CSV detalhado, procure a coluna Autorizacao. Confira também Usuario, Objeto,
CaminhoLocal, Resultado e Evidencia. Assim você vê qual acesso foi comparado e
se o evento descreve uma verificação, um direito utilizado ou uma exclusão.

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

## Exemplo de regra mais específica

Se o CSV contém `E:\Dados\Financeiro` para GG_Financeiro e
`E:\Dados\Financeiro\Folha` para GG_Folha, um registro na pasta Folha usa a
regra com o texto mais longo, ou seja, GG_Folha. A regra geral não é somada a ela
automaticamente. Se a intenção for permitir ambos nessa subpasta, cadastre ambos
com o mesmo caminho da subpasta.

Se o resultado for Sem regra, compare o texto do CSV com Objeto e CaminhoLocal.
Por exemplo, um evento pode conter `E:\Dados\Financeiro`, enquanto a lista usa
somente `\\SRV\Financeiro`. O programa não considera esses textos equivalentes
por saber que apontam para a mesma pasta; use um caminho presente no registro.
