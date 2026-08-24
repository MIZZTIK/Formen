# Exploracion de solo lectura sobre caja, recibos y comprobantes de Dragonfish.
#
# Objetivo:
#   1. Encontrar que diferencia "Black" de "Formen" dentro de la base.
#   2. Ubicar de donde salen los recibos / pagos asociados a una venta.
#   3. Ver si esa informacion permite vincular mejor Kommo con Dragonfish.
#
# NO escribe nada. Solo SELECT sobre SQL Server.
#
#   powershell -ExecutionPolicy Bypass -File .\explorar-recibos.ps1

$ErrorActionPreference = 'Stop'
$cfgPath = Join-Path $PSScriptRoot 'conector.config.json'
if (-not (Test-Path $cfgPath)) { throw "No encuentro $cfgPath" }
$Cfg = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json

function Invoke-Sql {
  param([string]$Query)
  $cs = "Server=$($Cfg.sql.server);Database=$($Cfg.sql.database);Connect Timeout=15;"
  if ($Cfg.sql.user) { $cs += "User Id=$($Cfg.sql.user);Password=$($Cfg.sql.password);" }
  else { $cs += 'Integrated Security=SSPI;' }
  $con = New-Object System.Data.SqlClient.SqlConnection $cs
  try {
    $con.Open()
    $cmd = $con.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 60
    $ad = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable
    [void]$ad.Fill($t)
    return $t
  } finally { $con.Close() }
}

function Show-Titulo {
  param([string]$T)
  Write-Host ''
  Write-Host "=== $T ===" -ForegroundColor Cyan
}

function Show-Tabla {
  param($Rows)
  if (-not $Rows -or $Rows.Rows.Count -eq 0) { Write-Host '  (sin filas)'; return }
  $Rows | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
}

function Get-Columnas {
  param([string]$Tabla)
  $q = @"
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '$($Cfg.sql.schema)' AND TABLE_NAME = '$Tabla'
ORDER BY ORDINAL_POSITION
"@
  return @((Invoke-Sql $q) | ForEach-Object { "$($_.COLUMN_NAME)" })
}

function Quote-Col {
  param([string]$Col)
  return '[' + $Col.Replace(']', ']]') + ']'
}

function Select-ColumnasInteresantes {
  param([string[]]$Columnas)
  $rx = 'COD|COMP|FACT|REC|CAJ|BAN|BLACK|FORMEN|VAL|PAG|COBR|CUP|TARJ|EFEC|IMP|TOTAL|MON|FECH|FEC|HORA|LETRA|PTO|NUM|CLIENT|PERSON|CUIT|EMAIL|NOM|DESC|TIPO|SUC|ORIG|CTA|CUENTA|TALON'
  $sel = @($Columnas | Where-Object { $_ -match $rx } | Select-Object -First 28)
  if ($sel.Count -eq 0) { $sel = @($Columnas | Select-Object -First 16) }
  return $sel
}

function Show-Muestra {
  param([string]$Tabla, [int]$Top = 10)
  $cols = Get-Columnas $Tabla
  if ($cols.Count -eq 0) {
    Write-Host "  (no existe $Tabla)"
    return
  }
  $sel = Select-ColumnasInteresantes $cols
  $select = ($sel | ForEach-Object { Quote-Col $_ }) -join ', '
  $order = if ($cols -contains 'FALTAFW') {
    ' ORDER BY [FALTAFW] DESC'
  } elseif ($cols -contains 'FECHA') {
    ' ORDER BY [FECHA] DESC'
  } elseif ($cols -contains 'FFCH') {
    ' ORDER BY [FFCH] DESC'
  } else { '' }
  $q = "SELECT TOP ($Top) $select FROM [$($Cfg.sql.schema)].[$Tabla]$order"
  Show-Titulo "Muestra $Tabla (columnas candidatas)"
  Write-Host "Columnas mostradas: $($sel -join ', ')"
  Show-Tabla (Invoke-Sql $q)
}

$esquema = $Cfg.sql.schema

Show-Titulo '1. Tablas que suenan a caja, banco, recibo, pago, cupon o comprobante'
$q1 = @"
SELECT t.TABLE_NAME, SUM(p.rows) AS filas
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN sys.tables st ON st.name = t.TABLE_NAME AND SCHEMA_NAME(st.schema_id) = t.TABLE_SCHEMA
LEFT JOIN sys.partitions p ON p.object_id = st.object_id AND p.index_id IN (0,1)
WHERE t.TABLE_SCHEMA = '$esquema'
  AND (t.TABLE_NAME LIKE '%BAN%' OR t.TABLE_NAME LIKE '%BLACK%' OR t.TABLE_NAME LIKE '%FORMEN%'
    OR t.TABLE_NAME LIKE '%REC%' OR t.TABLE_NAME LIKE '%COBR%' OR t.TABLE_NAME LIKE '%PAG%'
    OR t.TABLE_NAME LIKE '%CAJA%' OR t.TABLE_NAME LIKE '%CUPON%' OR t.TABLE_NAME LIKE '%TARJ%'
    OR t.TABLE_NAME LIKE '%VAL%' OR t.TABLE_NAME LIKE '%COMP%' OR t.TABLE_NAME LIKE '%FACT%')
GROUP BY t.TABLE_NAME
ORDER BY SUM(p.rows) DESC, t.TABLE_NAME
"@
Show-Tabla (Invoke-Sql $q1)

Show-Titulo '2. Columnas que contienen Black/Formen/Banco/Caja/Recibo/Pago'
$q2 = @"
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS largo
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '$esquema'
  AND (COLUMN_NAME LIKE '%BAN%' OR COLUMN_NAME LIKE '%BLACK%' OR COLUMN_NAME LIKE '%FORMEN%'
    OR COLUMN_NAME LIKE '%REC%' OR COLUMN_NAME LIKE '%COBR%' OR COLUMN_NAME LIKE '%PAG%'
    OR COLUMN_NAME LIKE '%CAJA%' OR COLUMN_NAME LIKE '%CUPON%' OR COLUMN_NAME LIKE '%TARJ%'
    OR COLUMN_NAME LIKE '%VAL%' OR COLUMN_NAME LIKE '%COMP%' OR COLUMN_NAME LIKE '%FACT%'
    OR COLUMN_NAME LIKE '%PTO%' OR COLUMN_NAME LIKE '%SUC%' OR COLUMN_NAME LIKE '%TALON%')
ORDER BY TABLE_NAME, COLUMN_NAME
"@
Show-Tabla (Invoke-Sql $q2)

Show-Titulo '3. Ventas ultimos 90 dias agrupadas por tipo, letra y punto de venta'
$q3 = @"
SELECT
  FACTTIPO,
  LTRIM(RTRIM(ISNULL(FLETRA,''))) AS letra,
  FPTOVEN AS punto_venta,
  COUNT(*) AS ventas,
  MIN(FALTAFW) AS desde,
  MAX(FALTAFW) AS hasta,
  MIN(FNUMCOMP) AS primer_numero,
  MAX(FNUMCOMP) AS ultimo_numero,
  SUM(FTOTAL) AS total
FROM [$esquema].[COMPROBANTEV]
WHERE ANULADO = 0 AND FALTAFW >= DATEADD(day, -90, CAST(GETDATE() AS date))
GROUP BY FACTTIPO, LTRIM(RTRIM(ISNULL(FLETRA,''))), FPTOVEN
ORDER BY ventas DESC
"@
Show-Tabla (Invoke-Sql $q3)

Show-Titulo '4. Ultimas 30 ventas con datos de comprobante'
$q4 = @"
SELECT TOP 30
  CODIGO, FALTAFW, HALTAFW, FFCH, FACTTIPO, FLETRA, FPTOVEN, FNUMCOMP,
  FCLIENTE, FPERSON, FCUIT, EMAIL, FTOTAL
FROM [$esquema].[COMPROBANTEV]
WHERE ANULADO = 0
ORDER BY FALTAFW DESC, HALTAFW DESC
"@
Show-Tabla (Invoke-Sql $q4)

Show-Titulo '5. Columnas de tablas clave'
$tablasClave = @('COMPROBANTEV','COMPROBANTEVDET','MOVCAJA','VAL','CUPONES','COMB','COMPCAJADET','COMCAJ','ADT_COMB','IMPUESTOSV')
foreach ($tabla in $tablasClave) {
  $cols = Get-Columnas $tabla
  if ($cols.Count -gt 0) { Write-Host "${tabla}: $($cols -join ', ')" }
  else { Write-Host "${tabla}: (no existe)" }
}

foreach ($tabla in $tablasClave) {
  Show-Muestra -Tabla $tabla -Top 10
}

Write-Host ''
Write-Host 'Listo. Nada de esto escribio en la base.' -ForegroundColor Green
Write-Host 'Copiame la salida entera, aunque sea larga.'
