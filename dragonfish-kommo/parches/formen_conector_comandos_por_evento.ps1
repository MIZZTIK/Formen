# Parche del conector Dragonfish -> Kommo (Formen).
#
# Objetivo: que Agustin toque UN SOLO campo. Escribe "B 6641" en
# "Dragonfish comando" y el conector lo procesa; "Dragonfish estado" pasa a ser
# solo salida (pendiente / vinculado / error), no algo que el tenga que setear.
#
# Como: la API de Kommo expone los cambios de campo en /api/v4/events filtrados
# por tipo custom_field_<id>_value_changed, con el texto nuevo, el lead y un id
# de evento unico. El conector los lee en cada pasada de 15 s y dedupea contra
# data\salesbot-events.json.
#
# La via vieja (estado = pendiente) queda intacta como escape manual.
#
# Se corre en la PC del local (C:\FormenConector). Hace backup antes de tocar y
# no escribe nada si alguna ancla no coincide.
#
# TODO va adentro de un scriptblock a proposito: pegado linea por linea en la
# consola, un `throw` no frena los comandos que vienen despues y se termina
# escribiendo un archivo a medias. Adentro del bloque, aborta de verdad.

& {
  $ErrorActionPreference = 'Stop'
  $p = 'C:\FormenConector\conector.ps1'

  $bytes = [System.IO.File]::ReadAllBytes($p)
  $tieneBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $texto = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($tieneBom) { $texto = $texto.Substring(1) }

  if ($texto.Contains('Get-ComandosPorEventosSalesbot')) {
    throw 'El conector ya tiene el parche aplicado (o quedo a medias). No se toca nada.'
  }

  $L = New-Object 'System.Collections.Generic.List[string]'
  foreach ($ln in ($texto -split "`r?`n")) { [void]$L.Add($ln) }

  function BuscarUnica {
    param($Lineas, [string]$Aguja)
    $idx = @()
    for ($i = 0; $i -lt $Lineas.Count; $i++) { if ($Lineas[$i].Contains($Aguja)) { $idx += $i } }
    if ($idx.Count -ne 1) { throw "Esperaba 1 linea con [$Aguja] y encontre $($idx.Count). No se aplica el parche." }
    return [int]$idx[0]
  }

  # El archivo tiene mas de un 'foreach ($lead in $leads)'. El que importa es el
  # de Invoke-ComandosSalesbot: el primero que aparece despues del bloque que
  # arma los trabajos.
  function BuscarDesde {
    param($Lineas, [string]$Aguja, [int]$Desde)
    for ($j = $Desde; $j -lt $Lineas.Count; $j++) { if ($Lineas[$j].Contains($Aguja)) { return [int]$j } }
    throw "No encontre [$Aguja] despues de la linea $Desde. No se aplica el parche."
  }

  $bloqueFunciones = @'
# -- Comandos escritos a mano en el campo "Dragonfish comando" ----------------
#
# Agustin escribe "B 6641" en el campo y nada mas. No tiene que acordarse de
# poner el estado en "pendiente": el conector se entera por el evento que Kommo
# genera al cambiar el valor del campo, y el estado queda como salida nuestra.
#
# Dedupe en tres capas, porque un comando procesado dos veces duplica la nota y
# suma el importe otra vez al presupuesto:
#   - id de evento ya visto (data\salesbot-events.json);
#   - el comprobante ya figura en las notas del lead;
#   - misma clave lead+comando dentro de una pasada.
#
# El conector NO escribe el campo comando, solo el estado: no hay realimentacion.

function Get-ArchivoEventosSalesbot {
  return (Join-Path $DataDir 'salesbot-events.json')
}

function Save-EventosSalesbot {
  param([string[]]$Ids)
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  # La lista llega con lo mas reciente adelante: recortar por el final.
  $lista = @($Ids | Where-Object { $_ } | Select-Object -Unique)
  if ($lista.Count -gt 500) { $lista = @($lista | Select-Object -First 500) }
  $f = Get-ArchivoEventosSalesbot
  $tmp = "$f.tmp"
  ([pscustomobject]@{ processedIds = $lista }) | ConvertTo-Json -Depth 4 | Out-File $tmp -Encoding utf8
  Move-Item -Path $tmp -Destination $f -Force
}

function Get-ComandosPorEventosSalesbot {
  param($Cfg, [int64]$ComandoFieldId)

  $script:SalesbotEventosParaGuardar = $null
  $tipo = "custom_field_${ComandoFieldId}_value_changed"
  $rutas = @(
    "/api/v4/events?filter[type][0]=$tipo&limit=50",
    "/api/v4/events?filter%5Btype%5D%5B0%5D=$tipo&limit=50",
    "/api/v4/events?filter[type]=$tipo&limit=50"
  )
  $r = $null; $llamo = $false; $ultimoError = ''
  foreach ($ruta in $rutas) {
    try { $r = Invoke-Kommo -Cfg $Cfg -Metodo 'GET' -Ruta $ruta; $llamo = $true; break }
    catch { $ultimoError = $_.Exception.Message }
  }
  if (-not $llamo) {
    Write-Log 'warn' "Salesbot por campo: no pude leer los eventos de Kommo ($ultimoError)."
    return @()
  }

  $eventos = @($r._embedded.events)
  $f = Get-ArchivoEventosSalesbot
  $previos = @()
  $primerArranque = $true
  if (Test-Path $f) {
    $primerArranque = $false
    try {
      $previos = @((Get-Content $f -Raw -Encoding utf8 | ConvertFrom-Json).processedIds)
    } catch {
      Write-Log 'warn' "salesbot-events.json ilegible ($($_.Exception.Message)). Se re-siembra: no se reprocesan comandos viejos."
      $previos = @()
      $primerArranque = $true
    }
  }

  $vistos = @()
  $nuevos = @()
  foreach ($e in $eventos) {
    $eid = "$($e.id)"
    if (-not $eid) { continue }
    $vistos += $eid
    if ($previos -contains $eid) { continue }
    if ("$($e.entity_type)" -ne 'lead') { continue }
    $txt = "$($e.value_after.custom_field_value.text)".Trim()
    if (-not $txt) { continue }
    if (-not (Parse-ComandoSalesbot $txt)) { continue }
    $nuevos += [pscustomobject]@{ EventoId = $eid; LeadId = [int64]$e.entity_id; Comando = $txt }
  }

  # Se guarda recien al final de la pasada: si el conector se cae en el medio,
  # el comando se reintenta y el dedupe por nota evita el duplicado.
  $script:SalesbotEventosParaGuardar = @($vistos + $previos)

  if ($primerArranque) {
    Save-EventosSalesbot -Ids $script:SalesbotEventosParaGuardar
    $script:SalesbotEventosParaGuardar = $null
    Write-Log 'info' "Salesbot por campo: primer arranque, $($vistos.Count) evento(s) marcados como ya vistos."
    return @()
  }

  if ($nuevos.Count -gt 0) {
    Write-Log 'info' "Salesbot por campo: $($nuevos.Count) comando(s) nuevo(s) detectado(s) por evento."
  }
  return @($nuevos)
}

'@

  $bloqueTrabajos = @'
  # Dos fuentes para el mismo trabajo: el campo estado en "pendiente" (la via
  # vieja, que sigue sirviendo de escape manual) y el evento de cambio del campo
  # comando (la via nueva, un solo paso para el local).
  $trabajos = @()
  $clavesVistas = @{}

  foreach ($leadPend in @(Get-LeadsSalesbotPendientes -Cfg $Cfg -ManualCfg $manualCfg -EstadoFieldId ([int64]$campoEstado.id) -ComandoFieldId ([int64]$campoComando.id))) {
    $lid = [int64]$leadPend.id
    $c = "$($leadPend.dragonfish_comando)".Trim()
    $k = "$lid|" + $c.ToUpperInvariant()
    if ($clavesVistas.ContainsKey($k)) { continue }
    $clavesVistas[$k] = $true
    $trabajos += [pscustomobject]@{ LeadId = $lid; Comando = $c }
  }

  foreach ($ev in @(Get-ComandosPorEventosSalesbot -Cfg $Cfg -ComandoFieldId ([int64]$campoComando.id))) {
    $k = "$($ev.LeadId)|" + "$($ev.Comando)".ToUpperInvariant()
    if ($clavesVistas.ContainsKey($k)) { continue }
    $clavesVistas[$k] = $true
    $trabajos += [pscustomobject]@{ LeadId = [int64]$ev.LeadId; Comando = "$($ev.Comando)" }
  }

  if ($trabajos.Count -eq 0) {
    if ($script:SalesbotEventosParaGuardar) {
      Save-EventosSalesbot -Ids $script:SalesbotEventosParaGuardar
      $script:SalesbotEventosParaGuardar = $null
    }
    return
  }
'@

  # 1) funciones nuevas, antes de Get-LeadsSalesbotPendientes
  $i = BuscarUnica $L 'function Get-LeadsSalesbotPendientes {'
  $L.InsertRange($i, [string[]]($bloqueFunciones -split "`r?`n"))

  # 2) las dos lineas que armaban $leads -> lista unificada de trabajos
  $i = BuscarUnica $L '$leads = @(Get-LeadsSalesbotPendientes -Cfg $Cfg'
  if (-not $L[$i + 1].Contains('if ($leads.Count -eq 0) { return }')) { throw 'No encontre el return de $leads. No se aplica el parche.' }
  $L.RemoveRange($i, 2)
  $L.InsertRange($i, [string[]]($bloqueTrabajos -split "`r?`n"))

  # 3) el foreach de Invoke-ComandosSalesbot y sus dos primeras lineas
  $j = BuscarDesde $L 'foreach ($lead in $leads) {' $i
  if (-not $L[$j + 1].Contains('$leadId = [int64]$lead.id')) { throw 'No encontre la linea del $leadId. No se aplica el parche.' }
  if (-not $L[$j + 2].Contains('$lead.dragonfish_comando')) { throw 'No encontre la linea del $cmd. No se aplica el parche.' }
  $L[$j]     = '  foreach ($t in $trabajos) {'
  $L[$j + 1] = '    $leadId = [int64]$t.LeadId'
  $L[$j + 2] = '    $cmd = "$($t.Comando)".Trim()'

  # 4) marcar los eventos como vistos antes del resumen de la pasada
  $k = BuscarUnica $L 'Salesbot manual: $ok vinculadas'
  $L.Insert($k, '  if ($script:SalesbotEventosParaGuardar) { Save-EventosSalesbot -Ids $script:SalesbotEventosParaGuardar; $script:SalesbotEventosParaGuardar = $null }')

  # recien aca se toca el disco: si algo fallo arriba, el archivo quedo intacto
  $bak = "$p.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
  [System.IO.File]::WriteAllBytes($bak, $bytes)
  "backup: $bak"

  $enc = New-Object System.Text.UTF8Encoding($tieneBom)
  [System.IO.File]::WriteAllText($p, ($L -join "`r`n"), $enc)

  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    $errs | ForEach-Object { "  $($_.Extent.StartLineNumber): $($_.Message)" }
    [System.IO.File]::WriteAllBytes($p, [System.IO.File]::ReadAllBytes($bak))
    throw "PARSER CON ERRORES. Se restauro el backup: $bak"
  }

  'parser OK - parche aplicado'
}
