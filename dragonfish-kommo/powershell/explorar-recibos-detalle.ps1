# Exploracion enfocada de recibos, pagos y productos por comprobante.
#
# NO escribe nada. Solo SELECT.
#
#   powershell -ExecutionPolicy Bypass -File .\explorar-recibos-detalle.ps1

$ErrorActionPreference = 'Stop'
$cfgPath = Join-Path $PSScriptRoot 'conector.config.json'
if (-not (Test-Path $cfgPath)) { throw "No encuentro $cfgPath" }
$Cfg = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
$esquema = $Cfg.sql.schema

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
  $Rows | Format-Table -AutoSize | Out-String -Width 260 | Write-Host
}

Show-Titulo '1. Tablas chicas que pueden separar Black / Formen'
$q1 = @"
SELECT 'PTOVTA' AS tabla, CAST(PTO AS varchar(30)) AS clave, COMP AS descripcion
FROM [$esquema].[PTOVTA]
UNION ALL
SELECT 'NUMERACIONES', CAST(PTOVEN AS varchar(30)), TALONARIO
FROM [$esquema].[NUMERACIONES]
ORDER BY tabla, clave
"@
Show-Tabla (Invoke-Sql $q1)

Show-Titulo '2. Valores / medios de pago configurados'
$q2 = @"
SELECT
  LTRIM(RTRIM(VALORACRED)) AS valor_acredita,
  LTRIM(RTRIM(VALORRETEF)) AS valor_retefuente,
  LTRIM(RTRIM(VALLINCE)) AS descripcion,
  TIPOTARJ,
  IDCAJA,
  CTABANC,
  PAGUESEA,
  FACTELEC,
  CLRECARGO,
  PERSOCOMP,
  TIPAGRUPUB
FROM [$esquema].[XVAL]
ORDER BY descripcion
"@
Show-Tabla (Invoke-Sql $q2)

Show-Titulo '2b. Medios de pago usados recientemente en caja'
$q2b = @"
SELECT
  LTRIM(RTRIM(DESCRIP)) AS descripcion,
  LTRIM(RTRIM(IDVALOR)) AS idvalor,
  TIPOVALOR,
  COUNT(*) AS movimientos,
  SUM(MONTO) AS total
FROM [$esquema].[MOVCAJA]
WHERE FECHA >= DATEADD(day, -30, CAST(GETDATE() AS date))
GROUP BY LTRIM(RTRIM(DESCRIP)), LTRIM(RTRIM(IDVALOR)), TIPOVALOR
ORDER BY movimientos DESC, descripcion
"@
Show-Tabla (Invoke-Sql $q2b)

Show-Titulo '3. Comprobantes por tipo y punto de venta (ultimos 90 dias)'
$q3 = @"
SELECT
  FACTTIPO,
  FACTSEC,
  LTRIM(RTRIM(ISNULL(FLETRA,''))) AS letra,
  FPTOVEN AS punto_venta,
  COUNT(*) AS ventas,
  MIN(FNUMCOMP) AS primer_numero,
  MAX(FNUMCOMP) AS ultimo_numero,
  SUM(FTOTAL) AS total
FROM [$esquema].[COMPROBANTEV]
WHERE ANULADO = 0 AND FALTAFW >= DATEADD(day, -90, CAST(GETDATE() AS date))
GROUP BY FACTTIPO, FACTSEC, LTRIM(RTRIM(ISNULL(FLETRA,''))), FPTOVEN
ORDER BY ventas DESC
"@
Show-Tabla (Invoke-Sql $q3)

Show-Titulo '4. Pruebas de enlace entre ventas, cupones y caja (ultimos 30 dias)'
$q4 = @"
SELECT
  (SELECT COUNT(*)
   FROM [$esquema].[COMPROBANTEV] v
   JOIN [$esquema].[CUPONES] c ON c.COMP = v.CODIGO
   WHERE v.ANULADO = 0 AND v.FALTAFW >= DATEADD(day, -30, CAST(GETDATE() AS date))) AS cupones_por_codigo_venta,
  (SELECT COUNT(*)
   FROM [$esquema].[CUPONES] c
   JOIN [$esquema].[MOVCAJA] m ON m.ITEMVALOR = c.CODIGO
   WHERE c.FECHA >= DATEADD(day, -30, CAST(GETDATE() AS date))) AS movcaja_por_codigo_cupon,
  (SELECT COUNT(*)
   FROM [$esquema].[COMPROBANTEV] v
   JOIN [$esquema].[MOVCAJA] m ON m.NUMCOMP = v.FNUMCOMP AND m.PTOVTA = v.FPTOVEN AND m.FECHACOMPR = v.FFCH
   WHERE v.ANULADO = 0 AND v.FALTAFW >= DATEADD(day, -30, CAST(GETDATE() AS date))) AS movcaja_por_numero_fecha
FROM (SELECT 1 AS x) base
"@
Show-Tabla (Invoke-Sql $q4)

Show-Titulo '5. Ultimas ventas con recibo / cupon / caja'
$q5 = @"
SELECT TOP 60
  v.DESCFW AS comprobante,
  v.CODIGO AS venta_id,
  v.FALTAFW,
  v.HALTAFW,
  v.FCLIENTE,
  v.FTOTAL AS venta_total,
  v.IDCAJA AS venta_idcaja,
  c.CODIGO AS cupon_id,
  c.MONTO AS cupon_monto,
  c.VALOR AS cupon_valor,
  c.TIPOTARJ,
  c.NUMERO AS cupon_numero,
  c.NROINTERNO,
  c.ULTDIG,
  c.NOMTITULAR,
  c.POS,
  m.DESCRIP AS caja_descrip,
  m.MONTO AS caja_monto,
  m.IDVALOR AS caja_valor,
  m.TIPOVALOR,
  m.ITEMVALOR
FROM [$esquema].[COMPROBANTEV] v
LEFT JOIN [$esquema].[CUPONES] c ON c.COMP = v.CODIGO
LEFT JOIN [$esquema].[MOVCAJA] m ON m.ITEMVALOR = c.CODIGO
WHERE v.ANULADO = 0 AND v.FALTAFW >= DATEADD(day, -10, CAST(GETDATE() AS date))
ORDER BY v.FALTAFW DESC, v.HALTAFW DESC, c.MONTO DESC
"@
Show-Tabla (Invoke-Sql $q5)

Show-Titulo '6. Productos por comprobante desde COMPROBANTEVDET'
$q6 = @"
SELECT TOP 80
  v.DESCFW AS comprobante,
  v.FALTAFW,
  v.HALTAFW,
  d.NROITEM,
  LTRIM(RTRIM(d.FART)) AS articulo,
  LTRIM(RTRIM(d.FTXT)) AS descripcion,
  d.FCANT AS cantidad,
  d.FPRECIO AS precio_unitario,
  d.MNTPTOT AS total_item,
  LTRIM(RTRIM(d.TALLE)) AS talle,
  LTRIM(RTRIM(d.CCOLOR)) AS color_codigo,
  LTRIM(RTRIM(d.FCOLTXT)) AS color_texto
FROM [$esquema].[COMPROBANTEV] v
JOIN [$esquema].[COMPROBANTEVDET] d ON d.CODIGO = v.CODIGO
WHERE v.ANULADO = 0 AND v.FALTAFW >= DATEADD(day, -10, CAST(GETDATE() AS date))
ORDER BY v.FALTAFW DESC, v.HALTAFW DESC, d.NROITEM
"@
Show-Tabla (Invoke-Sql $q6)

Show-Titulo '7. Movimientos de stock asociados al texto del comprobante'
$q7 = @"
SELECT TOP 80
  ADT_COMP AS comprobante,
  ADT_FECHA,
  ADT_HORA,
  LTRIM(RTRIM(COCOD)) AS articulo,
  COCANT AS cantidad,
  LTRIM(RTRIM(TALLE)) AS talle,
  LTRIM(RTRIM(COCOL)) AS color_codigo,
  CORIG,
  CORIGENTRE,
  ENTRANORIG
FROM [$esquema].[ADT_COMB]
WHERE ADT_FECHA >= DATEADD(day, -10, CAST(GETDATE() AS date))
ORDER BY ADT_FECHA DESC, ADT_HORA DESC, ADT_COMP, COCOD
"@
Show-Tabla (Invoke-Sql $q7)

Show-Titulo '8. Comprobantes de caja recientes con detalle'
$q8 = @"
SELECT TOP 80
  cc.DESCFW AS comprobante_caja,
  cc.CODIGO AS caja_id,
  cc.FECHA,
  cc.CAJAORIG,
  cc.CAJADEST,
  cc.CONCEPTO,
  d.CODVAL,
  d.DESCRIP,
  d.MONTO,
  d.MONTOSISTE,
  d.GUIDCOMP
FROM [$esquema].[COMCAJ] cc
LEFT JOIN [$esquema].[COMPCAJADET] d ON d.GUIDCOMP = cc.CODIGO
WHERE cc.FECHA >= DATEADD(day, -10, CAST(GETDATE() AS date))
ORDER BY cc.FECHA DESC, cc.CODIGO, d.NROITEM
"@
Show-Tabla (Invoke-Sql $q8)

Write-Host ''
Write-Host 'Listo. Nada de esto escribio en la base.' -ForegroundColor Green
Write-Host 'Copiame la salida entera.'
