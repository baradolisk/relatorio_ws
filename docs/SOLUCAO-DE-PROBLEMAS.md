# Resolver problemas

Execute os exemplos na pasta principal do repositório.

## Script bloqueado

Confira a política e, após verificar a origem do arquivo, remova a marca de download:

```powershell
Get-ExecutionPolicy -List
Unblock-File -LiteralPath .\scripts\acessos\Relatorio-AcessoPasta.ps1
```

Se MachinePolicy e UserPolicy forem Undefined e a empresa permitir, libere scripts locais apenas nesta sessão:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Se uma GPO exigir AllSigned, solicite a assinatura do script com certificado confiável. Desbloquear o download não substitui a assinatura.

## Erro com o nome do usuário

Use Usuario para o nome. UsuarioExato é uma opção sem texto:

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Usuario "usuario.teste" -UsuarioExato -Dias 1
```

Se não encontrar o usuário, retire UsuarioExato e tente `-Usuario "*teste*"`.

## Nenhum resultado

1. Faça um acesso pela rede a partir de outra estação.
2. Consulte um período curto, sem Pasta ou Usuario.
3. Confira [auditoria e tipos de evento](AUDITORIA-WINDOWS.md).

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 5145
    StartTime = (Get-Date).AddMinutes(-15)
} -MaxEvents 5 | Select-Object TimeCreated, Id, Message
```

Sem 5145, confira Detailed File Share. Para 4663, confira também auditoria na pasta (SACL). Leia os erros: acesso negado não significa zero eventos. Confira o servidor e o período; eventos antigos podem ter sido perdidos.

## Caminho local funciona, nome de rede não

Confira os nomes com `Get-SmbShare | Select-Object Name, Path`. Se `z` aponta para `E:\FileServer`, use `\\SERVIDOR\z`.

O original corrigido trata nomes curtos e completos do servidor. Na v8, use o nome mostrado no CSV; para 4663, use caminho local. Nomes alternativos e DFS não são traduzidos automaticamente.

## Demora depois de “Consultando log”

Se o prompt não voltou, a consulta pode continuar ativa. Interrompa com Ctrl+C e tente 15 minutos. Evite ResolverIP e EnriquecerAD no primeiro teste. Silencioso apenas oculta tabelas; não reduz o trabalho.

## Falha remota ou relatório incompleto

- Teste primeiro no servidor local, com acesso ao log de Segurança.
- Log remoto depende de permissões e RPC/firewall; inventário usa CIM e leitura de pastas usa SMB. Não desative o firewall inteiro.
- Confira avisos e o CSV de cobertura da v8 ou do inventário v2.
- Confira a data do CSV: quando não há registros, o detalhado pode não ser criado e um arquivo antigo continuar na pasta.
- Indeterminado significa que faltam dados para concluir a autorização.

## Arquivos arquivados não aparecem

Os relatórios consultam apenas o log ativo. Veja [arquivamento](AUDITORIA-WINDOWS.md#arquivar-ao-atingir-o-limite).
