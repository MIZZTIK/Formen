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
  foreach ($db in @(Get-SqlDatabases -Cfg $c)) {
    if ($db -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      throw "Nombre de base invalido: $db"
    }
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

function Get-SqlDatabases {
  param($Cfg)
  $bases = @()
  $p = $Cfg.sql.PSObject.Properties['databases']
  if ($p -and $p.Value) {
    $bases = @($p.Value)
  } else {
    $bases = @($Cfg.sql.database)
  }
  return @($bases | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -Unique)
}

function Get-SistemaVentaPorBase {
  param([string]$Base)
  if ($Base -match 'BLACK') { return 'Black' }
  if ($Base -match 'FORMEN') { return 'Formen' }
  return $Base
}

function Invoke-Sql {
  param($Cfg, [string]$Query, [hashtable]$Params = @{}, [string]$Database = $null)

  $db = if ($Database) { $Database } else { $Cfg.sql.database }
  $cs = "Server=$($Cfg.sql.server);Database=$db;Connect Timeout=15;"
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
  $ventas = @()
  foreach ($db in @(Get-SqlDatabases -Cfg $Cfg)) {
    $filas = Invoke-Sql -Cfg $Cfg -Database $db -Query $q -Params @{ desde = $Desde }

    $ventas += @($filas | ForEach-Object {
        $codigo = "$($_.CODIGO)".Trim()
        $letra = "$($_.FLETRA)".Trim()
        $pto = "{0:d4}" -f [int]$_.FPTOVEN
        $nro = "{0:d8}" -f [int]$_.FNUMCOMP
        [pscustomobject]@{
          Id          = "${db}:$codigo"
          Codigo      = $codigo
          Base        = $db
          Sistema     = Get-SistemaVentaPorBase $db
          Comprobante = "$letra $pto-$nro".Trim()
          Ts          = [datetime]$_.TS
          Total       = if ($_.FTOTAL -is [DBNull]) { $null } else { [decimal]$_.FTOTAL }
        }
      })
    }
  return @($ventas | Sort-Object Ts)
}

# El reves del apareo: dado un contacto, que ventas pueden reclamarlo.
#
# La ventana de una venta mira hacia adelante buscando contactos; esta mira
# hacia atras buscando ventas. Hace falta por el cliente que NO se anota: no
# deja ningun rastro, pero su venta sale a buscar candidato igual y se queda
# con el contacto del cliente SIGUIENTE, que es el unico en su ventana. La
# regla de ambiguedad no lo salva (hay un solo candidato, no dos) y la nota
# termina en la ficha equivocada sin que nada lo delate.
#
# Se consulta la base y no las ventas de esta pasada porque dos ventas
# seguidas caen en pasadas distintas: con esperaMin, la de las 14:32 se evalua
# a las 14:42 y la de las 14:38 a las 14:48. Preguntandole a Dragonfish, las
# dos ven lo mismo y las dos se abstienen.
function Get-VentasQueReclaman {
  param($Cfg, [datetime]$Creado)

  $ts = "CAST(CONVERT(varchar(10),FALTAFW,120)+' '+HALTAFW AS datetime)"
  $tipos = ($Cfg.tiposVenta | ForEach-Object { [int]$_ }) -join ','
  $filtroTipo = if ($tipos) { " AND FACTTIPO IN ($tipos)" } else { '' }

  # Una venta reclama al contacto si el contacto cae en SU ventana, o sea si
  # la venta ocurrio entre (creado - ventana) y creado.
  $q = @"
SELECT CODIGO
FROM [$($Cfg.sql.schema)].[COMPROBANTEV]
WHERE ANULADO = 0 $filtroTipo AND $ts BETWEEN @desde AND @hasta
"@
  $ids = @()
  foreach ($db in @(Get-SqlDatabases -Cfg $Cfg)) {
    $filas = Invoke-Sql -Cfg $Cfg -Database $db -Query $q -Params @{
      desde = $Creado.AddMinutes(-1 * $Cfg.match.ventanaMin)
      hasta = $Creado
    }
    $ids += @($filas | ForEach-Object { "${db}:$($_.CODIGO)".Trim() })
  }
  return @($ids)
}

function ConvertTo-MontoTexto {
  param($Monto)
  if ($null -eq $Monto -or $Monto -is [DBNull]) { return 's/d' }
  return '$ ' + ('{0:N0}' -f [decimal]$Monto)
}

function Get-NombreMedioPago {
  param([string]$Codigo)
  $c = "$Codigo".Trim()
  $map = @{
    '0'   = 'PESOS'
    'VI'  = 'VISA'
    'NA'  = 'NARANJA'
    'TR'  = 'Transferencia Bancaria'
    'EL'  = 'ELECTRON'
    'MAE' = 'MAESTRO'
  }
  if ($map.ContainsKey($c)) { return $map[$c] }
  if ($c) { return $c }
  return 'Medio de pago s/d'
}

function Get-DetalleVenta {
  param($Cfg, $Venta)

  $qItems = @"
SELECT TOP (20)
  NROITEM,
  LTRIM(RTRIM(ISNULL(FART,''))) AS articulo,
  LTRIM(RTRIM(ISNULL(FTXT,''))) AS descripcion,
  FCANT AS cantidad,
  FPRECIO AS precio_unitario,
  MNTPTOT AS total_item,
  LTRIM(RTRIM(ISNULL(TALLE,''))) AS talle,
  LTRIM(RTRIM(ISNULL(FCOLTXT,''))) AS color
FROM [$($Cfg.sql.schema)].[COMPROBANTEVDET]
WHERE CODIGO = @id
ORDER BY NROITEM
"@
  $items = @(Invoke-Sql -Cfg $Cfg -Database $Venta.Base -Query $qItems -Params @{ id = $Venta.Codigo } | ForEach-Object {
      [pscustomobject]@{
        articulo    = "$($_.articulo)".Trim()
        descripcion = "$($_.descripcion)".Trim()
        cantidad    = if ($_.cantidad -is [DBNull]) { $null } else { [decimal]$_.cantidad }
        total       = if ($_.total_item -is [DBNull]) { $null } else { [decimal]$_.total_item }
        talle       = "$($_.talle)".Trim()
        color       = "$($_.color)".Trim()
      }
    })

  $qPagos = @"
SELECT
  LTRIM(RTRIM(ISNULL(VALOR,''))) AS codigo,
  SUM(MONTO) AS monto
FROM [$($Cfg.sql.schema)].[CUPONES]
WHERE COMP = @id
GROUP BY LTRIM(RTRIM(ISNULL(VALOR,'')))
ORDER BY SUM(MONTO) DESC
"@
  $pagos = @(Invoke-Sql -Cfg $Cfg -Database $Venta.Base -Query $qPagos -Params @{ id = $Venta.Codigo } | ForEach-Object {
      $codigo = "$($_.codigo)".Trim()
      [pscustomobject]@{
        codigo = $codigo
        nombre = Get-NombreMedioPago $codigo
        monto  = if ($_.monto -is [DBNull]) { $null } else { [decimal]$_.monto }
      }
    })

  return [pscustomobject]@{
    items = $items
    pagos = $pagos
  }
}

# ── Kommo ────────────────────────────────────────────────────────────────────

function Invoke-Kommo {
  param($Cfg, [string]$Metodo, [string]$Ruta, $Cuerpo = $null)

  $url = "https://$($Cfg.kommo.subdominio).kommo.com$Ruta"
  $headers = @{ Authorization = "Bearer $($Cfg.kommo.token)"; Accept = 'application/json' }
  # Ojo: no usar $args, que es una variable automatica de PowerShell.
  $req = @{ Uri = $url; Method = $Metodo; Headers = $headers; TimeoutSec = 30 }
  if ($Cuerpo) {
    $req.Body = ($Cuerpo | ConvertTo-Json -Depth 6 -Compress)
    $req.ContentType = 'application/json'
  }
  try {
    return Invoke-RestMethod @req
  } catch {
    $code = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 'sin_codigo' }
    $detalle = ''
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $detalle = $reader.ReadToEnd()
      }
    } catch {}
    if ($code -eq 204) { return $null }   # sin resultados
    $msg = "Kommo $Metodo $Ruta -> $code : $($_.Exception.Message)"
    if ($detalle) { $msg += " : $detalle" }
    throw $msg
  }
}

# ¿Este contacto se cargo en el mostrador?
#
# Dos formas, y las dos tienen que seguir valiendo durante la transicion:
#   - Etiqueta (hoy "local"): la pone el formulario web. Es la buena, esta
#     puesta a proposito. El formulario crea los contactos con created_by = 0,
#     asi que sin esto el conector se queda ciego el dia que empiecen a usarlo.
#   - created_by del usuario FormenAR: como se cargaba antes, a mano desde la
#     app. Se puede sacar cuando ya nadie cargue asi.
function Test-ContactoDelLocal {
  param($Cfg, $Contacto)
  if ($Cfg.match.etiqueta) {
    foreach ($t in @($Contacto._embedded.tags)) {
      if ($t.name -eq $Cfg.match.etiqueta) { return $true }
    }
  }
  return ($Contacto.created_by -eq $Cfg.kommo.ipadUserId)
}

# Contactos cargados en el mostrador entre dos momentos.
function Get-ContactosEnVentana {
  param($Cfg, [datetime]$Desde, [datetime]$Hasta)

  $from = [DateTimeOffset]::new($Desde).ToUnixTimeSeconds()
  $to = [DateTimeOffset]::new($Hasta).ToUnixTimeSeconds()
  $ruta = "/api/v4/contacts?filter[created_at][from]=$from&filter[created_at][to]=$to&limit=250"
  $r = Invoke-Kommo -Cfg $Cfg -Metodo 'GET' -Ruta $ruta
  if (-not $r) { return @() }

  # La consulta ya devuelve _embedded.tags, no hace falta pedir cada contacto.
  return @(@($r._embedded.contacts) | Where-Object { Test-ContactoDelLocal -Cfg $Cfg -Contacto $_ })
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

function ConvertTo-Ultimos4 {
  param([string]$Texto)
  $d = [regex]::Replace("$Texto", '\D', '')
  if ($d.Length -ge 4) { return $d.Substring($d.Length - 4) }
  return $null
}

function ConvertTo-SistemaVentaNormalizado {
  param([string]$Texto)
  $t = "$Texto".Trim().ToLowerInvariant()
  if ($t -eq 'black') { return 'black' }
  if ($t -eq 'formen') { return 'formen' }
  return $t
}

function Get-Ultimos4Comprobante {
  param($Venta)
  return ConvertTo-Ultimos4 $Venta.Comprobante
}

function Get-ComprobanteContacto {
  param($Cfg, $Contacto)

  $fieldId = if ($Cfg.match.comprobanteUltimos4FieldId) { [int64]$Cfg.match.comprobanteUltimos4FieldId } else { $null }
  $fieldName = if ($Cfg.match.comprobanteUltimos4FieldName) { "$($Cfg.match.comprobanteUltimos4FieldName)" } else { $null }
  if (-not $fieldId -and -not $fieldName) { return $null }

  foreach ($f in @($Contacto.custom_fields_values)) {
    $porId = ($fieldId -and [int64]$f.field_id -eq $fieldId)
    $porNombre = ($fieldName -and "$($f.field_name)" -eq $fieldName)
    if ($porId -or $porNombre) {
      foreach ($v in @($f.values)) {
        $ultimos4 = ConvertTo-Ultimos4 "$($v.value)"
        if ($ultimos4) { return $ultimos4 }
      }
    }
  }
  return $null
}

function Get-SistemaVentaContacto {
  param($Cfg, $Contacto)

  $fieldId = if ($Cfg.match.sistemaVentaFieldId) { [int64]$Cfg.match.sistemaVentaFieldId } else { $null }
  $fieldName = if ($Cfg.match.sistemaVentaFieldName) { "$($Cfg.match.sistemaVentaFieldName)" } else { $null }
  if (-not $fieldId -and -not $fieldName) { return $null }

  foreach ($f in @($Contacto.custom_fields_values)) {
    $porId = ($fieldId -and [int64]$f.field_id -eq $fieldId)
    $porNombre = ($fieldName -and "$($f.field_name)" -eq $fieldName)
    if ($porId -or $porNombre) {
      foreach ($v in @($f.values)) {
        $sistema = ConvertTo-SistemaVentaNormalizado "$($v.value)"
        if ($sistema) { return $sistema }
      }
    }
  }
  return $null
}

function Select-CandidatosParaVenta {
  param($Cfg, $Venta, $Candidatos)

  $esperado = Get-Ultimos4Comprobante $Venta
  $campoActivo = ($Cfg.match.comprobanteUltimos4FieldId -or $Cfg.match.comprobanteUltimos4FieldName)
  $sistemaEsperado = ConvertTo-SistemaVentaNormalizado $Venta.Sistema
  $sistemaActivo = ($Cfg.match.sistemaVentaFieldId -or $Cfg.match.sistemaVentaFieldName)
  if (-not $campoActivo -or -not $esperado) {
    return [pscustomobject]@{
      candidatos  = @($Candidatos)
      modo        = 'tiempo'
      esperado    = $esperado
      descartados = @()
      sinCampo    = @()
    }
  }

  $exactos = @()
  $sinCampo = @()
  $descartados = @()
  foreach ($c in @($Candidatos)) {
    $informado = Get-ComprobanteContacto -Cfg $Cfg -Contacto $c
    if (-not $informado) {
      $sinCampo += $c
    } elseif ($informado -eq $esperado) {
      if ($sistemaActivo -and $sistemaEsperado) {
        $sistemaInformado = Get-SistemaVentaContacto -Cfg $Cfg -Contacto $c
        if (-not $sistemaInformado) {
          $sinCampo += $c
          continue
        }
        if ($sistemaInformado -ne $sistemaEsperado) {
          $descartados += [pscustomobject]@{ id = $c.id; informado = $informado; sistema = $sistemaInformado }
          continue
        }
      }
      $exactos += $c
    } else {
      $descartados += [pscustomobject]@{ id = $c.id; informado = $informado }
    }
  }

  if ($exactos.Count -gt 0) {
    return [pscustomobject]@{
      candidatos  = @($exactos)
      modo        = 'comprobante'
      esperado    = $esperado
      descartados = @($descartados)
      sinCampo    = @($sinCampo)
    }
  }

  $fallbackTemporal = Get-PropValor -Objeto $Cfg.match -Nombre 'permitirFallbackTemporalSinComprobante'
  if (-not $fallbackTemporal) {
    return [pscustomobject]@{
      candidatos  = @()
      modo        = 'comprobante'
      esperado    = $esperado
      descartados = @($descartados)
      sinCampo    = @($sinCampo)
    }
  }

  return [pscustomobject]@{
    candidatos  = @($sinCampo)
    modo        = 'tiempo'
    esperado    = $esperado
    descartados = @($descartados)
    sinCampo    = @($sinCampo)
  }
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
      -not (Test-ContactoDelLocal -Cfg $Cfg -Contacto $_) -and
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

function Get-PropValor {
  param($Objeto, [string]$Nombre)
  if (-not $Objeto) { return $null }
  $p = $Objeto.PSObject.Properties[$Nombre]
  if ($p) { return $p.Value }
  return $null
}

$script:CamposContactoKommo = $null

function Get-CamposContactoKommo {
  param($Cfg)
  if ($script:CamposContactoKommo) { return $script:CamposContactoKommo }
  $r = Invoke-Kommo -Cfg $Cfg -Metodo 'GET' -Ruta '/api/v4/contacts/custom_fields?limit=250'
  $script:CamposContactoKommo = @($r._embedded.custom_fields)
  return $script:CamposContactoKommo
}

function Resolve-CampoContactoKommo {
  param($Cfg, [Nullable[int64]]$FieldId, [string]$FieldName)
  $campos = Get-CamposContactoKommo -Cfg $Cfg
  if ($FieldId) {
    $porId = @($campos | Where-Object { [int64]$_.id -eq [int64]$FieldId } | Select-Object -First 1)[0]
    if ($porId) { return $porId }
    return [pscustomobject]@{ id = [int64]$FieldId; name = $FieldName; type = '' }
  }
  if (-not $FieldName) { return $null }
  return @($campos | Where-Object { "$($_.name)" -eq $FieldName } | Select-Object -First 1)[0]
}

function ConvertTo-ValorCampoKommo {
  param($Campo, $Valor)
  if ($null -eq $Valor -or $Valor -is [DBNull]) { return $null }
  $tipo = "$($Campo.type)"
  if ($tipo -match 'date') {
    if ($Valor -is [datetime]) {
      return [DateTimeOffset]::new($Valor).ToUnixTimeSeconds()
    }
    return [int64]$Valor
  }
  if ($tipo -match 'numeric|monetary') {
    return [decimal]$Valor
  }
  if ($Valor -is [datetime]) { return $Valor.ToString('dd/MM/yyyy HH:mm') }
  return "$Valor"
}

function Join-ProductosResumen {
  param($Detalle)
  if (-not $Detalle -or $Detalle.items.Count -eq 0) { return '' }
  $partes = @()
  foreach ($it in @($Detalle.items | Select-Object -First 8)) {
    $cant = if ($null -ne $it.cantidad) { ('{0:N0}' -f $it.cantidad) } else { 's/cant' }
    $nombre = if ($it.descripcion) { $it.descripcion } else { $it.articulo }
    $extra = if ($it.talle) { " talle $($it.talle)" } else { '' }
    $partes += "$nombre x$cant$extra"
  }
  if ($Detalle.items.Count -gt 8) { $partes += "... y $($Detalle.items.Count - 8) mas" }
  return $partes -join '; '
}

function Join-PagosResumen {
  param($Detalle)
  if (-not $Detalle -or $Detalle.pagos.Count -eq 0) { return '' }
  return (@($Detalle.pagos) | ForEach-Object { "$($_.nombre): $(ConvertTo-MontoTexto $_.monto)" }) -join '; '
}

function Get-DefinicionesCamposCompra {
  param($Cfg, $Venta, $Detalle)
  $c = $Cfg.camposCompra
  if (-not $c) { return @() }

  $defs = @(
    @{ clave = 'ultimaCompraFecha'; id = 'ultimaCompraFechaFieldId'; nombre = 'ultimaCompraFechaFieldName'; valor = $Venta.Ts },
    @{ clave = 'ultimoComprobante'; id = 'ultimoComprobanteFieldId'; nombre = 'ultimoComprobanteFieldName'; valor = $Venta.Comprobante },
    @{ clave = 'ultimaCompraTotal'; id = 'ultimaCompraTotalFieldId'; nombre = 'ultimaCompraTotalFieldName'; valor = $Venta.Total },
    @{ clave = 'ultimos4Comprobante'; id = 'ultimos4ComprobanteFieldId'; nombre = 'ultimos4ComprobanteFieldName'; valor = (Get-Ultimos4Comprobante $Venta) },
    @{ clave = 'ultimaCompraProductos'; id = 'ultimaCompraProductosFieldId'; nombre = 'ultimaCompraProductosFieldName'; valor = (Join-ProductosResumen $Detalle) },
    @{ clave = 'ultimaCompraPagos'; id = 'ultimaCompraPagosFieldId'; nombre = 'ultimaCompraPagosFieldName'; valor = (Join-PagosResumen $Detalle) }
  )

  $activos = @()
  foreach ($d in $defs) {
    $fieldId = Get-PropValor -Objeto $c -Nombre $d.id
    $fieldName = Get-PropValor -Objeto $c -Nombre $d.nombre
    if ($fieldId -or $fieldName) {
      $activos += [pscustomobject]@{
        clave     = $d.clave
        fieldId   = if ($fieldId) { [int64]$fieldId } else { $null }
        fieldName = if ($fieldName) { "$fieldName" } else { '' }
        valor     = $d.valor
      }
    }
  }
  return $activos
}

function Update-CamposCompraKommo {
  param($Cfg, [int64]$ContactoId, $Venta, $Detalle)

  $defs = @(Get-DefinicionesCamposCompra -Cfg $Cfg -Venta $Venta -Detalle $Detalle)
  if ($defs.Count -eq 0) { return }

  $customFields = @()
  foreach ($d in $defs) {
    $campo = Resolve-CampoContactoKommo -Cfg $Cfg -FieldId $d.fieldId -FieldName $d.fieldName
    if (-not $campo) {
      Write-Log 'warn' "Campo Kommo no encontrado para $($d.clave): $($d.fieldName)"
      continue
    }

    $valor = ConvertTo-ValorCampoKommo -Campo $campo -Valor $d.valor
    if ($null -eq $valor -or "$valor" -eq '') { continue }

    $customFields += @{
      field_id = [int64]$campo.id
      values   = @(@{ value = $valor })
    }
  }

  if ($customFields.Count -eq 0) { return }
  $cuerpo = @{ custom_fields_values = $customFields }
  [void](Invoke-Kommo -Cfg $Cfg -Metodo 'PATCH' -Ruta "/api/v4/contacts/$ContactoId" -Cuerpo $cuerpo)
}

function New-TextoNota {
  param($Venta, [int]$Minutos, $Detalle = $null)
  $total = ConvertTo-MontoTexto $Venta.Total
  $lineas = @(
    'Compra en el local',
    "Sistema: $($Venta.Sistema)",
    "Comprobante: $($Venta.Comprobante)",
    "Fecha: $($Venta.Ts.ToString('dd/MM/yyyy HH:mm'))",
    "Total: $total"
  )

  if ($Detalle -and $Detalle.items.Count -gt 0) {
    $lineas += ''
    $lineas += 'Productos:'
    foreach ($it in @($Detalle.items | Select-Object -First 10)) {
      $cant = if ($null -ne $it.cantidad) { ('{0:N0}' -f $it.cantidad) } else { 's/cant' }
      $nombre = if ($it.descripcion) { $it.descripcion } else { $it.articulo }
      $extra = @()
      if ($it.talle) { $extra += "talle $($it.talle)" }
      if ($it.color) { $extra += "color $($it.color)" }
      $sufijo = if ($extra.Count -gt 0) { ' (' + ($extra -join ', ') + ')' } else { '' }
      $lineas += "- $nombre x$cant$sufijo - $(ConvertTo-MontoTexto $it.total)"
    }
    if ($Detalle.items.Count -gt 10) {
      $lineas += "- ... y $($Detalle.items.Count - 10) item(s) mas"
    }
  }

  if ($Detalle -and $Detalle.pagos.Count -gt 0) {
    $lineas += ''
    $lineas += 'Pagos:'
    foreach ($p in @($Detalle.pagos)) {
      $lineas += "- $($p.nombre): $(ConvertTo-MontoTexto $p.monto)"
    }
  }

  $lineas += ''
  $lineas += "(asociado automaticamente: el contacto se cargo $Minutos min despues de la venta)"
  return Remove-Emojis ($lineas -join "`n")
}

# ── Cursor y reporte ─────────────────────────────────────────────────────────

function Get-Cursor {
  if (Test-Path $CursorFile) {
    try {
      return Get-Content $CursorFile -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
      # Cursor cortado a la mitad (corte de luz durante la escritura). Volver al
      # comienzo del dia significa REPROCESAR las ventas de hoy y duplicar notas,
      # asi que tiene que quedar gritado en el log.
      Write-Log 'error' "cursor.json ilegible ($($_.Exception.Message)). Se reinicia desde hoy 00:00: puede duplicar notas del dia."
    }
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
  # Escritura atomica: primero a un temporal, despues reemplazo. Si se corta la
  # luz en el medio queda el archivo viejo entero, nunca uno cortado por la
  # mitad. Sin esto, un corte a destiempo hace reprocesar el dia y duplicar
  # las notas en las fichas.
  $tmp = "$CursorFile.tmp"
  $Cursor | ConvertTo-Json -Depth 4 | Out-File $tmp -Encoding utf8
  Move-Item -Path $tmp -Destination $CursorFile -Force
}

# ── Vigilancia: que grite si se cae ──────────────────────────────────────────
#
# Esto corre solo en la PC del local, sin nadie que lo mire. Si vence el token,
# si SQL deja de responder o si alguien cierra sesion, el log acumula errores en
# una carpeta que nadie abre. Avisamos por Telegram.
#
# Reglas anti-ruido: avisa recien despues de N pasadas fallidas seguidas, no
# repite hasta que se recupere, y avisa tambien la recuperacion.
#
# SOLO ENVIA. Nunca getUpdates ni setWebhook: el mismo token lo usa otro bot
# haciendo polling y se romperia en silencio.
function Send-Telegram {
  param($Cfg, [string]$Texto)
  if (-not $Cfg.avisos.telegramToken -or -not $Cfg.avisos.telegramChatId) { return }
  try {
    $url = "https://api.telegram.org/bot$($Cfg.avisos.telegramToken)/sendMessage"
    $body = @{ chat_id = "$($Cfg.avisos.telegramChatId)"; text = $Texto } | ConvertTo-Json -Compress
    [void](Invoke-RestMethod -Uri $url -Method POST -Body $body `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 15)
  } catch {
    # Un aviso que falla no puede tumbar la pasada.
    Write-Log 'warn' "No se pudo avisar por Telegram: $($_.Exception.Message)"
  }
}

function Invoke-PasadaVigilada {
  param($Cfg)

  $EstadoFile = Join-Path $DataDir 'estado.json'
  $st = if (Test-Path $EstadoFile) {
    try { Get-Content $EstadoFile -Raw -Encoding utf8 | ConvertFrom-Json } catch { $null }
  } else { $null }
  if (-not $st) { $st = [pscustomobject]@{ fallosSeguidos = 0; avisado = $false } }

  $umbral = if ($Cfg.avisos.fallosSeguidosParaAvisar) { [int]$Cfg.avisos.fallosSeguidosParaAvisar } else { 3 }
  $maquina = "$env:COMPUTERNAME"

  try {
    Invoke-Pasada -Cfg $Cfg
    if ($st.avisado) {
      Send-Telegram -Cfg $Cfg -Texto "Formen: el conector Dragonfish-Kommo volvio a funcionar ($maquina)."
      Write-Log 'info' 'Recuperado: se aviso por Telegram.'
    }
    $st.fallosSeguidos = 0
    $st.avisado = $false
  } catch {
    $st.fallosSeguidos = [int]$st.fallosSeguidos + 1
    Write-Log 'error' "Pasada fallida ($($st.fallosSeguidos) seguidas): $($_.Exception.Message)"
    if ($st.fallosSeguidos -ge $umbral -and -not $st.avisado) {
      Send-Telegram -Cfg $Cfg -Texto ("Formen: el conector Dragonfish-Kommo esta fallando en $maquina. " +
        "$($st.fallosSeguidos) pasadas seguidas con error. Las compras del local dejaron de aparecer en las fichas. " +
        "Ultimo error: $($_.Exception.Message)")
      $st.avisado = $true
    }
  }

  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  $st | ConvertTo-Json -Depth 3 | Out-File $EstadoFile -Encoding utf8
}

function Add-Registro {
  param([string]$Resultado, $Venta, $Candidatos, $Extra = @{})
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  $o = [ordered]@{
    ts          = (Get-Date).ToString('o')
    resultado   = $Resultado
    venta       = $Venta.Comprobante
    sistema     = $Venta.Sistema
    base        = $Venta.Base
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
  Write-Host '  muchas "ambiguas"     -> dos clientes seguidos, o uno que no se anoto y'
  Write-Host '                           dejo su venta apuntando al de al lado. Achicar la'
  Write-Host '                           ventana, o pedir que carguen tambien al que se niega.'
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
      $todos = Get-ContactosEnVentana -Cfg $Cfg -Desde $venta.Ts -Hasta $hasta
      $sel = Select-CandidatosParaVenta -Cfg $Cfg -Venta $venta -Candidatos $todos
      $cand = @($sel.candidatos)

      if ($cand.Count -eq 0) {
        $stats.sin_candidato++
        if ($todos.Count -gt 0 -and ($sel.descartados.Count -gt 0 -or $sel.sinCampo.Count -gt 0)) {
          Write-Log 'debug' "Venta $($venta.Comprobante): contactos en ventana, pero ninguno con comprobante $($sel.esperado)."
          Add-Registro -Resultado 'sin_candidato' -Venta $venta -Candidatos $todos `
            -Extra @{ motivo = 'comprobante_no_coincide'; comprobante_ultimos4 = $sel.esperado; descartados = $sel.descartados; sin_campo = @($sel.sinCampo | ForEach-Object { $_.id }) }
        } else {
          Write-Log 'debug' "Venta $($venta.Comprobante): sin contacto en la ventana."
          Add-Registro -Resultado 'sin_candidato' -Venta $venta -Candidatos @()
        }
      } elseif ($cand.Count -gt 1) {
        $stats.ambiguas++
        $ids = ($cand | ForEach-Object { $_.id }) -join ', '
        if ($sel.modo -eq 'comprobante') {
          Write-Log 'warn' "Venta $($venta.Comprobante): $($cand.Count) contactos con comprobante $($sel.esperado) -> SIN asociar (ids: $ids)."
          Add-Registro -Resultado 'ambigua' -Venta $venta -Candidatos $cand `
            -Extra @{ motivo = 'comprobante_duplicado'; comprobante_ultimos4 = $sel.esperado }
        } else {
          Write-Log 'warn' "Venta $($venta.Comprobante): $($cand.Count) contactos en la ventana -> SIN asociar (ids: $ids)."
          Add-Registro -Resultado 'ambigua' -Venta $venta -Candidatos $cand
        }
      } else {
        $c = $cand[0]
        $creado = [DateTimeOffset]::FromUnixTimeSeconds($c.created_at).LocalDateTime
        $min = [math]::Round(($creado - $venta.Ts).TotalMinutes)

        # Candidato unico, pero puede no ser nuestro: si otra venta tambien
        # llega a este contacto, no hay forma de saber cual de las dos es.
        $reclaman = if ($sel.modo -eq 'comprobante') { @($venta.Id) } else { Get-VentasQueReclaman -Cfg $Cfg -Creado $creado }
        if ($reclaman.Count -gt 1) {
          $stats.ambiguas++
          Write-Log 'warn' ("Venta $($venta.Comprobante): el contacto $($c.id) lo reclaman " +
            "$($reclaman.Count) ventas ($($reclaman -join ', ')) -> SIN asociar.")
          Add-Registro -Resultado 'ambigua' -Venta $venta -Candidatos $cand `
            -Extra @{ motivo = 'contacto_compartido'; minutos = $min; ventas_en_disputa = $reclaman }
        } else {
          $destino = Resolve-ContactoDestino -Cfg $Cfg -Contacto $c
          if ($Cfg.dryRun) {
            Write-Log 'info' "[DRY_RUN] $($venta.Comprobante) -> contacto $($destino.id) ($($sel.modo), +$min min)"
          } else {
            $detalle = $null
            try {
              $detalle = Get-DetalleVenta -Cfg $Cfg -Venta $venta
            } catch {
              Write-Log 'warn' "No se pudo leer detalle de $($venta.Comprobante): $($_.Exception.Message)"
            }
            [void](Add-NotaKommo -Cfg $Cfg -ContactoId $destino.id -Texto (New-TextoNota -Venta $venta -Minutos $min -Detalle $detalle))
            try {
              Update-CamposCompraKommo -Cfg $Cfg -ContactoId $destino.id -Venta $venta -Detalle $detalle
            } catch {
              Write-Log 'warn' "No se pudieron actualizar campos de compra en contacto $($destino.id): $($_.Exception.Message)"
            }
            Write-Log 'info' "$($venta.Comprobante) -> nota en contacto $($destino.id) ($($sel.modo), +$min min)"
          }
          $stats.asociadas++
          Add-Registro -Resultado 'asociada' -Venta $venta -Candidatos $cand `
            -Extra @{ minutos = $min; contacto_destino = $destino.id; era_duplicado = ($destino.id -ne $c.id); modo_apareo = $sel.modo; comprobante_ultimos4 = $sel.esperado }
        }
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
  Invoke-PasadaVigilada -Cfg $cfg
  return
}

while ($true) {
  Invoke-PasadaVigilada -Cfg $cfg
  Start-Sleep -Seconds $cfg.intervaloSeg
}
