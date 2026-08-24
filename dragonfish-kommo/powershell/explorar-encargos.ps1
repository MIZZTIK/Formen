# Exploracion de solo lectura sobre la base de Dragonfish.
#
# Responde tres preguntas que nunca se midieron:
#   1. Existe alguna tabla de encargos / pedidos / taller / arreglos?
#   2. Las ventas traen cargado el cliente (FPERSON / FCLIENTE), o esta vacio?
#   3. Si trae cliente, la ficha de CLI tiene telefono?
#
# NO escribe nada. Son cuatro SELECT.
#
#   powershell -ExecutionPolicy Bypass -File .\explorar-encargos.ps1

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
    $cmd = $con.CreateCommand(); $cmd.CommandText = $Query
    $ad = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable
    [void]$ad.Fill($t)
    return $t
  } finally { $con.Close() }
}

function Show-Titulo { param([string]$T) Write-Host ''; Write-Host "=== $T ===" -ForegroundColor Cyan }

$esquema = $Cfg.sql.schema

# --- 1. Tablas que suenen a encargo -----------------------------------------
Show-Titulo '1. Tablas candidatas (encargo / pedido / taller / arreglo / reserva)'
$q1 = @"
SELECT t.TABLE_NAME, p.rows AS filas
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN sys.tables st ON st.name = t.TABLE_NAME
LEFT JOIN sys.partitions p ON p.object_id = st.object_id AND p.index_id IN (0,1)
WHERE t.TABLE_SCHEMA = '$esquema'
  AND (t.TABLE_NAME LIKE '%PEDID%' OR t.TABLE_NAME LIKE '%ENCARG%'
    OR t.TABLE_NAME LIKE '%TALLER%' OR t.TABLE_NAME LIKE '%ARREGL%'
    OR t.TABLE_NAME LIKE '%RESERV%' OR t.TABLE_NAME LIKE '%ENTREG%'
    OR t.TABLE_NAME LIKE '%SENA%'   OR t.TABLE_NAME LIKE '%MEDID%')
ORDER BY p.rows DESC
"@
$r1 = Invoke-Sql $q1
if ($r1.Rows.Count -eq 0) { Write-Host '  (ninguna) -> el encargo no vive en una tabla propia.' }
else { $r1 | Format-Table -AutoSize | Out-String | Write-Host }

Show-Titulo '1b. Las 25 tablas mas grandes del esquema (por si el encargo se llama de otra forma)'
$q1b = @"
SELECT TOP 25 t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE s.name = '$esquema'
GROUP BY t.name
ORDER BY SUM(p.rows) DESC
"@
Invoke-Sql $q1b | Format-Table -AutoSize | Out-String | Write-Host

# --- 2. Viene cargado el cliente en la venta? -------------------------------
Show-Titulo '2. Ventas de los ultimos 90 dias: cuantas identifican al comprador'
$q2 = @"
SELECT
  COUNT(*)                                                            AS ventas,
  SUM(CASE WHEN LTRIM(RTRIM(ISNULL(FPERSON,'')))  <> '' THEN 1 ELSE 0 END) AS con_fperson,
  SUM(CASE WHEN LTRIM(RTRIM(ISNULL(FCLIENTE,''))) <> '' THEN 1 ELSE 0 END) AS con_fcliente,
  SUM(CASE WHEN LTRIM(RTRIM(ISNULL(EMAIL,'')))    <> '' THEN 1 ELSE 0 END) AS con_email
FROM [$esquema].[COMPROBANTEV]
WHERE ANULADO = 0 AND FALTAFW >= DATEADD(day, -90, CAST(GETDATE() AS date))
"@
Invoke-Sql $q2 | Format-Table -AutoSize | Out-String | Write-Host

Show-Titulo '2b. Los valores de FCLIENTE que mas se repiten (para ver si es todo "consumidor final")'
$q2b = @"
SELECT TOP 15 LTRIM(RTRIM(ISNULL(FCLIENTE,'(vacio)'))) AS cliente, COUNT(*) AS veces
FROM [$esquema].[COMPROBANTEV]
WHERE ANULADO = 0 AND FALTAFW >= DATEADD(day, -90, CAST(GETDATE() AS date))
GROUP BY LTRIM(RTRIM(ISNULL(FCLIENTE,'(vacio)')))
ORDER BY COUNT(*) DESC
"@
Invoke-Sql $q2b | Format-Table -AutoSize | Out-String | Write-Host

# --- 3. La ficha de cliente tiene telefono? ---------------------------------
Show-Titulo '3. Columnas de CLI que parecen contacto (telefono / celular / mail)'
$q3 = @"
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS largo
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '$esquema' AND TABLE_NAME = 'CLI'
  AND (COLUMN_NAME LIKE '%TEL%' OR COLUMN_NAME LIKE '%CEL%'
    OR COLUMN_NAME LIKE '%MAIL%' OR COLUMN_NAME LIKE '%FONO%'
    OR COLUMN_NAME LIKE '%NOM%'  OR COLUMN_NAME LIKE '%CONTAC%')
ORDER BY COLUMN_NAME
"@
$r3 = Invoke-Sql $q3
if ($r3.Rows.Count -eq 0) { Write-Host '  (ninguna) -> CLI no guarda telefono.' }
else { $r3 | Format-Table -AutoSize | Out-String | Write-Host }

Write-Host ''
Write-Host 'Listo. Nada de esto escribio en la base.' -ForegroundColor Green
Write-Host 'Copiame la salida entera.'
