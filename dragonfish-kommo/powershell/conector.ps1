# ─────────────────────────────────────────────────────────────────────────────
#  Conector Dragonfish -> Kommo  ·  Formen
#
#  Corre EN LA PC DEL LOCAL, sin instalar nada: usa el SqlClient de .NET (ya
#  viene con Windows) y la API REST de Kommo. Se agenda con el Programador de
#  tareas.
#
#  Uso:
#    .\conector.ps1 -Once      una pasada y termina (para probar)
#    .\conector.ps1            loop continuo
#    .\conector.ps1 -Medir     imprime el reporte de apareo y termina
#
#  QUÉ HACE: las ventas de Dragonfish no guardan el teléfono del comprador
#  (casi todas van a "consumidor final"). El dato lo junta el iPad del local,
#  con un formulario de Kommo que el vendedor pasa DESPUÉS de cobrar. La única
#  llave entre los dos sistemas es el momento: la venta primero, el contacto
#  uno a diez minutos después. Ver ..\README.md.
#
#  REGLA DE ORO: si hay más de un candidato NO se adivina. Meterle a alguien la
#  compra de otro en su ficha es peor que no meterle nada.
#
#  Sobre Dragonfish solo hace SELECT. Nunca escribe en la base del cliente.
# ─────────────────────────────────────────────────────────────────────────────

param(
  [switch]$Once,
  [switch]$Medir,
  [string]$ConfigPath = "$PSScriptRoot\conector.config.json"
)

$ErrorActionPreference = 'Stop'
$DataDir = Join-Path $PSScriptRoot 'data'
$CursorFile = Join-Path $DataDir 'cursor.json'
$DetalleFile = Join-Path $DataDir 'reporte.jsonl'
$ResumenFile = Join-Path $DataDir 'reporte.json'
$LogFile = Join-Path $DataDir 'conector.log'

# ── Utilidades ───────────────────────────────────────────────────────────────

function Write-Log {
  param([string]$Nivel, [string]$Mensaje)
  $linea = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
  Write-Host $linea
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  Add-Content -Path $LogFile -Value $linea -Encoding utf8
}

function Get-Config {
  if (-not (Test-Path $ConfigPath)) {
    throw "Falta $ConfigPath. Copiar conector.config.example.json y completarlo."
  }
  $c = Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $c.kommo.token) { throw "Falta el token de Kommo en $ConfigPath" }
  if ($c.sql.schema -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    throw "Nombre de esquema invalido: $($c.sql.schema)"
  }
  return $c
}

# Kommo trunca cualquier texto en el primer emoji (su base es MySQL utf8 de
# 3 bytes). Sacamos todo lo que este fuera del plano basico.
function Remove-Emojis {
  param([string]$Texto)
  return [regex]::Replace($Texto, '[\uD800-\uDBFF][\uDC00-\uDFFF]', '')
}

# ── Dragonfish (SQL Server, solo lectura) ────────────────────────────────────

function Invoke-Sql {
  param($Cfg, [string]$Query, [hashtable]$Params = @{})

  $cs = "Server=$($Cfg.sql.server);Database=$($Cfg.sql.database);Connect Timeout=15;"
  if ($Cfg.sql.user) {
    $cs += "User Id=$($Cfg.sql.user);Password=$($Cfg.sql.password);"
  } else {
    # Fallback para pruebas a mano. En produccion va un usuario SQL propio.
    $cs += 'Integrated Security=SSPI;'
  }

  $con = New-Object System.Data.SqlClient.SqlConnection $cs
  try {
    $con.Open()
    $cmd = $con.CreateCommand()
    $cmd.CommandText = $Query
    foreach ($k in $Params.Keys) {
      [void]$cmd.Parameters.AddWithValue("@$k", $Params[$k])
    }
    $ad = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable
    [void]$ad.Fill($t)
    return $t
  } finally {
    $con.Close()
  }
}

function Get-VentasNuevas {
  param($Cfg, [datetime]$Desde)

  # El timestamp real se arma con la fecha de alta + la hora de alta.
  $ts = "CAST(CONVERT(varchar(10),FALTAFW,120)+' '+HALTAFW AS datetime)"
  $tipos = ($Cfg.tiposVenta | ForEach-Object { [int]$_ }) -join ','
  $filtroTipo = if ($tipos) { " AND FACTTIPO IN ($tipos)" } else { '' }

  $q = @"
SELECT TOP (200)
  CODIGO, FFCH, FTOTAL, FACTTIPO, FLETRA, FPTOVEN, FNUMCOMP, $ts AS TS
FROM [$($Cfg.sql.schema)].[COMPROBANTEV]
WHERE ANULADO = 0 $filtroTipo AND $ts > @desde
ORDER BY $ts ASC
"@
  $filas = Invoke-Sql -Cfg $Cfg -Query $q -Params @{ desde = $Desde }

  return $filas | ForEach-Object {
    $letra = "$($_.FLETRA)".Trim()
    $pto = "{0:d4}" -f [int]$_.FPTOVEN
    $nro = "{0:d8}" -f [int]$_.FNUMCOMP
    [pscustomobject]@{
      Id          = "$($_.CODIGO)".Trim()
      Comprobante = "$letra $pto-$nro".Trim()
      Ts          = [datetime]$_.TS
      Total       = if ($_.FTOTAL -is [DBNull]) { $null } else { [decimal]$_.FTOTAL }
    }
  }
}

# ── Kommo ────────────────────────────────────────────────────────────────────

function Invoke-Kommo {
  param($Cfg, [string]$Metodo, [string]$Ruta, $Cuerpo = $null)

  $url = "https://$($Cfg.kommo.subdominio).kommo.com$Ruta"
  $headers = @{ Authorization = "Bearer $($Cfg.kommo.token)" }
  # Ojo: no usar $args, que es una variable automatica de PowerShell.
  $req = @{ Uri = $url; Method = $Metodo; Headers = $headers; TimeoutSec = 30 }
  if ($Cuerpo) {
    $req.Body = ($Cuerpo | ConvertTo-Json -Depth 6 -Compress)
    $req.ContentType = 'application/json; charset=utf-8'
  }
  try {
    return Invoke-RestMethod @req
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 204) { return $null }   # sin resultados
    throw "Kommo $Metodo $Ruta -> $code : $($_.Exception.Message)"
  }
}

# Contactos creados entre dos momentos, filtrando por el usuario del iPad.
function Get-ContactosEnVentana {
  param($Cfg, [datetime]$Desde, [datetime]$Hasta)

  $from = [DateTimeOffset]::new($Desde).ToUnixTimeSeconds()
  $to = [DateTimeOffset]::new($Hasta).ToUnixTimeSeconds()
  $ruta = "/api/v4/contacts?filter[created_at][from]=$from&filter[created_at][to]=$to&limit=250"
  $r = Invoke-Kommo -Cfg $Cfg -Metodo 'GET' -Ruta $ruta
  if (-not $r) { return @() }

  $cs = @($r._embedded.contacts)
  # El filtro por created_by de la API no siempre se respeta: filtramos aca.
  return @($cs | Where-Object { $_.created_by -eq $Cfg.kommo.ipadUserId })
}

function Get-TelefonoContacto {
  param($Contacto)
  foreach ($f in @($Contacto.custom_fields_values)) {
    if ($f.field_code -eq 'PHONE' -or $f.field_name -eq 'Phone') {
      return "$($f.values[0].value)"
    }
  }
  return $null
}

# "3794801505" y "+5493794801505" son la misma persona. Los dejamos en los
# ultimos 10 digitos, sin el 54/549 de Argentina.
function ConvertTo-TelefonoNormalizado {
  param([string]$Telefono)
  $d = [regex]::Replace("$Telefono", '\D', '')
  if ($d.StartsWith('549')) { $d = $d.Substring(3) }
  elseif ($d.StartsWith('54')) { $d = $d.Substring(2) }
  if ($d.Length -ge 10) { return $d.Substring($d.Length - 10) }
  return $d
}

# El iPad graba el telefono en 10 digitos pelados; WhatsApp lo graba con +549.
# Kommo no los reconoce como la misma persona: 17 de las 69 cargas del iPad
# (25%, medido el 19/8/2026) son un duplicado de un contacto que ya existia.
# Si le pegamos la nota al duplicado, la ficha donde esta toda la conversacion
# de esa persona no se entera de que compro.
#
# El criterio NO es la antiguedad: en la mayoria de los casos medidos el mellizo
# de WhatsApp es mas NUEVO (la persona se carga en el local y escribe al rato,
# 12 a 52 min despues). Lo que distingue a la ficha buena es quien la creo: la
# que vino por un canal tiene la conversacion, la del iPad es solo un nombre y
# un telefono. Si hay mas de una candidata, no elegimos.
function Resolve-ContactoDestino {
  param($Cfg, $Contacto)

  if (-not $Cfg.match.preferirContactoExistente) { return $Contacto }
  $norm = ConvertTo-TelefonoNormalizado (Get-TelefonoContacto $Contacto)
  if ($norm.Length -lt 8) { return $Contacto }

  $r = Invoke-Kommo -Cfg $Cfg -Metodo 'GET' -Ruta "/api/v4/contacts?query=$norm&limit=50"
  if (-not $r) { return $Contacto }

  $mellizos = @(@($r._embedded.contacts) | Where-Object {
      $_.id -ne $Contacto.id -and
      $_.created_by -ne $Cfg.kommo.ipadUserId -and
      (ConvertTo-TelefonoNormalizado (Get-TelefonoContacto $_)) -eq $norm
    })

  if ($mellizos.Count -eq 0) { return $Contacto }
  if ($mellizos.Count -gt 1) {
    Write-Log 'warn' ("Contacto $($Contacto.id): $($mellizos.Count) fichas con el mismo telefono -> se deja la del iPad.")
    return $Contacto
  }

  $orig = $mellizos[0]
  Write-Log 'info' "Contacto $($Contacto.id) es duplicado del iPad -> la nota va a la ficha $($orig.id)."
  return $orig
}

function Add-NotaKommo {
  param($Cfg, [int64]$ContactoId, [string]$Texto)
  $cuerpo = @(@{ entity_id = $ContactoId; note_type = 'common'; params = @{ text = $Texto } })
  return Invoke-Kommo -Cfg $Cfg -Metodo 'POST' -Ruta '/api/v4/contacts/notes' -Cuerpo $cuerpo
}

function New-TextoNota {
  param($Venta, [int]$Minutos)
  $total = if ($null -ne $Venta.Total) { '$ ' + ('{0:N0}' -f $Venta.Total) } else { 's/d' }
  $lineas = @(
    'Compra en el local',
    "Comprobante: $($Venta.Comprobante)",
    "Fecha: $($Venta.Ts.ToString('dd/MM/yyyy HH:mm'))",
    "Total: $total",
    "(asociado automaticamente: el contacto se cargo $Minutos min despues de la venta)"
  )
  return Remove-Emojis ($lineas -join "`n")
}

# ── Cursor y reporte ─────────────────────────────────────────────────────────

function Get-Cursor {
  if (Test-Path $CursorFile) {
    return Get-Content $CursorFile -Raw -Encoding utf8 | ConvertFrom-Json
  }
  # Primer arranque: desde el comienzo del dia, para no arrastrar anios de historia.
  return [pscustomobject]@{
    lastTs       = (Get-Date).Date.ToString('o')
    processedIds = @()
  }
}

function Save-Cursor {
  param($Cursor)
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  # Ventana de dedupe acotada.
  if ($Cursor.processedIds.Count -gt 500) {
    $Cursor.processedIds = @($Cursor.processedIds | Select-Object -Last 500)
  }
  $Cursor | ConvertTo-Json -Depth 4 | Out-File $CursorFile -Encoding utf8
}

function Add-Registro {
  param([string]$Resultado, $Venta, $Candidatos, $Extra = @{})
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  $o = [ordered]@{
    ts          = (Get-Date).ToString('o')
    resultado   = $Resultado
    venta       = $Venta.Comprobante
    venta_ts    = $Venta.Ts.ToString('o')
    total       = $Venta.Total
    candidatos  = @($Candidatos | ForEach-Object { $_.id })
  }
  foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
  Add-Content -Path $DetalleFile -Value ($o | ConvertTo-Json -Compress -Depth 4) -Encoding utf8
}

function Add-Acumulado {
  param($Stats)
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  $data = if (Test-Path $ResumenFile) {
    Get-Content $ResumenFile -Raw -Encoding utf8 | ConvertFrom-Json
  } else { [pscustomobject]@{} }

  $hoy = (Get-Date).ToString('yyyy-MM-dd')
  if (-not $data.PSObject.Properties[$hoy]) {
    $data | Add-Member -NotePropertyName $hoy -NotePropertyValue ([pscustomobject]@{
        evaluadas = 0; asociadas = 0; sin_candidato = 0; ambiguas = 0; fallidas = 0
      })
  }
  foreach ($k in @('evaluadas', 'asociadas', 'sin_candidato', 'ambiguas', 'fallidas')) {
    $data.$hoy.$k += $Stats[$k]
  }
  $data | ConvertTo-Json -Depth 4 | Out-File $ResumenFile -Encoding utf8
}

function Show-Reporte {
  if (-not (Test-Path $ResumenFile)) {
    Write-Host 'Todavia no hay mediciones (data\reporte.json no existe).'
    return
  }
  $data = Get-Content $ResumenFile -Raw -Encoding utf8 | ConvertFrom-Json
  $tot = @{ evaluadas = 0; asociadas = 0; sin_candidato = 0; ambiguas = 0 }

  Write-Host 'fecha        ventas  asociadas  sin contacto  ambiguas   tasa'
  foreach ($dia in ($data.PSObject.Properties.Name | Sort-Object)) {
    $d = $data.$dia
    foreach ($k in @($tot.Keys)) { $tot[$k] += $d.$k }
    $tasa = if ($d.evaluadas) { [math]::Round($d.asociadas / $d.evaluadas * 100) } else { 0 }
    '{0}   {1,5}  {2,9}  {3,12}  {4,8}  {5,4}%' -f $dia, $d.evaluadas, $d.asociadas, $d.sin_candidato, $d.ambiguas, $tasa
  }
  $tasa = if ($tot.evaluadas) { [math]::Round($tot.asociadas / $tot.evaluadas * 100) } else { 0 }
  Write-Host ('-' * 60)
  '{0}   {1,5}  {2,9}  {3,12}  {4,8}  {5,4}%' -f 'TOTAL     ', $tot.evaluadas, $tot.asociadas, $tot.sin_candidato, $tot.ambiguas, $tasa
  Write-Host ''
  Write-Host 'Como leerlo:'
  Write-Host '  tasa alta (>60%)      -> el proceso funciona, se puede poner dryRun=false.'
  Write-Host '  muchas "sin contacto" -> no estan pasando el iPad, o lo pasan tarde.'
  Write-Host '  muchas "ambiguas"     -> dos clientes seguidos; achicar la ventana.'
}

# ── Una pasada ───────────────────────────────────────────────────────────────

function Invoke-Pasada {
  param($Cfg)

  $stats = @{ evaluadas = 0; asociadas = 0; sin_candidato = 0; ambiguas = 0; fallidas = 0 }
  $cursor = Get-Cursor
  $desde = [datetime]::Parse($cursor.lastTs)
  $ventas = @(Get-VentasNuevas -Cfg $Cfg -Desde $desde |
      Where-Object { $_.Id -and ($cursor.processedIds -notcontains $_.Id) })

  Write-Log 'info' "Dragonfish: $($ventas.Count) ventas nuevas desde $($desde.ToString('dd/MM HH:mm'))."
  $ahora = Get-Date

  foreach ($venta in $ventas) {
    # Demasiado reciente: el vendedor todavia puede estar cargando el contacto.
    # Se deja para la proxima pasada SIN avanzar el cursor.
    if (($ahora - $venta.Ts).TotalMinutes -lt $Cfg.match.esperaMin) {
      Write-Log 'debug' "Venta $($venta.Comprobante): muy reciente, se evalua mas tarde."
      continue
    }

    $stats.evaluadas++
    try {
      $hasta = $venta.Ts.AddMinutes($Cfg.match.ventanaMin)
      $cand = Get-ContactosEnVentana -Cfg $Cfg -Desde $venta.Ts -Hasta $hasta

      if ($cand.Count -eq 0) {
        $stats.sin_candidato++
        Write-Log 'debug' "Venta $($venta.Comprobante): sin contacto en la ventana."
        Add-Registro -Resultado 'sin_candidato' -Venta $venta -Candidatos @()
      } elseif ($cand.Count -gt 1) {
        $stats.ambiguas++
        $ids = ($cand | ForEach-Object { $_.id }) -join ', '
        Write-Log 'warn' "Venta $($venta.Comprobante): $($cand.Count) contactos en la ventana -> SIN asociar (ids: $ids)."
        Add-Registro -Resultado 'ambigua' -Venta $venta -Candidatos $cand
      } else {
        $c = $cand[0]
        $creado = [DateTimeOffset]::FromUnixTimeSeconds($c.created_at).LocalDateTime
        $min = [math]::Round(($creado - $venta.Ts).TotalMinutes)
        $destino = Resolve-ContactoDestino -Cfg $Cfg -Contacto $c
        if ($Cfg.dryRun) {
          Write-Log 'info' "[DRY_RUN] $($venta.Comprobante) -> contacto $($destino.id) (+$min min)"
        } else {
          [void](Add-NotaKommo -Cfg $Cfg -ContactoId $destino.id -Texto (New-TextoNota -Venta $venta -Minutos $min))
          Write-Log 'info' "$($venta.Comprobante) -> nota en contacto $($destino.id) (+$min min)"
        }
        $stats.asociadas++
        Add-Registro -Resultado 'asociada' -Venta $venta -Candidatos $cand `
          -Extra @{ minutos = $min; contacto_destino = $destino.id; era_duplicado = ($destino.id -ne $c.id) }
      }

      # Asociada o no, queda procesada: si el contacto no aparecio en la
      # ventana, no va a aparecer mas tarde.
      $cursor.processedIds += $venta.Id
      if ($venta.Ts -gt [datetime]::Parse($cursor.lastTs)) {
        $cursor.lastTs = $venta.Ts.ToString('o')
      }
      Save-Cursor $cursor
    } catch {
      # Sin avanzar el cursor: se reintenta en la proxima pasada.
      $stats.fallidas++
      Write-Log 'error' "Fallo la venta $($venta.Comprobante): $($_.Exception.Message)"
    }
  }

  $tasa = if ($stats.evaluadas) { [math]::Round($stats.asociadas / $stats.evaluadas * 100) } else { 0 }
  $extra = if ($Cfg.dryRun) { ' [DRY_RUN: no se escribio en Kommo]' } else { '' }
  Write-Log 'info' ("Pasada: {0} asociadas, {1} sin candidato, {2} ambiguas, {3} con error (tasa {4}%){5}" -f `
      $stats.asociadas, $stats.sin_candidato, $stats.ambiguas, $stats.fallidas, $tasa, $extra)
  Add-Acumulado $stats
}

# ── Main ─────────────────────────────────────────────────────────────────────

if ($Medir) { Show-Reporte; return }

$cfg = Get-Config
Write-Log 'info' "Conector iniciado. dryRun=$($cfg.dryRun)"

if ($Once) {
  Invoke-Pasada -Cfg $cfg
  return
}

while ($true) {
  try {
    Invoke-Pasada -Cfg $cfg
  } catch {
    Write-Log 'error' "Pasada fallida: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds $cfg.intervaloSeg
}
