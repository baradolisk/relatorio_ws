<#
.SYNOPSIS
    Consulta acessos a pastas e exporta relatórios CSV.

.DESCRIPTION
    Execute no Windows com acesso aos dados consultados. Exemplos partem da raiz do repositório.
    5145: verificação SMB; não comprova leitura do conteúdo.
    5140: conexão ao compartilhamento. 4663: direito auditado no objeto; exige SACL.
    4660: exclusão; caminho associado por 4656 ou 4663 DELETE próximo, quando disponíveis.
    Sem registros não significa ausência de acessos. Consulta apenas o log ativo.

.PARAMETER MaxEventos
    Limite por servidor antes dos filtros de pasta/usuário. Zero: sem limite. Resultado pode ser parcial.

.PARAMETER ResolverSids
    Traduz SIDs para nomes. Pode aguardar respostas do domínio; desativado por padrão.

.PARAMETER Menu
    Abre o menu com valores sugeridos e exportação CSV. Omita em tarefas agendadas.

.PARAMETER Pasta
    Nome, trecho ou caminho da pasta. Omita para pesquisar todas.

.PARAMETER Dias
    Dias anteriores a consultar. Padrão: 1. Não combine com Inicio/Fim.

.PARAMETER Inicio
    Data e hora inicial de um período específico.

.PARAMETER Fim
    Data e hora final. Com Inicio, o padrão é até agora.

.PARAMETER EventoId
    Um evento por execução: 5145 (padrão), 5140, 4663 ou 4660 (exclusões).

.PARAMETER Usuario
    Nome ou padrão do usuário. Exemplo: "joao*". Padrão: todos.

.PARAMETER UsuarioExato
    Otimiza a busca pelo nome exato; diferencia maiúsculas/minúsculas. Não recebe texto.

.PARAMETER Computador
    Servidores a consultar. Padrão: computador local.

.PARAMETER IgnorarAtributos
    Descarta eventos que contêm apenas direitos considerados ruído.

.PARAMETER Agrupar
    Reúne eventos semelhantes no mesmo minuto. Use sem esta opção para preservar cada evento.

.PARAMETER Resultado
    Todos (padrão), Exito ou Falha.

.PARAMETER IncluirContasComputador
    Inclui contas com nome terminado em $, ignoradas por padrão.

.PARAMETER CsvSaida
    Arquivo CSV detalhado. Aceita {data} no nome.

.PARAMETER ExcluirUsuarios
    Contas a ignorar. Exemplo: "svc-*","backup".

.PARAMETER IncluirCompartilhamentosEspeciais
    Inclui compartilhamentos como C$, E$ e ADMIN$.

.PARAMETER ListarCompartilhamentos
    Lista os compartilhamentos dos servidores informados.

.PARAMETER ListaAutorizados
    CSV Pasta;Grupo. Requer ActiveDirectory/RSAT. Comparação auxiliar por nome e trecho.

.PARAMETER EnriquecerAD
    Acrescenta departamento e cargo. Requer ActiveDirectory/RSAT.

.PARAMETER ResolverIP
    Busca o nome DNS da estação pelo IP. Pode tornar a consulta lenta.

.PARAMETER CsvResumo
    Arquivo CSV de resumo por usuário e pasta. Aceita {data}.

.PARAMETER Silencioso
    Oculta tabelas; avisos e mensagens de execução continuam.

.PARAMETER GridView
    Abre os resultados em janela. Requer Out-GridView e interface gráfica.

.PARAMETER PassThru
    Retorna os registros como objetos PowerShell.

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Pasta "RH" -Dias 1

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -CsvSaida "C:\Relatorios\acessos-{data}.csv"

.NOTES
    Veja README.md, docs/PARAMETROS.md e docs/EXEMPLOS.md para mais opções.
    PowerShell 5.1 e Windows Server real ainda precisam de validação no seu ambiente.
    A classificação por grupos usa nome e trecho; não comprova autorização efetiva.
    Caminho de rede usa o nome do compartilhamento: Get-SmbShare mostra Name e Path.
#>

[CmdletBinding(DefaultParameterSetName = 'Dias')]
param (

    [string]$Pasta = '',

    [Parameter(ParameterSetName = 'Dias')]
    [ValidateRange(1, 3650)]
    [int]$Dias = 1,

    [Parameter(Mandatory = $true, ParameterSetName = 'Periodo')]
    [datetime]$Inicio,

    [Parameter(ParameterSetName = 'Periodo')]
    [datetime]$Fim,

    [ValidateSet(4663, 5145, 5140, 4660)]
    [int]$EventoId = 5145,

    [ValidateNotNullOrEmpty()]
    [string]$Usuario = '*',

    [switch]$UsuarioExato,

    [ValidateNotNullOrEmpty()]
    [string[]]$Computador = @($env:COMPUTERNAME),

    [switch]$IgnorarAtributos,

    [switch]$Agrupar,

    [ValidateSet('Todos', 'Exito', 'Falha')]
    [string]$Resultado = 'Todos',

    [switch]$IncluirContasComputador,

    [string]$CsvSaida,

    [string[]]$ExcluirUsuarios = @(),

    [switch]$IncluirCompartilhamentosEspeciais,

    [switch]$ListarCompartilhamentos,

    [string]$ListaAutorizados,

    [switch]$EnriquecerAD,

    [switch]$ResolverIP,

    [string]$CsvResumo,

    [switch]$Silencioso,

    [switch]$GridView,

    [switch]$PassThru,

    [switch]$Menu,

    [ValidateRange(0, 2147483647)]
    [int]$MaxEventos = 0,

    [switch]$ResolverSids
)

# ATENÇÃO: nomes de variáveis no PowerShell não diferenciam maiúsculas de
# minúsculas. O parâmetro $Resultado (string com ValidateSet) NÃO pode ser
# reutilizado para a lista de registros; por isso a lista se chama $registros.


# ============================================================
# Funções auxiliares
# ============================================================

function ConvertTo-AccessMask {

    param (
        [string]$Mask
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return $null
    }

    $valor = $Mask.Trim()

    # Remove prefixo 0x caso exista
    if ($valor -match '^0x') {
        $valor = $valor.Substring(2)
    }

    try {
        return [Convert]::ToInt64($valor, 16)
    }
    catch {
        return $null
    }
}


function Get-TipoAcesso {

    param (
        [string]$Mask
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return ''
    }

    $m = ConvertTo-AccessMask $Mask

    if ($null -eq $m) {
        return $Mask
    }

    $tipos = @()

    # Direitos específicos de arquivos e diretórios
    if ($m -band 0x1)      { $tipos += 'Leitura/Listagem' }
    if ($m -band 0x2)      { $tipos += 'Gravação/Criação' }
    if ($m -band 0x4)      { $tipos += 'Anexar dados/Criar subpasta' }
    if ($m -band 0x8)      { $tipos += 'Ler atributos estendidos' }
    if ($m -band 0x10)     { $tipos += 'Gravar atributos estendidos' }
    if ($m -band 0x20)     { $tipos += 'Executar/Atravessar pasta' }
    if ($m -band 0x40)     { $tipos += 'Excluir arquivo/subpasta filho' }
    if ($m -band 0x80)     { $tipos += 'Ler atributos' }
    if ($m -band 0x100)    { $tipos += 'Gravar atributos' }

    # Direitos padrão do Windows
    if ($m -band 0x10000)  { $tipos += 'Excluir' }
    if ($m -band 0x20000)  { $tipos += 'Ler permissões' }
    if ($m -band 0x40000)  { $tipos += 'Alterar permissões' }
    if ($m -band 0x80000)  { $tipos += 'Alterar proprietário' }
    if ($m -band 0x100000) { $tipos += 'Sincronizar' }

    if ($tipos.Count -eq 0) {
        return "Outro ($Mask)"
    }

    return ($tipos -join ', ')
}


# Retorna $true somente quando TODOS os bits da máscara são "ruído" conhecido
# (ler atributos estendidos, atravessar pasta, ler atributos, ler permissões,
# sincronizar). Qualquer bit desconhecido faz o evento ser MANTIDO: em auditoria
# é melhor mostrar demais do que esconder algo em silêncio.
function Test-AcessoRuido {

    param (
        [string]$Mask
    )

    $m = ConvertTo-AccessMask $Mask

    if ($null -eq $m) {
        return $false
    }

    $ruido = 0x8 -bor 0x20 -bor 0x80 -bor 0x20000 -bor 0x100000

    return (($m -band (-bnot $ruido)) -eq 0)
}


function ConvertTo-XPathTime {

    param (
        [datetime]$Data
    )

    return $Data.ToUniversalTime().ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}


# Evita que textos iniciados por = + - @ (ou tab/CR) sejam executados como
# fórmula ao abrir o CSV no Excel.
function Protect-CsvCell {

    param (
        [object]$Valor
    )

    $texto = [string]$Valor

    if ($texto -match '^[=+\-@\t\r]') {
        return "'" + $texto
    }

    return $texto
}


# Retorna $true quando o nome informado é o próprio computador (leitura local,
# sem RPC).
function Test-ServidorLocal {

    param (
        [string]$Nome
    )

    $locais = @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME)

    if ($env:USERDNSDOMAIN) {
        $locais += ($env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN)
    }

    return ($locais -contains $Nome)
}


# Normaliza IPv4 mapeado em IPv6 (::ffff:10.0.0.5 -> 10.0.0.5).
function ConvertTo-IpNormalizado {

    param (
        [string]$Ip
    )

    if ([string]::IsNullOrWhiteSpace($Ip)) {
        return ''
    }

    $valor = $Ip.Trim()

    if ($valor -match '^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') {
        return $Matches[1]
    }

    return $valor
}


# Traduz um SID (ou apelido SDDL, como WD/AU/BU) para nome, com cache.
function Resolve-SidConta {

    param (
        [string]$Sid
    )

    if ($script:cacheSid.ContainsKey($Sid)) {
        return $script:cacheSid[$Sid]
    }

    $nome = $Sid

    if ($ResolverSids -and $Sid -like 'S-1-*') {

        try {
            $nome = ([System.Security.Principal.SecurityIdentifier]::new($Sid)).Translate(
                [System.Security.Principal.NTAccount]).Value
        }
        catch {
            $nome = $Sid
        }
    }
    elseif ($script:aliasesSddl.ContainsKey($Sid)) {

        $nome = $script:aliasesSddl[$Sid]
    }

    $script:cacheSid[$Sid] = $nome

    return $nome
}


# Lê o AccessReason do evento 5145 (ACEs em SDDL) e devolve quem liberou o
# acesso. "Ampla" = liberação por Everyone, Authenticated Users, Domain Users,
# BUILTIN\Users ou NETWORK (detecção por SID, independente do idioma).
function Get-ConcessaoAcesso {

    param (
        [string]$AccessReason
    )

    $saida = @{ Contas = ''; Ampla = $false }

    if ([string]::IsNullOrWhiteSpace($AccessReason)) {
        return $saida
    }

    if ($script:cacheConcessao.ContainsKey($AccessReason)) { return $script:cacheConcessao[$AccessReason] }

    $contas = New-Object 'System.Collections.Generic.List[string]'

    $regexAce = [regex]'\((?<tipo>[A-Za-z]+);(?<flags>[A-Za-z]*);(?<dir>[0-9A-Za-z]*);[^;)]*;[^;)]*;(?<sid>[^;)]+)\)'

    foreach ($m in $regexAce.Matches($AccessReason)) {

        # Só interessam ACEs de permissão (A); negações (D) não "liberam"
        if ($m.Groups['tipo'].Value -ne 'A') {
            continue
        }

        $sid = $m.Groups['sid'].Value
        $conta = Resolve-SidConta $sid

        if (-not $contas.Contains($conta)) {
            $contas.Add($conta)
        }

        if (
            ($sid -in @('WD', 'AU', 'BU', 'DU', 'NU')) -or
            ($sid -in @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-2')) -or
            ($sid -match '^S-1-5-21-\d+-\d+-\d+-513$')
        ) {
            $saida.Ampla = $true
        }
    }

    $saida.Contas = ($contas -join '; ')
    if ($script:cacheConcessao.Count -lt 5000) { $script:cacheConcessao[$AccessReason] = $saida }

    return $saida
}


# Pasta usada nos resumos: compartilhamento + subpasta de 1º nível (5145/5140)
# ou os 3 primeiros níveis do caminho local (4663).
function Get-PastaResumo {

    param (
        [string]$Compartilhamento,
        [string]$CaminhoRelativo,
        [string]$CaminhoLocal
    )

    if (-not [string]::IsNullOrWhiteSpace($Compartilhamento)) {

        $base = $Compartilhamento.TrimEnd('\')

        $seg = @(([string]$CaminhoRelativo -split '\\') | Where-Object { $_ -ne '' })

        # Com 1 só nível, um nome com ponto é tratado como arquivo na raiz
        if ($seg.Count -ge 2 -or ($seg.Count -eq 1 -and $seg[0] -notmatch '\.')) {
            return $base + '\' + $seg[0]
        }

        return $base
    }

    if (-not [string]::IsNullOrWhiteSpace($CaminhoLocal)) {

        $seg = @($CaminhoLocal -split '\\' | Where-Object { $_ -ne '' })

        return (($seg | Select-Object -First 3) -join '\')
    }

    return ''
}


# Compara o acesso com a lista de autorizados (regra mais específica vence).
function Get-StatusAutorizacao {

    param (
        $Registro
    )

    $sam = ([string]$Registro.Usuario) -replace '^.*\\', ''

    $melhor = 0
    $grupos = @()

    foreach ($regra in $regrasAutorizacao) {

        $combina =
            (-not [string]::IsNullOrWhiteSpace($Registro.Objeto) -and $Registro.Objeto -like $regra.Padrao) -or
            (-not [string]::IsNullOrWhiteSpace($Registro.CaminhoLocal) -and $Registro.CaminhoLocal -like $regra.Padrao)

        if (-not $combina) {
            continue
        }

        $tamanho = $regra.Pasta.Length

        if ($tamanho -gt $melhor) {
            $melhor = $tamanho
            $grupos = @($regra.Grupo)
        }
        elseif ($tamanho -eq $melhor) {
            $grupos += $regra.Grupo
        }
    }

    if ($melhor -eq 0) {
        return 'Sem regra'
    }

    $lidos = 0

    foreach ($grupo in $grupos) {

        if ($membrosPorGrupo.ContainsKey($grupo)) {

            $lidos++

            if ($membrosPorGrupo[$grupo].Contains($sam)) {
                return 'Autorizado'
            }
        }
    }

    if ($lidos -eq 0) {
        return 'Indeterminado'
    }

    return 'NAO AUTORIZADO'
}


# Informa tamanho do log de Segurança, evento mais antigo e (no servidor
# local) a configuração da auditoria. Nunca interrompe o relatório.
function Test-LogSeguranca {

    param (
        [string]$Servidor,
        [datetime]$Inicio
    )

    $local = Test-ServidorLocal $Servidor

    $cn = @{}

    if (-not $local) {
        $cn.ComputerName = $Servidor
    }

    try {

        $log = Get-WinEvent -ListLog 'Security' -ErrorAction Stop @cn
        $mb = [math]::Round($log.MaximumSizeInBytes / 1MB)

        $primeiro = Get-WinEvent -LogName 'Security' -MaxEvents 1 -Oldest -ErrorAction Stop @cn

        Write-Host ("  Log de Segurança: máximo de {0} MB; evento mais antigo em {1}" -f
            $mb, $primeiro.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')) -ForegroundColor DarkGray

        if ($primeiro.TimeCreated -gt $Inicio) {

            Write-Warning (
                "[$Servidor] O log de Segurança começa em " +
                $primeiro.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss') +
                ", depois do início do período: eventos mais antigos já foram sobrescritos. " +
                "Aumente o tamanho do log (GPO) ou encaminhe/exporte os eventos."
            )
        }
        elseif ($EventoId -ne 4663 -and $mb -lt 1024) {

            Write-Host "  Dica: o evento $EventoId gera muito volume; considere aumentar o log de Segurança (hoje $mb MB)." -ForegroundColor DarkYellow
        }
    }
    catch {

        Write-Verbose "[$Servidor] Não foi possível verificar o log de Segurança: $($_.Exception.Message)"
    }

    if ($local) {

        # GUIDs das subcategorias (independem do idioma do Windows)
        switch ($EventoId) {
            4663 { $guid = '{0CCE921D-69AE-11D9-BED3-505054503030}' }
            4660 { $guid = '{0CCE921D-69AE-11D9-BED3-505054503030}' }
            5145 { $guid = '{0CCE9244-69AE-11D9-BED3-505054503030}' }
            5140 { $guid = '{0CCE9224-69AE-11D9-BED3-505054503030}' }
        }

        try {

            $linha = & auditpol.exe /get "/subcategory:$guid" /r 2>$null |
                Where-Object { $_ -match '\{0CCE' } |
                Select-Object -First 1

            if ($linha) {

                $config = ($linha -split ',')[4]

                Write-Host "  Auditoria da subcategoria do evento ${EventoId}: $config" -ForegroundColor DarkGray
            }
        }
        catch {

            Write-Verbose "Não foi possível consultar o auditpol: $($_.Exception.Message)"
        }
    }
}


# Lista os compartilhamentos não administrativos de um servidor.
function Get-CompartilhamentosServidor {

    param (
        [string]$Servidor
    )

    try {

        if (Test-ServidorLocal $Servidor) {

            $shares = Get-SmbShare -Special:$false -ErrorAction Stop
        }
        else {

            $cim = New-CimSession -ComputerName $Servidor -ErrorAction Stop

            try {
                $shares = Get-SmbShare -CimSession $cim -Special:$false -ErrorAction Stop
            }
            finally {
                Remove-CimSession $cim -ErrorAction SilentlyContinue
            }
        }

        return @($shares | Select-Object Name, Path, Description)
    }
    catch {

        Write-Warning "[$Servidor] Não foi possível listar os compartilhamentos: $($_.Exception.Message)"

        return @()
    }
}


# O Windows registra ShareName como \\*\Share, sem o nome real do servidor.
function ConvertTo-ShareServidor {
    param ([string]$Share, [string]$Servidor)
    if ($Share.StartsWith('\\*\') -and $Servidor) {
        return '\\' + $Servidor + $Share.Substring(3)
    }
    return $Share
}

function Test-FiltroRede {
    param ([string]$Filtro, [string]$Share, [string]$Relativo,
           [string]$ServidorEvento, [string]$ServidorConsulta)
    if ($Filtro -notmatch '^\\\\([^\\]+)\\(.+)$') { return $false }
    $hostFiltro = $Matches[1]
    $restante = $Matches[2].TrimEnd('\')
    $servidorValido = $false
    foreach ($nome in @($ServidorEvento, $ServidorConsulta)) {
        if (-not $nome) { continue }
        if ($hostFiltro -ieq $nome -or
            (($hostFiltro -notlike '*.*' -or $nome -notlike '*.*') -and
             ($hostFiltro.Split('.')[0] -ieq $nome.Split('.')[0]))) {
            $servidorValido = $true
        }
    }
    if (-not $servidorValido -or $Share -notmatch '^\\\\[^\\]+\\(.+)$') { return $false }
    $alvo = $Matches[1].TrimEnd('\')
    if ($Relativo) { $alvo += '\' + $Relativo.TrimStart('\') }
    return ($alvo -ieq $restante -or $alvo.StartsWith($restante + '\', [StringComparison]::OrdinalIgnoreCase))
}

# Classificação conservadora: máscara de gravação não distingue criação de edição.
function Get-AcaoEvento {
    param ([int]$Id, [string]$Mask, [string]$Resultado, [bool]$CaminhoCorrelacionado = $false, [int]$EventoCorrelacao = 4656)
    if ($Id -eq 4660) {
        if ($Resultado -eq 'Falha') { return @{Acao='Exclusão não confirmada';Evidencia='4660 com indicação de falha; não confirmar exclusão.'} }
        if ($CaminhoCorrelacionado) {
            if ($EventoCorrelacao -eq 4663) {
                return @{Acao='Exclusão confirmada'; Evidencia='4660 confirma exclusão; caminho associado ao 4663 com DELETE nos 30 segundos anteriores, com mesmo servidor, SID, sessão, processo e handle. Sem abertura 4656 correlacionada.'}
            }
            return @{Acao='Exclusão confirmada'; Evidencia='4660 confirma exclusão; caminho associado ao 4656 no mesmo ciclo de handle.'}
        }
        return @{Acao='Exclusão registrada; caminho não identificado'; Evidencia='4660 confirma exclusão, mas não traz nome. Sem abertura 4656 válida ou 4663 DELETE próximo para associar caminho.'}
    }
    if ($Id -eq 5140) {
        return @{Acao='Conexão ao compartilhamento'; Evidencia='5140 não informa a operação em cada arquivo.'}
    }
    $m = ConvertTo-AccessMask $Mask
    if ($null -eq $m) { return @{Acao='Não identificada';Evidencia="Evento $Id com máscara ausente ou inválida."} }
    $acoes = New-Object 'System.Collections.Generic.List[string]'
    if ($m -band 0x2) { $acoes.Add('Gravação ou criação') }
    if ($m -band 0x4) { $acoes.Add('Anexação ou criação de subpasta') }
    if ($m -band 0x10000) { $acoes.Add('Direito de exclusão') }
    if ($m -band 0x40) { $acoes.Add('Direito de excluir filhos') }
    if ($m -band 0x40000) { $acoes.Add('Alteração de permissões') }
    if ($m -band 0x80000) { $acoes.Add('Alteração de proprietário') }
    if ($m -band 0x1) { $acoes.Add('Leitura ou listagem') }
    if ($m -band (0x10 -bor 0x100)) { $acoes.Add('Gravação de atributos') }
    if ($m -band 0x20) { $acoes.Add('Execução ou travessia') }
    if ($acoes.Count -eq 0 -and $m -ne 0 -and ($m -band (-bnot (0x8 -bor 0x80 -bor 0x20000 -bor 0x100000))) -eq 0) {
        $acoes.Add('Consulta de metadados')
    }
    if ($acoes.Count -eq 0) { $acoes.Add('Outros direitos; ver AccessMask') }
    if ($m -band (-bnot 0x1F01FF)) { $acoes.Add('Bits adicionais; ver AccessMask') }
    $acao = $acoes -join '; '
    $evidencia = "4663: direitos utilizados no objeto; máscara $Mask. Gravação não distingue novo de editado; exclusão requer 4660."
    if ($Id -eq 5145) {
        $acao = 'Verificação SMB: ' + $acao
        $evidencia = "5145: direitos verificados, não comprova operação nem leitura do conteúdo; máscara $Mask."
    }
    if ($Resultado -eq 'Falha') { $acao = 'Falha: ' + $acao }
    return @{Acao=$acao; Evidencia=$evidencia}
}

function Get-ChaveHandle {
    param ($Evento, [hashtable]$Dados)
    $partes = @(([string]$Evento.MachineName).ToLowerInvariant(), [string]$Dados.SubjectUserSid)
    if (-not $partes[0] -or $partes[1] -notmatch '^S-1-') { return '' }
    foreach ($nome in @('SubjectLogonId','ProcessId','HandleId')) {
        $valor = [string]$Dados[$nome]
        if (-not $valor) { return '' }
        try {
            if ($valor -match '^0x') { $numero = [Convert]::ToUInt64($valor.Substring(2),16) }
            else { $numero = [Convert]::ToUInt64($valor,10) }
            if ($numero -eq 0) { return '' }
            $partes += $numero.ToString([Globalization.CultureInfo]::InvariantCulture)
        } catch { return '' }
    }
    return $partes -join '|'
}

function Update-CorrelacaoExclusao {
    param ($Evento)
    $id = [int]$Evento.Id
    if ($id -in @(4608,4609,1102)) { $script:handlesExclusao.Clear(); return $null }
    $xml = [xml]$Evento.ToXml()
    $dados = @{}
    foreach ($item in $xml.Event.EventData.Data) { if ($item.Name) { $dados[[string]$item.Name] = [string]$item.'#text' } }
    $chave = Get-ChaveHandle $Evento $dados
    $caminho = ''; $abertura = ''; $acesso = ''; $origem = 0; $registroOrigem = ''
    $ordemValida = $script:ultimoRecordCorrelacao -lt [long]$Evento.RecordId
    if (-not $ordemValida) { $script:handlesExclusao.Clear() }
    $script:ultimoRecordCorrelacao = [long]$Evento.RecordId
    $script:passosCorrelacao++
    if (($script:passosCorrelacao % 256) -eq 0) {
        foreach ($k in @($script:handlesExclusao.Keys)) {
            $limite = 300
            if ($script:handlesExclusao[$k].Origem -eq 4663) { $limite = 30 }
            if (($Evento.TimeCreated - $script:handlesExclusao[$k].Inicio).TotalSeconds -gt $limite) { $script:handlesExclusao.Remove($k) }
        }
    }
    if ($chave) {
        if ($id -eq 4656) {
            $script:handlesExclusao.Remove($chave)
            if ($ordemValida -and -not ($Evento.Keywords -band 0x10000000000000) -and $dados.ObjectName -and $dados.ObjectType -eq 'File') {
                if ($script:handlesExclusao.Count -ge 10000) {
                    $script:handlesExclusao.Clear(); $script:descartesCorrelacao++
                }
                $script:handlesExclusao[$chave] = @{Caminho=$dados.ObjectName;Inicio=$Evento.TimeCreated;RecordId=$Evento.RecordId;Origem=4656;RecordIdAcesso=''}
            }
        }
        elseif ($id -eq 4658) { $script:handlesExclusao.Remove($chave) }
        else {
            $bloquearAlternativa = -not $ordemValida
            if ($script:handlesExclusao.ContainsKey($chave)) {
                $estado = $script:handlesExclusao[$chave]
                $segundos = ($Evento.TimeCreated - $estado.Inicio).TotalSeconds
                $limite = 300
                if ($estado.Origem -eq 4663) { $limite = 30 }
                $conflito = $id -eq 4663 -and $dados.ObjectName -and $dados.ObjectName -ine $estado.Caminho
                if ($segundos -lt 0 -or $segundos -gt $limite -or $conflito) {
                    $script:handlesExclusao.Remove($chave)
                    if ($segundos -lt 0 -or $conflito) { $bloquearAlternativa = $true }
                }
            }
            $mask = ConvertTo-AccessMask ([string]$dados.AccessMask)
            $deleteValido = $id -eq 4663 -and $null -ne $mask -and ($mask -band 0x10000) -and
                ($Evento.Keywords -band 0x20000000000000) -and -not ($Evento.Keywords -band 0x10000000000000) -and
                $dados.ObjectType -eq 'File' -and -not [string]::IsNullOrWhiteSpace($dados.ObjectName)
            if ($deleteValido -and -not $bloquearAlternativa) {
                if (-not $script:handlesExclusao.ContainsKey($chave)) {
                    if ($script:handlesExclusao.Count -ge 10000) {
                        $script:handlesExclusao.Clear(); $script:descartesCorrelacao++
                    }
                    $script:handlesExclusao[$chave] = @{Caminho=$dados.ObjectName;Inicio=$Evento.TimeCreated;RecordId=$Evento.RecordId;Origem=4663;RecordIdAcesso=$Evento.RecordId}
                }
                elseif ($script:handlesExclusao[$chave].Origem -eq 4663) {
                    # Usar o DELETE mais recente no mesmo objeto, sem alargar a janela.
                    $script:handlesExclusao[$chave].Inicio = $Evento.TimeCreated
                    $script:handlesExclusao[$chave].RecordId = $Evento.RecordId
                    $script:handlesExclusao[$chave].RecordIdAcesso = $Evento.RecordId
                }
                else { $script:handlesExclusao[$chave].RecordIdAcesso = $Evento.RecordId }
            }
            if ($id -eq 4660 -and $script:handlesExclusao.ContainsKey($chave)) {
                $estado = $script:handlesExclusao[$chave]
                $caminho = $estado.Caminho
                $origem = [int]$estado.Origem
                $registroOrigem = [string]$estado.RecordId
                $acesso = [string]$estado.RecordIdAcesso
                if ($origem -eq 4656) { $abertura = $registroOrigem }
            }
        }
        if ($id -eq 4660) { $script:handlesExclusao.Remove($chave) }
    }
    if ($id -eq 4660) {
        if (-not $caminho) { $script:exclusoesSemCaminho++ }
        return @{Caminho=$caminho;RecordIdAbertura=$abertura;RecordIdAcesso=$acesso;EventoCorrelacao=$origem;RecordIdCorrelacao=$registroOrigem;Dados=$dados}
    }
    return $null
}

# Converte um evento do log em um registro de acesso.
# Retorna $null quando o evento é filtrado ou não pôde ser processado.
function Convert-EventoAcesso {

    param (
        [Parameter(Mandatory = $true)]
        $Evento,
        [hashtable]$Correlacao
    )

    $script:totalLidos++

    try {

        $xml = $null
        $dado = @{}
        if ($Correlacao) { $dado = $Correlacao.Dados }
        else { $xml = [xml]$Evento.ToXml() }

        foreach ($d in $(if ($xml) { $xml.Event.EventData.Data })) {

            if ($null -ne $d.Name) {
                $dado[$d.Name] = $d.'#text'
            }
        }


        # Valores padrão
        $objeto = ''
        $caminhoLocal = ''
        $ip = ''
        $porta = ''
        $acesso = ''
        $processo = ''
        $processId = ''
        $handleId = ''
        $compartilhamento = ''
        $caminhoRelativo = ''


        switch ($EventoId) {

            4660 {
                if ($Correlacao) { $objeto = [string]$Correlacao.Caminho; $caminhoLocal = $objeto }
                $acesso = 'Exclusão registrada (4660)'
                $processo = [string]$dado['ProcessName']
                $processId = [string]$dado['ProcessId']
                $handleId = [string]$dado['HandleId']
            }

            # Evento 4663 - acesso efetivo a arquivo/pasta
            4663 {

                $objeto = [string]$dado['ObjectName']
                $caminhoLocal = $objeto
                $acesso = Get-TipoAcesso $dado['AccessMask']
                $processo = [string]$dado['ProcessName']
                $processId = [string]$dado['ProcessId']
                $handleId = [string]$dado['HandleId']
            }

            # Evento 5145 - acesso detalhado via compartilhamento SMB
            5145 {

                $shareName = ConvertTo-ShareServidor ([string]$dado['ShareName']) ([string]$Evento.MachineName)
                $relativeTarget = [string]$dado['RelativeTargetName']
                $compartilhamento = $shareName
                $caminhoRelativo = $relativeTarget

                # ShareLocalPath vem como \??\D:\Dados\Financeiro
                $raiz = ([string]$dado['ShareLocalPath'] -replace '^\\\?\?\\', '').TrimEnd('\')

                if (-not [string]::IsNullOrWhiteSpace($relativeTarget)) {

                    $objeto = $shareName.TrimEnd('\') + '\' + $relativeTarget.TrimStart('\')

                    if (-not [string]::IsNullOrWhiteSpace($raiz)) {
                        $caminhoLocal = $raiz + '\' + $relativeTarget.TrimStart('\')
                    }
                }
                else {

                    $objeto = $shareName
                    $caminhoLocal = $raiz
                }

                $ip = ConvertTo-IpNormalizado ([string]$dado['IpAddress'])
                $porta = [string]$dado['IpPort']
                $acesso = Get-TipoAcesso $dado['AccessMask']
            }

            # Evento 5140 - conexão ao compartilhamento
            5140 {

                $objeto = ConvertTo-ShareServidor ([string]$dado['ShareName']) ([string]$Evento.MachineName)
                $compartilhamento = $objeto
                $caminhoLocal = ([string]$dado['ShareLocalPath'] -replace '^\\\?\?\\', '').TrimEnd('\')
                $ip = ConvertTo-IpNormalizado ([string]$dado['IpAddress'])
                $porta = [string]$dado['IpPort']
                $acesso = 'Conexão ao compartilhamento'
            }
        }


        # Usuário
        $user = [string]$dado['SubjectUserName']
        $domain = [string]$dado['SubjectDomainName']
        $logonId = [string]$dado['SubjectLogonId']

        # Ignora eventos sem usuário
        if ([string]::IsNullOrWhiteSpace($user)) {
            return $null
        }

        # Ignora contas de computador, salvo quando solicitado explicitamente
        if (-not $IncluirContasComputador -and $user -like '*$') {
            return $null
        }

        # Ignora compartilhamentos administrativos (IPC$, ADMIN$, C$...), que
        # geram muito ruído nos eventos 5145/5140
        if (
            -not $IncluirCompartilhamentosEspeciais -and
            $EventoId -ne 4663 -and
            $compartilhamento -match '\\(IPC\$|ADMIN\$|print\$|[A-Za-z]\$)$'
        ) {
            $script:ignoradosEspeciais++
            return $null
        }

        # Contas excluídas explicitamente (-ExcluirUsuarios)
        if ($ExcluirUsuarios.Count -gt 0) {

            $usuarioDominio = $user

            if (-not [string]::IsNullOrWhiteSpace($domain)) {
                $usuarioDominio = "$domain\$user"
            }

            foreach ($padraoExcluir in $ExcluirUsuarios) {

                if ($user -like $padraoExcluir -or $usuarioDominio -like $padraoExcluir) {
                    $script:ignoradosExcluidos++
                    return $null
                }
            }
        }

        # Filtro de usuário (com curingas). Se o filtro contiver "\", compara
        # com DOMINIO\usuario; caso contrário, só com o nome do usuário.
        $nomeParaFiltro = $user

        if ($Usuario -match '\\' -and -not [string]::IsNullOrWhiteSpace($domain)) {
            $nomeParaFiltro = "$domain\$user"
        }

        if ($nomeParaFiltro -notlike $Usuario) {
            return $null
        }

        # Filtro de pasta/arquivo: caminho de rede OU caminho local completo.
        # O nome do processo (4663) não participa do filtro.
        $correspondeObjeto =
            -not [string]::IsNullOrWhiteSpace($objeto) -and
            $objeto -like $padraoPasta

        $correspondeLocal =
            -not [string]::IsNullOrWhiteSpace($caminhoLocal) -and
            $caminhoLocal -like $padraoPasta

        # UNC considera servidor curto/FQDN e o servidor consultado (alias explícito).
        $correspondeRede = Test-FiltroRede -Filtro $Pasta -Share $compartilhamento `
            -Relativo $caminhoRelativo -ServidorEvento $Evento.MachineName -ServidorConsulta $servidor
        # 4663 contém apenas ObjectName local: a tradução depende do inventário SMB.
        $correspondeTraducao = $false
        if ($EventoId -in @(4663,4660) -and $pastaLocalTraduzida) {
            $correspondeTraducao = $caminhoLocal -ieq $pastaLocalTraduzida -or
                $caminhoLocal.StartsWith($pastaLocalTraduzida + '\', [StringComparison]::OrdinalIgnoreCase)
        }
        $exclusaoSemFiltro = $EventoId -eq 4660 -and [string]::IsNullOrWhiteSpace($Pasta)
        if (-not $exclusaoSemFiltro -and -not $correspondeObjeto -and -not $correspondeLocal -and -not $correspondeRede -and -not $correspondeTraducao) {
            return $null
        }

        # Descarta acessos que são só "ruído" (opcional)
        if ($IgnorarAtributos -and $EventoId -notin @(5140,4660) -and (Test-AcessoRuido $dado['AccessMask'])) {
            $script:ignoradosRuido++
            return $null
        }

        # Êxito ou Falha (palavras-chave de auditoria do evento)
        $resultadoAcesso = 'Êxito'

        if ($Evento.Keywords -band 0x10000000000000) {
            $resultadoAcesso = 'Falha'
        }

        # Filtro por resultado (também aplicado na consulta XPath; mantido
        # aqui como garantia)
        if ($Resultado -eq 'Exito' -and $resultadoAcesso -ne 'Êxito') {
            return $null
        }

        if ($Resultado -eq 'Falha' -and $resultadoAcesso -ne 'Falha') {
            return $null
        }

        # domínio\usuário
        if ([string]::IsNullOrWhiteSpace($domain)) {
            $usuarioCompleto = $user
        }
        else {
            $usuarioCompleto = "$domain\$user"
        }

        # AccessList vem com códigos (%%4416...) separados por tabs/quebras de
        # linha; normaliza os espaços para não bagunçar o CSV.
        $listaAcesso = ([string]$dado['AccessList'] -replace '\s+', ' ').Trim()

        # AccessReason (5145): informa qual ACE liberou o acesso. Resolve os
        # SIDs para nomes e sinaliza liberação por grupo amplo.
        $razaoAcesso = ([string]$dado['AccessReason'] -replace '\s+', ' ').Trim()
        $concedidoPor = ''
        $permissaoAmpla = ''

        if ($EventoId -eq 5145 -and -not [string]::IsNullOrWhiteSpace($razaoAcesso)) {

            $concessao = Get-ConcessaoAcesso $razaoAcesso
            $concedidoPor = $concessao.Contas

            if ($concessao.Ampla) {
                $permissaoAmpla = 'Sim'
            }
            else {
                $permissaoAmpla = 'Nao'
            }
        }

        $pastaResumo = Get-PastaResumo `
            -Compartilhamento $compartilhamento `
            -CaminhoRelativo $caminhoRelativo `
            -CaminhoLocal $caminhoLocal


        $origemCorrelacao = 0; $registroCorrelacao = ''; $registroAcesso = ''
        if ($Correlacao) {
            $origemCorrelacao = [int]$Correlacao.EventoCorrelacao
            $registroCorrelacao = [string]$Correlacao.RecordIdCorrelacao
            $registroAcesso = [string]$Correlacao.RecordIdAcesso
        }
        $classificacao = Get-AcaoEvento -EventoCorrelacao $origemCorrelacao -Id $EventoId -Mask ([string]$dado['AccessMask']) -Resultado $resultadoAcesso -CaminhoCorrelacionado ([bool]($Correlacao -and $Correlacao.Caminho))
        $idAbertura = ''
        if ($Correlacao) { $idAbertura = [string]$Correlacao.RecordIdAbertura }
        return [PSCustomObject]@{

            DataHora         = $Evento.TimeCreated
            PrimeiroAcesso   = $Evento.TimeCreated
            UltimoAcesso     = $Evento.TimeCreated
            Servidor         = $Evento.MachineName
            RecordId         = $Evento.RecordId
            Usuario          = $usuarioCompleto
            Resultado        = $resultadoAcesso
            IP               = $ip
            Porta            = $porta
            Acesso           = $acesso
            AccessList       = $listaAcesso
            AccessMask       = [string]$dado['AccessMask']
            Objeto           = $objeto
            Compartilhamento = $compartilhamento
            CaminhoRelativo  = $caminhoRelativo
            CaminhoLocal     = $caminhoLocal
            Processo         = $processo
            ProcessId        = $processId
            HandleId         = $handleId
            LogonId          = $logonId
            EventoId         = $Evento.Id
            Ocorrencias      = 1
            UsuarioSid       = [string]$dado['SubjectUserSid']
            TipoObjeto       = [string]$dado['ObjectType']
            AccessReason     = $razaoAcesso
            ConcedidoPor     = $concedidoPor
            PermissaoAmpla   = $permissaoAmpla
            PastaResumo      = $pastaResumo
            Estacao          = ''
            Departamento     = ''
            Cargo            = ''
            Autorizacao      = ''
            Acao             = $classificacao.Acao
            Evidencia        = $classificacao.Evidencia
            RecordIdAbertura  = $idAbertura
            EventoCorrelacao  = $origemCorrelacao
            RecordIdCorrelacao = $registroCorrelacao
            RecordIdAcesso    = $registroAcesso
        }

    }
    catch {

        $script:falhasParse++

        Write-Verbose (
            "Erro ao processar evento RecordId " +
            "$($Evento.RecordId): $($_.Exception.Message)"
        )

        return $null
    }
}


# Menu opcional; executa este mesmo arquivo com os parâmetros escolhidos.
function Show-MenuRelatorioAcesso {
    param ([string]$ScriptRelatorio, [hashtable]$ParametrosIniciais = @{})
    $ptBR = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')

    # A leitura real exige Windows; o menu pode ser inspecionado sem consultar dados.
    if ($env:OS -eq 'Windows_NT') {
        try {
            $ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $ehAdmin) { Write-Warning 'Abra como administrador se a leitura do log for negada.' }
        } catch { Write-Verbose 'Não foi possível verificar a elevação da sessão.' }
    }

    # ============================================================
    # Valores iniciais do menu; não alteram os padrões da linha de comando.
    # ============================================================

    $agoraMenu = Get-Date
    # No Windows, usa a unidade do sistema (normalmente C:\Relatorios).
    $raizSaida = [IO.Path]::GetTempPath()
    if ($env:SystemDrive) { $raizSaida = $env:SystemDrive + '\' }
    $pastaSaida = Join-Path $raizSaida 'Relatorios'

    $computadorPadrao = [Environment]::MachineName
    if ($env:COMPUTERNAME) { $computadorPadrao = $env:COMPUTERNAME }
    $cfg = [ordered]@{
        Computador       = @($computadorPadrao)
        EventoId         = 5145
        MaxEventos       = 0
        UsaPeriodo       = $false
        Dias             = 1
        Inicio           = $agoraMenu.AddDays(-1)
        Fim              = $null
        Pasta            = ''
        Usuario          = '*'
        UsuarioExato     = $false
        Resultado        = 'Todos'
        ExcluirUsuarios  = @()
        CsvSaida         = Join-Path $pastaSaida 'acessos-{data}.csv'
        CsvResumo        = Join-Path $pastaSaida 'resumo-{data}.csv'
        ListaAutorizados = ''
    }

    $opcoes = [ordered]@{
        IgnorarAtributos                  = @{ Ativo = $false; Desc = 'Descarta acessos de "ruído" (ler atributos/permissões)' }
        Agrupar                           = @{ Ativo = $false; Desc = 'Agrupa eventos repetidos no mesmo minuto' }
        IncluirContasComputador           = @{ Ativo = $false; Desc = 'Inclui contas de computador (terminadas em $)' }
        IncluirCompartilhamentosEspeciais = @{ Ativo = $false; Desc = 'Inclui IPC$, ADMIN$, C$...' }
        ListarCompartilhamentos           = @{ Ativo = $false; Desc = 'Lista compartilhamentos e registros encontrados' }
        EnriquecerAD                      = @{ Ativo = $false; Desc = 'Departamento e cargo do AD' }
        ResolverSids                      = @{ Ativo = $false; Desc = 'Traduz SIDs em nomes (depende do domínio)' }
        ResolverIP                        = @{ Ativo = $false; Desc = 'Nome da estação (DNS reverso)' }
        Silencioso                        = @{ Ativo = $true; Desc = 'Não imprime resumos no console' }
        GridView                          = @{ Ativo = $false; Desc = 'Abre o resultado em janela' }
        PassThru                          = @{ Ativo = $false; Desc = 'Retorna objetos para o pipeline' }
    }

    # Reutilizar valores explícitos da linha de comando ao abrir o menu.
    foreach ($chave in $ParametrosIniciais.Keys) {
        if ($cfg.Contains($chave)) { $cfg[$chave] = $ParametrosIniciais[$chave] }
        if ($opcoes.Contains($chave)) { $opcoes[$chave].Ativo = [bool]$ParametrosIniciais[$chave] }
    }
    $cfg.Computador = @($cfg.Computador)
    $cfg.ExcluirUsuarios = @($cfg.ExcluirUsuarios)
    $cfg.UsaPeriodo = $ParametrosIniciais.ContainsKey('Inicio')
    if (-not $cfg.UsaPeriodo) { $cfg.Inicio = $agoraMenu.AddDays(-[int]$cfg.Dias) }

    $descEvento = @{
        5145 = '5145 - Verificação de acesso SMB [padrão]'
        4663 = '4663 - Uso de direito no objeto (exige SACL)'
        5140 = '5140 - Conexão a um compartilhamento'
        4660 = '4660 - Exclusão (caminho depende de correlação)'
    }


    # ============================================================
    # Funções de entrada
    # ============================================================

    function Read-Texto {
        param (
            [string]$Pergunta,
            [string]$Atual = ''
        )

        if ($Atual) { $r = Read-Host "$Pergunta [$Atual]" }
        else        { $r = Read-Host $Pergunta }

        if ([string]::IsNullOrWhiteSpace($r)) { return $Atual }

        $r = $r.Trim().Trim('"')

        if ($r -eq '-') { return '' }   # "-" limpa o valor

        return $r
    }

    function ConvertTo-Lista {
        param ([string]$Texto)

        return @(
            $Texto -split '[,;]' |
            ForEach-Object { $_.Trim().Trim('"') } |
            Where-Object { $_ }
        )
    }

    function Read-Inteiro {
        param (
            [string]$Pergunta,
            [int]$Atual,
            [int]$Min,
            [int]$Max
        )

        while ($true) {

            $r = Read-Texto $Pergunta ([string]$Atual)
            $n = 0

            if ([int]::TryParse($r, [ref]$n) -and $n -ge $Min -and $n -le $Max) {
                return $n
            }

            Write-Host "  Valor inválido. Informe um número entre $Min e $Max." -ForegroundColor Yellow
        }
    }

    function Read-Data {
        param (
            [string]$Pergunta,
            $Atual,
            [bool]$Opcional = $false
        )

        while ($true) {

            $textoAtual = ''
            if ($null -ne $Atual) { $textoAtual = $Atual.ToString('dd/MM/yyyy HH:mm:ss') }
            if ($null -eq $Atual -and $Opcional) {
                $r = Read-Host "$Pergunta [até agora]"
                if ([string]::IsNullOrWhiteSpace($r) -or $r.Trim() -eq '-') { return $null }
            }
            else { $r = Read-Texto $Pergunta $textoAtual }

            if ([string]::IsNullOrWhiteSpace($r)) {

                if ($Opcional) { return $null }

                Write-Host '  Informe uma data.' -ForegroundColor Yellow
                continue
            }

            $d = [datetime]::MinValue

            if ([datetime]::TryParse($r, $ptBR, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
                return $d
            }

            Write-Host '  Data inválida. Use dd/MM/yyyy HH:mm (ex.: 19/10/2026 08:00).' -ForegroundColor Yellow
        }
    }


    # ============================================================
    # Edição de cada item do menu
    # ============================================================

    function Edit-Servidores {

        Write-Host ''
        Write-Host 'Um ou mais servidores de arquivos, separados por vírgula (ex.: SRV-ARQ1,SRV-ARQ2).'

        $r = Read-Texto 'Servidor(es)' ($cfg.Computador -join ',')
        $lista = ConvertTo-Lista $r

        if ($lista.Count -gt 0) { $cfg.Computador = $lista }
    }

    function Edit-Evento {

        Write-Host ''
        Write-Host '  1) ' $descEvento[5145]
        Write-Host '  2) ' $descEvento[4663]
        Write-Host '  3) ' $descEvento[5140]
        Write-Host '  4) ' $descEvento[4660]

        $eventosMenu = @{'1'=5145; '2'=4663; '3'=5140; '5145'=5145; '4663'=4663; '5140'=5140; '4'=4660; '4660'=4660}
        while ($true) {
            $r = (Read-Host "Digite a opção ou o ID do evento [$($cfg.EventoId)]; Enter mantém").Trim()
            if ([string]::IsNullOrWhiteSpace($r)) { return }
            if ($eventosMenu.ContainsKey($r)) {
                $cfg.EventoId = $eventosMenu[$r]
                return
            }
            Write-Host 'Evento inválido. Use 5145, 4663, 5140 ou 4660 (ou as opções 1 a 4).' -ForegroundColor Yellow
        }
    }

    function Edit-Periodo {

        Write-Host ''
        Write-Host '  1) Últimos N dias'
        Write-Host '  2) Período específico (início e fim)'

        $r = (Read-Host 'Escolha').Trim()

        if ($r -eq '1') {

            $cfg.UsaPeriodo = $false
            $cfg.Dias = Read-Inteiro 'Quantos dias para trás' $cfg.Dias 1 3650
            $cfg.Inicio = (Get-Date).AddDays(-$cfg.Dias)
            $cfg.Fim = $null
        }
        elseif ($r -eq '2') {

            while ($true) {

                $ini = Read-Data 'Início (dd/MM/yyyy HH:mm)' $cfg.Inicio
                $fim = Read-Data 'Fim (Enter mantém; "-" = até agora)' $cfg.Fim $true

                if ($null -ne $fim -and $fim -le $ini) {
                    Write-Host '  O fim deve ser posterior ao início.' -ForegroundColor Yellow
                    continue
                }

                $cfg.Inicio = $ini
                $cfg.Fim = $fim
                $cfg.UsaPeriodo = $true
                break
            }
        }
    }

    function Edit-Pasta {

        Write-Host ''
        Write-Host 'Trecho do caminho, pasta, arquivo ou compartilhamento a filtrar.'
        Write-Host 'Exemplos: RH | E:\FileServer\RH | \\SRV\z\RH'
        Write-Host 'Enter mantém a pasta atual; "-" pesquisa todas as pastas.'

        $cfg.Pasta = Read-Texto 'Pasta' $cfg.Pasta
    }

    function Edit-Usuario {

        Write-Host ''
        Write-Host 'Aceita curingas (joao, joao*, *silva*) ou DOMINIO\usuario. "*" = todos.'

        $r = Read-Texto 'Usuário' $cfg.Usuario

        if ([string]::IsNullOrWhiteSpace($r)) { $r = '*' }

        $cfg.Usuario = $r

        $exatoAnterior = [bool]$cfg.UsuarioExato
        $cfg.UsuarioExato = $false

        if ($r -notmatch '[\*\?\[\]\\"'']') {

            $padraoExato = 'N'
            if ($exatoAnterior) { $padraoExato = 'S' }
            do { $exato = (Read-Host "Nome exato no log? Diferencia maiúsculas/minúsculas (S/N) [$padraoExato]").Trim() }
            while ($exato -notmatch '^(?:[sSnN])?$')
            if (-not $exato) { $cfg.UsuarioExato = $exatoAnterior }
            else { $cfg.UsuarioExato = $exato -match '^[sS]$' }
        }
    }

    function Edit-Resultado {

        Write-Host ''
        Write-Host '  1) Todos'
        Write-Host '  2) Somente êxito'
        Write-Host '  3) Somente falha'

        $r = Read-Host 'Escolha (Enter mantém o atual)'

        switch ($r.Trim()) {
            '1' { $cfg.Resultado = 'Todos' }
            '2' { $cfg.Resultado = 'Exito' }
            '3' { $cfg.Resultado = 'Falha' }
        }
    }

    function Edit-ExcluirUsuarios {

        Write-Host ''
        Write-Host 'Contas de serviço a ignorar, separadas por vírgula (curingas aceitos).'
        Write-Host 'Exemplo: svc-backup,svc-av*   ("-" limpa a lista)'

        $r = Read-Texto 'Excluir usuários' ($cfg.ExcluirUsuarios -join ',')

        $cfg.ExcluirUsuarios = ConvertTo-Lista $r
    }

    function Edit-Opcoes {

        while ($true) {

            $chaves = @($opcoes.Keys)

            Write-Host ''

            for ($i = 0; $i -lt $chaves.Count; $i++) {

                $k = $chaves[$i]

                if ($opcoes[$k].Ativo) { $marca = 'X' } else { $marca = ' ' }

                Write-Host ('  {0,2}) [{1}] {2,-35} {3}' -f ($i + 1), $marca, $k, $opcoes[$k].Desc)
            }

            $r = Read-Host 'Números para marcar/desmarcar (ex.: 1,2) ou Enter para voltar'

            if ([string]::IsNullOrWhiteSpace($r)) { return }

            foreach ($n in (ConvertTo-Lista $r)) {

                $indice = 0
                if ([int]::TryParse($n, [ref]$indice) -and $indice -ge 1 -and $indice -le $chaves.Count) {

                    $k = $chaves[$indice - 1]
                    $opcoes[$k].Ativo = -not $opcoes[$k].Ativo
                }
            }
        }
    }

    function Edit-Csv {
        param ([string]$Campo, [string]$Titulo)

        Write-Host ''
        Write-Host 'Caminho do arquivo CSV. Aceita {data} (vira yyyyMMdd-HHmmss).'
        Write-Host 'Exemplo: C:\Relatorios\acessos-{data}.csv   ("-" desativa)'

        $cfg[$Campo] = Read-Texto $Titulo $cfg[$Campo]
    }

    function Edit-ListaAutorizados {

        Write-Host ''
        Write-Host 'CSV (separador ";") com as colunas Pasta;Grupo. Requer RSAT/ActiveDirectory.'

        while ($true) {

            $r = Read-Texto 'Lista de autorizados ("-" desativa)' $cfg.ListaAutorizados

            if ([string]::IsNullOrWhiteSpace($r) -or (Test-Path -LiteralPath $r)) {
                $cfg.ListaAutorizados = $r
                return
            }

            Write-Host '  Arquivo não encontrado.' -ForegroundColor Yellow
        }
    }


    # ============================================================
    # Montagem e execução
    # ============================================================

    function New-Parametros {

        $p = [ordered]@{}

        $p.Computador = @($cfg.Computador)
        $p.EventoId = [int]$cfg.EventoId
        if ($cfg.MaxEventos -gt 0) { $p.MaxEventos = [int]$cfg.MaxEventos }

        if ($cfg.UsaPeriodo -and $null -ne $cfg.Inicio) {

            $p.Inicio = $cfg.Inicio

            if ($null -ne $cfg.Fim) { $p.Fim = $cfg.Fim }
        }
        else {
            $p.Dias = [int]$cfg.Dias
        }

        if ($cfg.Pasta)                     { $p.Pasta = $cfg.Pasta }
        if ($cfg.Usuario -and $cfg.Usuario -ne '*') { $p.Usuario = $cfg.Usuario }
        if ($cfg.UsuarioExato)              { $p.UsuarioExato = $true }
        if ($cfg.Resultado -ne 'Todos')     { $p.Resultado = $cfg.Resultado }
        if ($cfg.ExcluirUsuarios.Count -gt 0) { $p.ExcluirUsuarios = @($cfg.ExcluirUsuarios) }
        if ($cfg.CsvSaida)                  { $p.CsvSaida = $cfg.CsvSaida }
        if ($cfg.CsvResumo)                 { $p.CsvResumo = $cfg.CsvResumo }
        if ($cfg.ListaAutorizados)          { $p.ListaAutorizados = $cfg.ListaAutorizados }

        foreach ($k in $opcoes.Keys) {
            if ($opcoes[$k].Ativo) { $p[$k] = $true }
        }

        return $p
    }

    function Format-Valor {
        param ($Valor)

        if ($Valor -is [datetime]) {
            return '([datetime]::new(' + (@($Valor.Year, $Valor.Month, $Valor.Day, $Valor.Hour, $Valor.Minute, $Valor.Second, $Valor.Millisecond) -join ',') + '))'
        }
        if ($Valor -is [int])      { return [string]$Valor }

        if ($Valor -is [array]) {
            return (($Valor | ForEach-Object { Format-Valor $_ }) -join ',')
        }

        return "'" + ([string]$Valor -replace "'", "''") + "'"
    }

    function Format-Comando {
        param ($Parametros)

        $partes = @('& ' + (Format-Valor $ScriptRelatorio))

        foreach ($k in $Parametros.Keys) {

            if ($Parametros[$k] -is [bool]) { $partes += "-$k" }
            else                            { $partes += "-$k " + (Format-Valor $Parametros[$k]) }
        }

        return ($partes -join ' ')
    }

    function Invoke-Relatorio {

        if ($cfg.UsaPeriodo -and $null -eq $cfg.Inicio) {
            Write-Host 'Defina o início do período antes de executar.' -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            return
        }

        $p = New-Parametros

        Write-Host ''
        Write-Host 'Comando equivalente (revise os caminhos antes de agendar):' -ForegroundColor Cyan
        Write-Host (Format-Comando $p) -ForegroundColor Gray
        Write-Host ''

        do { $r = (Read-Host 'Executar agora? (S/N) [S]').Trim() }
        while ($r -notmatch '^(?:[sSnN])?$')
        if ($r -match '^[nN]$') { return }

        try {
            if ($p.Contains('PassThru') -and [bool]$p['PassThru']) {
                & $ScriptRelatorio @p
            }
            else {
                & $ScriptRelatorio @p | Out-Host
            }
        }
        catch {
            Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''
        Read-Host 'Pressione Enter para voltar ao menu' | Out-Null
    }


    # ============================================================
    # Menu principal
    # ============================================================

    function Show-Menu {

        Clear-Host

        if ($cfg.UsaPeriodo -and $null -ne $cfg.Inicio) {

            $textoPeriodo = $cfg.Inicio.ToString('dd/MM/yyyy HH:mm') + ' até '

            if ($null -ne $cfg.Fim) { $textoPeriodo += $cfg.Fim.ToString('dd/MM/yyyy HH:mm') }
            else                    { $textoPeriodo += 'agora' }
        }
        else {
            $textoPeriodo = "últimos $($cfg.Dias) dia(s)"
        }

        if ($cfg.Pasta) { $textoPasta = $cfg.Pasta } else { $textoPasta = '(todas)' }

        $textoUsuario = $cfg.Usuario
        if ($cfg.Usuario -eq '*') { $textoUsuario = '(todos)' }
        if ($cfg.UsuarioExato) { $textoUsuario += ' (exato)' }

        if ($cfg.ExcluirUsuarios.Count -gt 0) { $textoExcluir = $cfg.ExcluirUsuarios -join ', ' } else { $textoExcluir = '(nenhum)' }

        $ativas = @($opcoes.Keys | Where-Object { $opcoes[$_].Ativo })
        if ($ativas.Count -gt 0) { $textoOpcoes = $ativas -join ', ' } else { $textoOpcoes = '(todas desativadas)' }

        if ($cfg.CsvSaida)         { $textoCsv = $cfg.CsvSaida }         else { $textoCsv = '(não exporta)' }
        if ($cfg.CsvResumo)        { $textoResumo = $cfg.CsvResumo }     else { $textoResumo = '(não exporta)' }
        if ($cfg.ListaAutorizados) { $textoAut = $cfg.ListaAutorizados } else { $textoAut = '(desativada; requer seu CSV)' }

        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RELATÓRIO DE AUDITORIA DE ACESSOS - MENU' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host " 1) Servidor(es)          : $($cfg.Computador -join ', ')"
        Write-Host " 2) Evento                : $($descEvento[[int]$cfg.EventoId])"
        Write-Host " 3) Período               : $textoPeriodo"
        Write-Host " 4) Pasta/compartilhamento: $textoPasta"
        Write-Host " 5) Usuário               : $textoUsuario"
        Write-Host " 6) Resultado             : $($cfg.Resultado)"
        Write-Host " 7) Excluir usuários      : $textoExcluir"
        Write-Host " 8) Opções                : $textoOpcoes"
        Write-Host " 9) CSV detalhado         : $textoCsv"
        Write-Host "10) CSV resumo            : $textoResumo"
        Write-Host "11) Lista de autorizados  : $textoAut"
        $textoLimite = 'sem limite'
        if ($cfg.MaxEventos -gt 0) { $textoLimite = "$($cfg.MaxEventos) por servidor; pode ser parcial" }
        Write-Host "12) Limite de diagnóstico : $textoLimite"
        if ($cfg.Usuario -ne '*' -and -not $cfg.UsuarioExato) { Write-Host ' Usuário filtrado após leitura. Nome exato (opção 5) pode acelerar.' -ForegroundColor Yellow }
        Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host ' E) Executar relatório      Q) Sair'
        Write-Host ' Pronto para executar. Altere somente o que precisar.'
        Write-Host ' Enter mantém o valor; - limpa um filtro/caminho ou desativa um CSV.'
        if ($cfg.ListaAutorizados) { Write-Host ' Autorização por grupos é auxiliar; confira identidade e permissões.' -ForegroundColor Yellow }
        Write-Host '============================================================' -ForegroundColor DarkGray
    }

    while ($true) {

        Show-Menu

        $op = (Read-Host 'Escolha uma opção').Trim().ToUpper()

        switch ($op) {
            '1'  { Edit-Servidores }
            '2'  { Edit-Evento }
            '3'  { Edit-Periodo }
            '4'  { Edit-Pasta }
            '5'  { Edit-Usuario }
            '6'  { Edit-Resultado }
            '7'  { Edit-ExcluirUsuarios }
            '8'  { Edit-Opcoes }
            '9'  { Edit-Csv -Campo 'CsvSaida'  -Titulo 'CSV detalhado' }
            '10' { Edit-Csv -Campo 'CsvResumo' -Titulo 'CSV resumo' }
            '11' { Edit-ListaAutorizados }
            '12' { $cfg.MaxEventos = Read-Inteiro 'Limite por servidor (0 = sem limite)' $cfg.MaxEventos 0 2147483647 }
            'E'  { Invoke-Relatorio }
            'Q'  { return }
            default { }
        }
    }
}

if ($Menu) {
    $iniciais = @{}
    foreach ($chave in $PSBoundParameters.Keys) {
        if ($chave -ne 'Menu') { $iniciais[$chave] = $PSBoundParameters[$chave] }
    }
    Show-MenuRelatorioAcesso -ScriptRelatorio $PSCommandPath -ParametrosIniciais $iniciais
    return
}

# ============================================================
# Configuração inicial
# ============================================================

if ($PSCmdlet.ParameterSetName -eq 'Periodo') {

    $dataInicio = $Inicio
    $usaFim = $PSBoundParameters.ContainsKey('Fim')

    if ($usaFim) {
        $dataFim = $Fim
    }
    else {
        $dataFim = Get-Date
    }

    if ($dataFim -le $dataInicio) {
        Write-Error '-Fim deve ser posterior a -Inicio.'
        return
    }
}
else {

    $dataInicio = (Get-Date).AddDays(-$Dias)
    $dataFim = Get-Date
    $usaFim = $false
}

$usaFim = $true # Fechar a janela antes da consulta, inclusive no modo Dias.

# Padrão de busca da pasta com caracteres especiais escapados ([ ] * ?)
# (sem -Pasta, o filtro de pasta fica aberto e considera tudo)
if ([string]::IsNullOrWhiteSpace($Pasta)) {
    $padraoPasta = '*'
}
else {
    $padraoPasta = '*' + [WildcardPattern]::Escape($Pasta) + '*'
}

# Contadores de controle
$totalLidos = 0
$falhasParse = 0
$ignoradosRuido = 0
$ignoradosEspeciais = 0
$ignoradosExcluidos = 0

# Cache de resolução de SIDs e apelidos SDDL usados no AccessReason (5145)
$cacheSid = @{}
$cacheConcessao = @{}
$aliasesSddl = @{
    WD = 'Everyone'
    AU = 'NT AUTHORITY\Authenticated Users'
    BU = 'BUILTIN\Users'
    BA = 'BUILTIN\Administrators'
    SY = 'NT AUTHORITY\SYSTEM'
    DU = 'Domain Users'
    DA = 'Domain Admins'
    DG = 'Domain Guests'
    DC = 'Domain Computers'
    DD = 'Domain Controllers'
    CO = 'CREATOR OWNER'
    CG = 'CREATOR GROUP'
    IU = 'NT AUTHORITY\INTERACTIVE'
    NU = 'NT AUTHORITY\NETWORK'
    AN = 'NT AUTHORITY\ANONYMOUS LOGON'
    LS = 'NT AUTHORITY\LOCAL SERVICE'
    NS = 'NT AUTHORITY\NETWORK SERVICE'
    BO = 'BUILTIN\Backup Operators'
    SO = 'BUILTIN\Server Operators'
    AO = 'BUILTIN\Account Operators'
    BG = 'BUILTIN\Guests'
    RD = 'BUILTIN\Remote Desktop Users'
}

$listaShares = New-Object 'System.Collections.Generic.List[object]'

# Token {data} nos caminhos de CSV (útil em execuções agendadas)
if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {
    $CsvSaida = $CsvSaida -replace '\{data\}', (Get-Date -Format 'yyyyMMdd-HHmmss')
}

if (-not [string]::IsNullOrWhiteSpace($CsvResumo)) {
    $CsvResumo = $CsvResumo -replace '\{data\}', (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$servidoresComErro = New-Object 'System.Collections.Generic.List[string]'
$servidoresSemEventos = New-Object 'System.Collections.Generic.List[string]'

if ($usaFim) {
    $textoFim = $dataFim.ToString('dd/MM/yyyy HH:mm:ss')
}
else {
    $textoFim = 'agora'
}


Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ' RELATÓRIO DE AUDITORIA DE ACESSOS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkGray

Write-Host "Servidor(es): $($Computador -join ', ')"
Write-Host "Evento      : $EventoId"
if ([string]::IsNullOrWhiteSpace($Pasta)) {
    Write-Host 'Filtro      : (todas as pastas/compartilhamentos)'
}
else {
    Write-Host "Filtro      : $Pasta"
}
Write-Host "Usuário     : $Usuario"
Write-Host "Resultado   : $Resultado"
Write-Host "Período     : $($dataInicio.ToString('dd/MM/yyyy HH:mm:ss')) até $textoFim"

Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ''


# ============================================================
# Lista de autorizados (opcional)
# ============================================================

$regrasAutorizacao = @()
$membrosPorGrupo = @{}

if (-not [string]::IsNullOrWhiteSpace($ListaAutorizados)) {

    if (-not (Test-Path -LiteralPath $ListaAutorizados)) {
        Write-Error "Arquivo de autorizados não encontrado: $ListaAutorizados"
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Error 'O módulo ActiveDirectory (RSAT) é necessário para usar -ListaAutorizados.'
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    $linhasLista = @(Import-Csv -LiteralPath $ListaAutorizados -Delimiter ';' -Encoding UTF8)

    foreach ($linha in $linhasLista) {

        $pastaRegra = ([string]$linha.Pasta).Trim()
        $grupoRegra = ([string]$linha.Grupo).Trim()

        if ($pastaRegra -and $grupoRegra) {

            $regrasAutorizacao += [PSCustomObject]@{
                Pasta  = $pastaRegra
                Grupo  = $grupoRegra
                Padrao = '*' + [WildcardPattern]::Escape($pastaRegra) + '*'
            }
        }
    }

    if ($regrasAutorizacao.Count -eq 0) {
        Write-Error "Nenhuma regra válida em '$ListaAutorizados' (use as colunas Pasta;Grupo, separadas por ';')."
        return
    }

    $gruposDistintos = @($regrasAutorizacao | ForEach-Object { $_.Grupo } | Sort-Object -Unique)

    foreach ($grupo in $gruposDistintos) {

        $nomeGrupo = $grupo -replace '^.*\\', ''

        try {

            $membros = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            Get-ADGroupMember -Identity $nomeGrupo -Recursive -ErrorAction Stop |
                ForEach-Object { [void]$membros.Add([string]$_.SamAccountName) }

            $membrosPorGrupo[$grupo] = $membros
        }
        catch {

            Write-Warning "Grupo '$grupo' não pôde ser lido: $($_.Exception.Message)"
        }
    }

    Write-Host "Autorizados : $($regrasAutorizacao.Count) regra(s); $($membrosPorGrupo.Count) de $($gruposDistintos.Count) grupo(s) lidos" -ForegroundColor DarkGray
    Write-Host ''
}


# ============================================================
# Montagem do filtro XPath (aplicado direto no log)
# ============================================================

$clausulaTempo = "@SystemTime>='$(ConvertTo-XPathTime $dataInicio)'"

if ($usaFim) {
    $clausulaTempo += " and @SystemTime<='$(ConvertTo-XPathTime $dataFim)'"
}

$condicoesSistema = "(EventID=$EventoId)"
if ($EventoId -eq 4660) {
    $condicoesSistema = '(EventID=4660 or EventID=4656 or EventID=4658 or EventID=4663 or EventID=4608 or EventID=4609 or EventID=1102)'
}

# Palavras-chave de auditoria: Falha = 0x10000000000000, Êxito = 0x20000000000000
# (mesma sintaxe band() das exibições personalizadas do Visualizador de Eventos)
if ($EventoId -ne 4660 -and $Resultado -eq 'Falha') {
    $condicoesSistema += ' and band(Keywords,4503599627370496)'
}
elseif ($EventoId -ne 4660 -and $Resultado -eq 'Exito') {
    $condicoesSistema += ' and band(Keywords,9007199254740992)'
}

$condicoesSistema += " and TimeCreated[$clausulaTempo]"

$xpath = "*[System[$condicoesSistema]"

$filtroUsuarioNoLog = $false
# Filtro de usuário na consulta (opcional, mais rápido; diferencia maiúsculas).
# Se houver aspas ou "\" no nome, o filtro fica apenas no PowerShell para evitar
# incompatibilidades com o subconjunto XPath aceito pelo Event Log.
if (
    $UsuarioExato -and
    $Usuario -notmatch '[\*\?\[\]\\]' -and
    $Usuario -notmatch '["'']'
) {

    if ($EventoId -eq 4660) {
        # Manter reinício/limpeza mesmo sem SubjectUserName para invalidar handles.
        $xpath += " and (EventData[Data[@Name='SubjectUserName']='$Usuario'] or System[(EventID=4608 or EventID=4609 or EventID=1102)])"
    }
    else { $xpath += " and EventData[Data[@Name='SubjectUserName']='$Usuario']" }
    $filtroUsuarioNoLog = $true
}
elseif ($UsuarioExato) {

    Write-Verbose 'Nome de usuário com curinga, aspas ou "\"; filtro XPath otimizado não será aplicado.'
}

$xpath += ']'

Write-Verbose "XPath: $xpath"


# ============================================================
# Consulta e processamento (streaming, servidor por servidor)
# ============================================================

$registros = New-Object 'System.Collections.Generic.List[object]'
$indiceGrupos = @{}
$diagnosticoConsulta = New-Object 'System.Collections.Generic.List[object]'

foreach ($servidor in $Computador) {
    $handlesExclusao = @{}
    $ultimoRecordCorrelacao = 0L
    $passosCorrelacao = 0
    $descartesCorrelacao = 0
    $exclusoesSemCaminho = 0
    $pastaLocalTraduzida = ''
    if ($EventoId -in @(4663,4660) -and $Pasta -match '^\\\\([^\\]+)\\([^\\]+)(.*)$') {
        $hostFiltro = $Matches[1]; $nomeShare = $Matches[2]; $subcaminho = $Matches[3]
        if ($hostFiltro -ieq $servidor -or
            (($hostFiltro -notlike '*.*' -or $servidor -notlike '*.*') -and
             ($hostFiltro.Split('.')[0] -ieq $servidor.Split('.')[0]))) {
            $shareFiltro = @(Get-CompartilhamentosServidor -Servidor $servidor | Where-Object { $_.Name -ieq $nomeShare })
            if ($shareFiltro.Count -eq 1 -and $shareFiltro[0].Path) {
                $pastaLocalTraduzida = ([string]$shareFiltro[0].Path).TrimEnd('\') + $subcaminho.TrimEnd('\')
            } else {
                Write-Warning "Não foi possível traduzir '$Pasta' para o caminho local no servidor '$servidor'. Para 4663/4660 use o caminho absoluto, por exemplo E:\FileServer, ou confira o inventário SMB."
            }
        }
    }


    Write-Host "Consultando log de Segurança em $servidor..." -ForegroundColor Cyan

    Test-LogSeguranca -Servidor $servidor -Inicio $dataInicio

    if ($ListarCompartilhamentos) {

        $sharesServidor = @(Get-CompartilhamentosServidor -Servidor $servidor)

        foreach ($sh in $sharesServidor) {

            $listaShares.Add([PSCustomObject]@{
                Servidor  = $servidor
                Nome      = $sh.Name
                Caminho   = $sh.Path
                Descricao = $sh.Description
            })
        }

        if (-not $Silencioso -and $sharesServidor.Count -gt 0) {

            Write-Host "  Compartilhamentos em ${servidor}: $($sharesServidor.Count)" -ForegroundColor DarkGray

            $sharesServidor |
                Format-Table Name, Path -AutoSize |
                Out-Host
        }
    }

    # Servidor local: lê direto, sem RPC (-ComputerName só para remotos)
    $parametrosLog = @{
        LogName     = 'Security'
        FilterXPath = $xpath
        ErrorAction = 'Stop'
    }

    if (-not (Test-ServidorLocal $servidor)) {
        $parametrosLog.ComputerName = $servidor
    }

    if ($EventoId -eq 4660) {
        $parametrosLog.Oldest = $true
        Write-Host 'Correlacionando exclusões em ordem cronológica; inclui eventos de suporte. Usa 4656 ou 4663 DELETE próximo; sem evidência, o caminho fica vazio.' -ForegroundColor DarkGray
    }
    if ($MaxEventos -gt 0) { $parametrosLog.MaxEvents = $MaxEventos }
    $tempoConsulta = [Diagnostics.Stopwatch]::StartNew()
    $consultadosServidor = 0
    $eventosAlvoLidos = 0
    $eventosApoioLidos = 0
    $eventosAlvoDescartados = 0
    $falhasConversaoAntes = $falhasParse
    $dataEventoAtual = $null
    $linhasAntes = $registros.Count
    $ultimoProgresso = -5.0
    $estadoConsulta = 'Concluída'
    Write-Host 'Buscando eventos. Ctrl+C interrompe; o filtro de pasta é aplicado após a leitura.' -ForegroundColor DarkGray
    if ($Usuario -ne '*' -and -not $filtroUsuarioNoLog) {
        Write-Host 'O usuário também será filtrado após a leitura; UsuarioExato pode acelerar (diferencia caixa).' -ForegroundColor Yellow
    }
    try {

        Get-WinEvent @parametrosLog |
            ForEach-Object {

                $eventoAtual = $_
                $consultadosServidor++
                $idEventoAtual = [int]$eventoAtual.Id
                $dataEventoAtual = $eventoAtual.TimeCreated
                if ($idEventoAtual -eq $EventoId) { $eventosAlvoLidos++ }
                else { $eventosApoioLidos++ }
                if (($tempoConsulta.Elapsed.TotalSeconds - $ultimoProgresso) -ge 5) {
                    $ultimoProgresso = $tempoConsulta.Elapsed.TotalSeconds
                    $status = "Lidos: $consultadosServidor | Evento $EventoId visto: $eventosAlvoLidos | Apoio: $eventosApoioLidos | Linhas: $($registros.Count - $linhasAntes) | Processando: $($dataEventoAtual.ToString('dd/MM/yyyy HH:mm:ss')) | Tempo: $($tempoConsulta.Elapsed.ToString())"
                    Write-Progress -Id 1 -Activity "Consulta em $servidor" -Status $status
                    Write-Host $status -ForegroundColor DarkGray
                }
                try {
                    if ($EventoId -eq 4660) {
                        $correlacaoAtual = Update-CorrelacaoExclusao -Evento $eventoAtual
                        $registro = $null
                        if ($idEventoAtual -eq 4660) { $registro = Convert-EventoAcesso -Evento $eventoAtual -Correlacao $correlacaoAtual }
                    }
                    else { $registro = Convert-EventoAcesso -Evento $eventoAtual }
                }
                finally {
                    if ($eventoAtual -is [IDisposable]) { $eventoAtual.Dispose() }
                }

                if ($null -eq $registro) {
                    if ($idEventoAtual -eq $EventoId) { $eventosAlvoDescartados++ }
                    return
                }

                if ($Agrupar) {

                    $chave = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f
                        $registro.Servidor,
                        $registro.Usuario,
                        $registro.LogonId,
                        $registro.IP,
                        $registro.Porta,
                        ($registro.Objeto + '|' + $registro.RecordIdAbertura + '|' + $registro.RecordIdCorrelacao + '|' + $registro.HandleId),
                        $registro.Acesso,
                        $registro.AccessMask,
                        $registro.ProcessId,
                        $registro.Resultado,
                        $registro.DataHora.ToString('yyyyMMddHHmm')

                    if ($indiceGrupos.ContainsKey($chave)) {

                        $grupo = $indiceGrupos[$chave]
                        $grupo.Ocorrencias++

                        # Preserva a janela temporal do grupo e mantém DataHora/RecordId
                        # referentes ao evento mais recente.
                        if ($registro.DataHora -lt $grupo.PrimeiroAcesso) {
                            $grupo.PrimeiroAcesso = $registro.DataHora
                        }

                        if ($registro.DataHora -gt $grupo.UltimoAcesso) {
                            $grupo.UltimoAcesso = $registro.DataHora
                        }

                        if ($registro.DataHora -gt $grupo.DataHora) {
                            $grupo.DataHora = $registro.DataHora
                            $grupo.RecordId = $registro.RecordId
                        }
                    }
                    else {

                        $indiceGrupos[$chave] = $registro
                        $registros.Add($registro)
                    }
                }
                else {

                    $registros.Add($registro)
                }
            }

    }
    catch {

        # Detecção independente do idioma do Windows
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {

            $estadoConsulta = 'Sem eventos correspondentes'
            $servidoresSemEventos.Add($servidor)
            continue
        }

        Write-Warning "[$servidor] Falha ao ler o log de Segurança: $($_.Exception.Message)"

        $estadoConsulta = 'Falha de leitura; possível resultado parcial'
        $servidoresComErro.Add($servidor)
        continue
    }
    finally {
        $tempoConsulta.Stop()
        Write-Progress -Id 1 -Activity "Consulta em $servidor" -Completed
        if ($MaxEventos -gt 0 -and $consultadosServidor -ge $MaxEventos) {
            $estadoConsulta = 'Limite atingido; cobertura possivelmente parcial'
            Write-Warning "[$servidor] Limite de $MaxEventos eventos atingido ANTES dos filtros. Resultado pode ser parcial; use zero para consultar sem limite."
        }
        if ($exclusoesSemCaminho -gt 0) { Write-Warning "[$servidor] $exclusoesSemCaminho exclusões sem caminho correlacionado; com filtro de pasta, essas exclusões não aparecem." }
        if ($descartesCorrelacao -gt 0) { Write-Warning "[$servidor] Contexto de correlação reiniciado por limite de memória; alguns caminhos podem ficar não identificados." }
        if ($eventosAlvoLidos -eq 0 -and $consultadosServidor -gt 0) {
            Write-Warning "[$servidor] Foram lidos eventos de apoio, mas nenhum evento $EventoId chegou da consulta. Confira o intervalo e a existência do evento no mesmo servidor."
        }
        Write-Host "[$servidor] Evento $EventoId visto: $eventosAlvoLidos; apoio: $eventosApoioLidos; alvos descartados: $eventosAlvoDescartados; falhas de conversão: $($falhasParse - $falhasConversaoAntes)."
        Write-Host "[$servidor] $consultadosServidor eventos lidos; $($registros.Count - $linhasAntes) linhas; tempo $($tempoConsulta.Elapsed)."
        $diagnosticoConsulta.Add([pscustomobject]@{
            Servidor = Protect-CsvCell $servidor; Estado = $estadoConsulta
            Inicio = $dataInicio.ToString('o'); Fim = $dataFim.ToString('o')
            EventosLidos = $consultadosServidor; Linhas = $registros.Count - $linhasAntes
            EventosAlvoLidos = $eventosAlvoLidos; EventosApoioLidos = $eventosApoioLidos
            EventosAlvoDescartados = $eventosAlvoDescartados; FalhasConversao = $falhasParse - $falhasConversaoAntes
            UltimoHorarioProcessado = $(if ($dataEventoAtual) { $dataEventoAtual.ToString('o') } else { '' })
            Limite = $MaxEventos; Segundos = [math]::Round($tempoConsulta.Elapsed.TotalSeconds, 2)
            Usuario = Protect-CsvCell $Usuario; UsuarioExato = [bool]$UsuarioExato
            FiltroUsuarioNoLog = $filtroUsuarioNoLog
            ExclusoesSemCaminho = $exclusoesSemCaminho; DescartesCorrelacao = $descartesCorrelacao
        })
    }
}
if ($CsvSaida) {
    $dirDiagnostico = Split-Path -Parent $CsvSaida
    if ($dirDiagnostico -and -not (Test-Path -LiteralPath $dirDiagnostico)) {
        New-Item -ItemType Directory -Path $dirDiagnostico -Force | Out-Null
    }
    $diagnosticoConsulta | Export-Csv -LiteralPath ($CsvSaida + '.execucao.csv') -Delimiter ';' -Encoding UTF8 -NoTypeInformation
}


# ============================================================
# Verificar resultado
# ============================================================

if ($registros.Count -eq 0) {

    Write-Host ''
    Write-Warning "Nenhum acesso encontrado para '$Pasta' no período informado."

    Write-Host ''
    Write-Host 'Possíveis motivos:' -ForegroundColor Yellow
    Write-Host ' - A pasta não teve acesso no período.'
    Write-Host ' - O evento escolhido não está sendo auditado.'
    Write-Host ' - O nome informado em -Pasta não corresponde ao log.'
    Write-Host ' - O log de Segurança já sobrescreveu eventos antigos.'

    if ($UsuarioExato) {
        Write-Host ' - Com -UsuarioExato a comparação diferencia maiúsculas de minúsculas.'
    }

    if ($Resultado -ne 'Todos') {
        Write-Host " - O filtro -Resultado $Resultado pode estar excluindo os eventos existentes."
    }

    if ($servidoresSemEventos.Count -gt 0) {
        Write-Host " - Sem eventos do tipo $EventoId em: $($servidoresSemEventos -join ', ')."
    }

    if ($servidoresComErro.Count -gt 0) {
        Write-Host " - Falha de leitura em: $($servidoresComErro -join ', ') (execute como Administrador; verifique RPC/firewall)."
    }

    if ($ignoradosRuido -gt 0) {
        Write-Host " - $ignoradosRuido evento(s) foram descartados por -IgnorarAtributos."
    }

    if ($ignoradosEspeciais -gt 0) {
        Write-Host " - $ignoradosEspeciais evento(s) de compartilhamentos administrativos (IPC$, ADMIN$, C$...) foram descartados; use -IncluirCompartilhamentosEspeciais para vê-los."
    }

    if ($ignoradosExcluidos -gt 0) {
        Write-Host " - $ignoradosExcluidos evento(s) foram descartados por -ExcluirUsuarios."
    }

    if ($falhasParse -gt 0) {
        Write-Warning "$falhasParse evento(s) não puderam ser processados (use -Verbose para detalhes)."
    }

    return
}


# ============================================================
# Ordenação e totais
# ============================================================

Write-Host "Ordenando $($registros.Count) linhas para gerar os relatórios..." -ForegroundColor DarkGray
$registros = @(
    $registros |
    Sort-Object DataHora -Descending
)

# Status de autorização (lista de autorizados)
if ($regrasAutorizacao.Count -gt 0) {

    foreach ($r in $registros) {
        $r.Autorizacao = Get-StatusAutorizacao $r
    }
}

# Departamento e cargo (AD), com cache por usuário
if ($EnriquecerAD) {

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

        Write-Warning 'Módulo ActiveDirectory não encontrado; -EnriquecerAD foi ignorado.'
    }
    else {

        Import-Module ActiveDirectory -ErrorAction SilentlyContinue

        $cacheAD = @{}

        foreach ($r in $registros) {

            $sam = ([string]$r.Usuario) -replace '^.*\\', ''

            if (-not $cacheAD.ContainsKey($sam)) {

                try {

                    $u = Get-ADUser -Identity $sam -Properties Department, Title -ErrorAction Stop

                    $cacheAD[$sam] = [PSCustomObject]@{
                        Departamento = [string]$u.Department
                        Cargo        = [string]$u.Title
                    }
                }
                catch {

                    $cacheAD[$sam] = [PSCustomObject]@{ Departamento = ''; Cargo = '' }
                }
            }

            $r.Departamento = $cacheAD[$sam].Departamento
            $r.Cargo = $cacheAD[$sam].Cargo
        }
    }
}

# Nome da estação (DNS reverso), com cache por IP
if ($ResolverIP) {

    $cacheIP = @{}

    foreach ($r in $registros) {

        if ([string]::IsNullOrWhiteSpace($r.IP)) {
            continue
        }

        if (-not $cacheIP.ContainsKey($r.IP)) {

            $nomeEstacao = ''

            try {
                $nomeEstacao = [System.Net.Dns]::GetHostEntry($r.IP).HostName
            }
            catch {
                $nomeEstacao = ''
            }

            $cacheIP[$r.IP] = $nomeEstacao
        }

        $r.Estacao = $cacheIP[$r.IP]
    }
}

$totalEventos = ($registros | Measure-Object Ocorrencias -Sum).Sum
$totalFalhas = [int](
    ($registros | Where-Object { $_.Resultado -eq 'Falha' } |
        Measure-Object Ocorrencias -Sum).Sum
)

Write-Host ''
Write-Host "$totalEventos acesso(s) encontrado(s) em $($registros.Count) linha(s); $totalFalhas com falha." -ForegroundColor Green
Write-Host "Eventos lidos no log: $totalLidos"
Write-Host ''


if (-not $Silencioso) {

    # ============================================================
    # Resumo por usuário
    # ============================================================

    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' RESUMO POR USUÁRIO' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkGray

    $registros |
        Group-Object Usuario |
        ForEach-Object {

            [PSCustomObject]@{
                Usuario      = $_.Name
                Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                Falhas       = [int](
                    ($_.Group | Where-Object { $_.Resultado -eq 'Falha' } |
                        Measure-Object Ocorrencias -Sum).Sum
                )
                UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
            }
        } |
        Sort-Object Acessos -Descending |
        Format-Table -AutoSize |
        Out-Host


    # ============================================================
    # Resumo por IP
    # ============================================================

    if ($registros | Where-Object { -not [string]::IsNullOrWhiteSpace($_.IP) }) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RESUMO POR IP' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray

        $registros |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.IP) } |
            Group-Object IP |
            ForEach-Object {

                [PSCustomObject]@{
                    IP           = $_.Name
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize |
            Out-Host
    }


    # ============================================================
    # Resumo por pasta
    # ============================================================

    $comPasta = $registros |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.PastaResumo) } |
        Select-Object -First 1

    if ($comPasta) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RESUMO POR PASTA' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray

        $registros |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.PastaResumo) } |
            Group-Object PastaResumo |
            ForEach-Object {

                [PSCustomObject]@{
                    Pasta        = $_.Name
                    Usuarios     = @($_.Group | Select-Object -ExpandProperty Usuario -Unique).Count
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    Falhas       = [int](
                        ($_.Group | Where-Object { $_.Resultado -eq 'Falha' } |
                            Measure-Object Ocorrencias -Sum).Sum
                    )
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize |
            Out-Host
    }

    # Compartilhamentos listados (-ListarCompartilhamentos) sem nenhum acesso
    if ($ListarCompartilhamentos -and $listaShares.Count -gt 0 -and $EventoId -ne 4663) {

        $semAcesso = @(
            foreach ($sh in $listaShares) {

                $teve = $registros |
                    Where-Object {
                        ($_.Servidor -ieq $sh.Servidor -or $_.Servidor -like "$($sh.Servidor).*") -and
                        (([string]$_.Compartilhamento) -replace '^.*\\', '') -ieq $sh.Nome
                    } |
                    Select-Object -First 1

                if (-not $teve) {
                    $sh
                }
            }
        )

        if ($semAcesso.Count -gt 0) {

            Write-Host ''
            Write-Host 'Compartilhamentos SEM acessos no período (considerando os filtros aplicados):' -ForegroundColor Yellow

            $semAcesso |
                Format-Table Servidor, Nome, Caminho -AutoSize |
                Out-Host
        }
    }


    # ============================================================
    # Alertas: permissões amplas e acessos não autorizados
    # ============================================================

    $liberadosAmplo = @($registros | Where-Object { $_.PermissaoAmpla -eq 'Sim' })

    if ($liberadosAmplo.Count -gt 0) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' PERMISSÕES AMPLAS DETECTADAS' -ForegroundColor Yellow
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host 'Regras de permissão amplas identificadas no evento:'

        $liberadosAmplo |
            Group-Object PastaResumo, ConcedidoPor |
            ForEach-Object {

                [PSCustomObject]@{
                    Pasta        = $_.Group[0].PastaResumo
                    ConcedidoPor = $_.Group[0].ConcedidoPor
                    Usuarios     = @($_.Group | Select-Object -ExpandProperty Usuario -Unique).Count
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize -Wrap |
            Out-Host
    }

    $naoAutorizados = @($registros | Where-Object { $_.Autorizacao -eq 'NAO AUTORIZADO' })

    if ($naoAutorizados.Count -gt 0) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' ACESSOS NAO AUTORIZADOS (conforme -ListaAutorizados)' -ForegroundColor Red
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host 'Fora da regra de autorização. Confira o evento: êxito no 5145 não comprova leitura do conteúdo.'

        $naoAutorizados |
            Group-Object Usuario, PastaResumo, Resultado |
            ForEach-Object {

                [PSCustomObject]@{
                    Usuario      = $_.Group[0].Usuario
                    Departamento = $_.Group[0].Departamento
                    Pasta        = $_.Group[0].PastaResumo
                    Resultado    = $_.Group[0].Resultado
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Resultado, Acessos -Descending |
            Format-Table -AutoSize -Wrap |
            Out-Host
    }


    # ============================================================
    # Detalhamento (colunas essenciais; o CSV traz todas)
    # ============================================================

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' DETALHAMENTO' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkGray

    $colunas = @('DataHora')

    if ($Computador.Count -gt 1) {
        $colunas += 'Servidor'
    }

    $colunas += 'Usuario', 'Resultado', 'IP'

    if ($ResolverIP) {
        $colunas += 'Estacao'
    }

    $colunas += 'Acao', 'Acesso', 'Objeto'

    if ($regrasAutorizacao.Count -gt 0) {
        $colunas += 'Autorizacao'
    }

    if (@($registros | Where-Object { $_.PermissaoAmpla -eq 'Sim' }).Count -gt 0) {
        $colunas += 'PermissaoAmpla'
    }

    $colunas += 'Ocorrencias'

    $registros |
        Select-Object -Property $colunas |
        Format-Table -AutoSize -Wrap |
        Out-Host
}


# ============================================================
# Exportação CSV
# ============================================================

if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {

    try {

        $diretorio = Split-Path -Path $CsvSaida -Parent

        if (
            -not [string]::IsNullOrWhiteSpace($diretorio) -and
            -not (Test-Path $diretorio)
        ) {

            New-Item -Path $diretorio -ItemType Directory -Force | Out-Null
        }

        $registros |
            ForEach-Object {

                [PSCustomObject]@{
                    DataHora         = $_.DataHora.ToString('yyyy-MM-dd HH:mm:ss')
                    PrimeiroAcesso   = $_.PrimeiroAcesso.ToString('yyyy-MM-dd HH:mm:ss')
                    UltimoAcesso     = $_.UltimoAcesso.ToString('yyyy-MM-dd HH:mm:ss')
                    Servidor         = Protect-CsvCell $_.Servidor
                    RecordId         = $_.RecordId
                    Usuario          = Protect-CsvCell $_.Usuario
                    Resultado        = $_.Resultado
                    IP               = Protect-CsvCell $_.IP
                    Porta            = $_.Porta
                    Acesso           = Protect-CsvCell $_.Acesso
                    AccessList       = Protect-CsvCell $_.AccessList
                    AccessMask       = $_.AccessMask
                    Objeto           = Protect-CsvCell $_.Objeto
                    Compartilhamento = Protect-CsvCell $_.Compartilhamento
                    CaminhoRelativo  = Protect-CsvCell $_.CaminhoRelativo
                    CaminhoLocal     = Protect-CsvCell $_.CaminhoLocal
                    Processo         = Protect-CsvCell $_.Processo
                    ProcessId        = $_.ProcessId
                    HandleId         = $_.HandleId
                    LogonId          = $_.LogonId
                    EventoId         = $_.EventoId
                    Ocorrencias      = $_.Ocorrencias
                    UsuarioSid       = $_.UsuarioSid
                    TipoObjeto       = Protect-CsvCell $_.TipoObjeto
                    AccessReason     = Protect-CsvCell $_.AccessReason
                    ConcedidoPor     = Protect-CsvCell $_.ConcedidoPor
                    PermissaoAmpla   = $_.PermissaoAmpla
                    PastaResumo      = Protect-CsvCell $_.PastaResumo
                    Estacao          = Protect-CsvCell $_.Estacao
                    Departamento     = Protect-CsvCell $_.Departamento
                    Cargo            = Protect-CsvCell $_.Cargo
                    Autorizacao      = $_.Autorizacao
                    Acao             = Protect-CsvCell $_.Acao
                    Evidencia        = Protect-CsvCell $_.Evidencia
                    RecordIdAbertura  = $_.RecordIdAbertura
                    EventoCorrelacao  = $_.EventoCorrelacao
                    RecordIdCorrelacao = $_.RecordIdCorrelacao
                    RecordIdAcesso    = $_.RecordIdAcesso
                }
            } |
            Export-Csv `
                -Path $CsvSaida `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ';'

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' EXPORTAÇÃO CONCLUÍDA' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor DarkGray

        Write-Host "Arquivo: $CsvSaida" -ForegroundColor Green
        Write-Host "Linhas exportadas: $($registros.Count)"

    }
    catch {

        Write-Error "Falha ao exportar CSV: $($_.Exception.Message)"
    }
}


# ============================================================
# Exportação CSV consolidado (usuário x pasta)
# ============================================================

if (-not [string]::IsNullOrWhiteSpace($CsvResumo)) {

    try {

        $diretorioResumo = Split-Path -Path $CsvResumo -Parent

        if (
            -not [string]::IsNullOrWhiteSpace($diretorioResumo) -and
            -not (Test-Path $diretorioResumo)
        ) {

            New-Item -Path $diretorioResumo -ItemType Directory -Force | Out-Null
        }

        $linhasResumo = @(
            $registros |
            Group-Object Usuario, PastaResumo |
            ForEach-Object {

                $g = $_.Group

                $razoes = @(
                    $g.ConcedidoPor |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                        ForEach-Object { $_ -split '; ' } |
                        Sort-Object -Unique
                )

                if (@($g | Where-Object { $_.PermissaoAmpla -eq 'Sim' }).Count -gt 0) {
                    $ampla = 'Sim'
                }
                elseif (@($g | Where-Object { $_.PermissaoAmpla -eq 'Nao' }).Count -gt 0) {
                    $ampla = 'Nao'
                }
                else {
                    $ampla = ''
                }

                if (@($g | Where-Object { $_.Autorizacao -eq 'NAO AUTORIZADO' }).Count -gt 0) {
                    $autorizacao = 'NAO AUTORIZADO'
                }
                else {
                    $autorizacao = [string]($g | Select-Object -First 1).Autorizacao
                }

                [PSCustomObject]@{
                    Usuario        = Protect-CsvCell $g[0].Usuario
                    Departamento   = Protect-CsvCell $g[0].Departamento
                    Pasta          = Protect-CsvCell $g[0].PastaResumo
                    Acessos        = ($g | Measure-Object Ocorrencias -Sum).Sum
                    Falhas         = [int](
                        ($g | Where-Object { $_.Resultado -eq 'Falha' } |
                            Measure-Object Ocorrencias -Sum).Sum
                    )
                    PrimeiroAcesso = (($g | Measure-Object PrimeiroAcesso -Minimum).Minimum).ToString('yyyy-MM-dd HH:mm:ss')
                    UltimoAcesso   = (($g | Measure-Object UltimoAcesso -Maximum).Maximum).ToString('yyyy-MM-dd HH:mm:ss')
                    ConcedidoPor   = Protect-CsvCell ($razoes -join '; ')
                    PermissaoAmpla = $ampla
                    Autorizacao    = $autorizacao
                    Acoes          = Protect-CsvCell (($g.Acao | Sort-Object -Unique) -join ' | ')
                    Evidencias     = Protect-CsvCell (($g.Evidencia | Sort-Object -Unique) -join ' | ')
                }
            }
        )

        $linhasResumo |
            Sort-Object { [int]$_.Acessos } -Descending |
            Export-Csv `
                -Path $CsvResumo `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ';'

        Write-Host ''
        Write-Host "Resumo usuário x pasta: $CsvResumo ($($linhasResumo.Count) linha(s))" -ForegroundColor Green
    }
    catch {

        Write-Error "Falha ao exportar o CSV de resumo: $($_.Exception.Message)"
    }
}


# ============================================================
# Avisos finais
# ============================================================

if ($servidoresSemEventos.Count -gt 0) {

    Write-Host ''
    Write-Host "Sem eventos do tipo $EventoId no período em: $($servidoresSemEventos -join ', ')" -ForegroundColor DarkYellow
}

if ($servidoresComErro.Count -gt 0) {

    Write-Host ''
    Write-Warning "Não foi possível ler o log de: $($servidoresComErro -join ', '). O relatório está incompleto."
}

if ($ignoradosRuido -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosRuido evento(s) de atributos/permissões foram descartados (-IgnorarAtributos)." -ForegroundColor DarkYellow
}

if ($ignoradosEspeciais -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosEspeciais evento(s) de compartilhamentos administrativos (IPC$, ADMIN$, C$...) foram descartados (use -IncluirCompartilhamentosEspeciais para incluí-los)." -ForegroundColor DarkYellow
}

if ($ignoradosExcluidos -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosExcluidos evento(s) foram descartados por -ExcluirUsuarios." -ForegroundColor DarkYellow
}

if ($falhasParse -gt 0) {

    Write-Host ''
    Write-Warning "$falhasParse evento(s) não puderam ser processados e ficaram fora do relatório (use -Verbose para detalhes)."
}


# ============================================================
# Saída interativa / pipeline
# ============================================================

if ($GridView) {

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {

        $registros |
            Out-GridView -Title 'Relatório de acessos' -Wait
    }
    else {

        Write-Warning 'Out-GridView não está disponível neste ambiente; -GridView foi ignorado.'
    }
}

if ($PassThru) {

    $registros
}
