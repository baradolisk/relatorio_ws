#requires -Version 5.1
# Testes isolados: não consulta serviços Windows nem executa o corpo dos relatórios.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$script:verificacoes = 0

function Assert-Resultado {
    param ([bool]$Condicao, [string]$Descricao)
    if (-not $Condicao) { throw "FALHOU: $Descricao" }
    $script:verificacoes++
}

function Import-FuncoesTeste {
    param ([string]$Arquivo)
    $tokens = $null; $erros = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Arquivo, [ref]$tokens, [ref]$erros)
    if ($erros.Count) { throw "Sintaxe: $($erros[0].Message)" }
    $funcoes = $ast.FindAll({
        param($no)
        $no -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    # Emitir somente declarações de função para importar no escopo do teste.
    return ($funcoes | ForEach-Object { $_.Extent.Text }) -join "`n"
}

foreach ($arquivo in Get-ChildItem -Path $raiz -Filter *.ps1 -Recurse -File) {
    $tokens = $null; $erros = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($arquivo.FullName, [ref]$tokens, [ref]$erros)
    Assert-Resultado ($erros.Count -eq 0) "Sintaxe de $($arquivo.Name)"
}

# Cada conjunto usa escopo próprio para não misturar funções das versões.
& {
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'))
    Assert-Resultado ((ConvertTo-ShareServidor '\\*\z' 'SRV.empresa.local') -eq '\\SRV.empresa.local\z') 'ShareName com servidor curinga'
    Assert-Resultado (Test-FiltroRede '\\SRV\z\RH' '\\SRV.empresa.local\z' 'RH\a.txt' 'SRV.empresa.local' 'SRV') 'UNC curto e FQDN'
    Assert-Resultado (-not (Test-FiltroRede '\\OUTRO\z' '\\SRV\z' 'a.txt' 'SRV' 'SRV')) 'Servidor diferente'
    Assert-Resultado (-not (Test-FiltroRede '\\SRV\z\RH' '\\SRV\z' 'RH-antigo\a.txt' 'SRV' 'SRV')) 'Limite de diretório no comparador UNC'
    Assert-Resultado ((ConvertTo-AccessMask '0x1') -eq 1) 'Máscara hexadecimal'
    Assert-Resultado ((Protect-CsvCell '=1+1') -eq "'=1+1") 'Proteção de fórmula em CSV'
}

& {
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta-v8.ps1'))
    $sidPermitido = 'S-1-5-21-1-2-3-1001'
    $membros = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$membros.Add($sidPermitido)
    $membrosPorGrupo = @{G1=$membros}
    $regrasAutorizacao = @(
        [pscustomobject]@{Pasta='\\SRV\z\RH'; Grupo='G1'},
        [pscustomobject]@{Pasta='\\SRV\z\RH'; Grupo='G2'}
    )
    $registro = [pscustomobject]@{
        Usuario='EMPRESA\joao'; UsuarioSid=$sidPermitido
        Objeto='\\SRV\z\RH\a.txt'; CaminhoLocal=''
    }
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Autorizado') 'SID confirmado em um grupo'
    $registro.UsuarioSid = 'S-1-5-21-4-5-6-1001'
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Indeterminado') 'Outro SID e grupo indisponível'
    $membrosPorGrupo.G2 = $membros
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'NAO AUTORIZADO') 'Mesmo nome não autoriza outro SID'
    $registro.UsuarioSid = ''
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Indeterminado') 'SID ausente'
    $registro.Objeto = '\\SRV\z\RH-antigo\a.txt'
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Sem regra') 'Regra não alcança nome parecido'
    Assert-Resultado ((ConvertTo-CaminhoRegra 'E:/FileServer/RH/') -eq 'E:\FileServer\RH') 'Normalizar caminho completo'
    $rejeitado = $false
    try { $null = ConvertTo-CaminhoRegra 'RH' } catch { $rejeitado = $true }
    Assert-Resultado $rejeitado 'Rejeitar regra por trecho'
    Assert-Resultado ((Get-PastaResumo -Compartilhamento '\\SRV\z' -CaminhoRelativo 'LEIAME') -eq '\\SRV\z') 'Não deduzir tipo pela extensão'
}

& {
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1'))
    Assert-Resultado (Test-SidAmplo 'S-1-1-0') 'Everyone por SID'
    Assert-Resultado (-not (Test-SidAmplo 'S-1-5-21-1-2-3-1001')) 'Usuário específico não é grupo amplo'
    Assert-Resultado (Test-DireitoEscrita 2) 'Direito de escrita'
    Assert-Resultado (-not (Test-DireitoEscrita 1)) 'Leitura não é escrita'
}

Write-Output "PASSOU: $script:verificacoes verificações de sintaxe e funções isoladas com dados simulados."
Write-Output 'Não valida integração Windows/AD/SMB, cobertura real de auditoria ou Windows PowerShell 5.1.'
