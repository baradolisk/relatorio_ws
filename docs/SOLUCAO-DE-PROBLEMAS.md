# Solução de problemas

## Script não assinado / execução bloqueada

Inspecione a política:

```powershell
Get-ExecutionPolicy -List
```

Após conferir a origem do arquivo, remova a marca de download:

```powershell
Unblock-File -LiteralPath .\Relatorio-AcessoPasta.ps1
```

Se MachinePolicy e UserPolicy estiverem Undefined e a política da empresa
permitir, é possível usar apenas na sessão atual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Uma GPO AllSigned exige assinatura por certificado confiável. Não é resolvida
com Unblock-File; siga o processo de assinatura do administrador do domínio.

## “Não é possível localizar um parâmetro posicional … usuario”

O nome pertence a Usuario; UsuarioExato é um switch:

```powershell
.\Relatorio-AcessoPasta.ps1 -Usuario "usuario.teste" -UsuarioExato -Dias 1
```

Para evitar erros de continuação de linha, use splatting:

```powershell
$opcoes = @{Usuario='usuario.teste'; UsuarioExato=$true; Dias=1}
.\Relatorio-AcessoPasta.ps1 @opcoes
```

UsuarioExato diferencia caixa no log. Para investigar grafia/domínio, remova a
opção e use Usuario com o nome ou um padrão, por exemplo `*teste*`.

## Sem eventos ou sem resultados

No servidor, verifique cada tipo separadamente:

```powershell
foreach ($id in 5145, 4663, 5140) {
    $ev = @(Get-WinEvent -FilterHashtable @{
        LogName='Security'; Id=$id; StartTime=(Get-Date).AddDays(-1)
    } -MaxEvents 5 -ErrorAction Continue)
    [pscustomobject]@{Evento=$id; Amostra=$ev.Count; MaisRecente=($ev | Select-Object -First 1).TimeCreated}
}
```

Amostra é limitada a 5; não representa o total. Leia erros: falha de acesso não
é equivalente a zero eventos. Se só existir 5140, confira a política Detailed
File Share para 5145. Para 4663, confira também SACL. Remova temporariamente
filtros de pasta e usuário, faça um acesso controlado por rede e consulte os
últimos 15 minutos. O período do relatório precisa incluir a data do teste.

## Caminho absoluto funciona, nome de rede não

Confirme o nome real em Get-SmbShare. O Windows pode gravar `\\*\z` em vez
de `\\SERVIDOR\z`. A correção do original normaliza esse nome e trata nomes
curtos/FQDN do servidor. Use o original atualizado e o servidor correto em
Computador. No v8, use o caminho resultante no CSV ou caminho local para 4663;
a correção UNC mais recente não foi portada integralmente para a v8.

Aliases, nomes DFS e caminhos locais não são intercambiáveis automaticamente.
Não presuma que o nome da pasta no disco seja o nome do compartilhamento.

## Parou depois de “Consultando log de Segurança”

Se o prompt não voltou, pode continuar processando. A consulta pode examinar
muitos eventos antes de aplicar o filtro de pasta. Diminua a janela para 15
minutos; evite DNS reverso e enriquecimento AD no primeiro diagnóstico.
Silencioso oculta tabelas, não reduz a quantidade de eventos consultados.
Se necessário, interrompa com Ctrl+C e execute novamente com janela menor.

Os registros são mantidos em memória. Agrupar reduz linhas, mas consolida
registros; para preservar evidência detalhada, prefira janelas menores.

## Acesso remoto falhou

Confira permissões do log e conectividade RPC/firewall de gerenciamento remoto
de eventos. O inventário SMB usa CIM, com requisitos adicionais; leitura de
ACL usa UNC/SMB. Sucesso em uma operação não comprova acesso às outras.
Teste localmente no servidor primeiro. Não desative o firewall inteiro.

## CSV vazio, arquivo antigo ou relatório incompleto

Confira avisos de exportação, caminho de saída, data de modificação e se o
resultado pertence à execução atual. Nas versões atuais, zero registros pode
retornar antes da criação de um novo CSV detalhado; um arquivo antigo não prova
sucesso. Use nomes com {data}. Na v8, confira também `.cobertura.csv`, mesmo
quando não houver eventos. No inventário v2, confira erros de ACL/enumeração/SID.

## Permissões amplas e não autorizados

Permissão ampla é indício para revisão, não prova de acesso indevido. O original
usa classificação anterior por nome/trecho; para comparar com regras de negócio,
prefira v8 e caminhos completos. Indeterminado significa consulta insuficiente,
não autorização nem acusação. Associações AD atuais não provam o estado histórico.

## Arquivo EVTX arquivado não aparece

O script consulta Security ativo. Veja as limitações de arquivamento em
[AUDITORIA-WINDOWS.md](AUDITORIA-WINDOWS.md); não há opção de arquivo EVTX nos
parâmetros atuais.
