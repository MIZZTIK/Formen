# Formen — conector Dragonfish→Kommo
# Parche: repescar las ventas que quedaron sin candidato, en vez de descartarlas
# en el primer intento.
#
# Problema que arregla (28/08/2026):
#   Invoke-Pasada evaluaba cada venta UNA sola vez, esperaMin despues de la venta,
#   y la marcaba como procesada pasara lo que pasara:
#
#       # Asociada o no, queda procesada: si el contacto no aparecio en la
#       # ventana, no va a aparecer mas tarde.
#       $cursor.processedIds += $venta.Id
#
#   Ese comentario valia cuando el apareo era por cercania temporal. Desde que se
#   busca por numero de comprobante ya no: el contacto aparece cuando el vendedor
#   termina de cargar el formulario, y eso puede ser despues.
#
#   El 28/08 las cuatro ventas del dia se definieron por segundos:
#     6654  conector busca 11:37:19 -> contacto creado 11:37:58   perdio por 39 s
#     6656  conector busca 12:04:51 -> contacto creado 12:05:25   perdio por 34 s
#     6655  conector busca 12:02:53 -> contacto creado 12:02:52   gano por 1 s
#     6656  conector busca 11:21:34 -> contacto creado 11:21:31   gano por 3 s
#   Las dos que perdieron quedaron descartadas para siempre.
#
# Que hace el parche:
#   1. La venta sin candidato ya NO entra en processedIds: queda pendiente.
#      (Las ambiguas si se marcan: esas no se resuelven solas y repetirlas solo
#      llenaria el log de warnings.)
#   2. Cada repescaCadaMin (5 por defecto) la consulta a Dragonfish mira hacia
#      atras repescaHoras (24 por defecto) en vez de arrancar en el cursor, asi
#      las pendientes vuelven a evaluarse. Las asociadas estan en processedIds y
#      no se tocan, de modo que no se duplican notas ni presupuestos.
#   3. Pasadas las repescaHoras, la venta sale del rango y se da por perdida.
#
#   Se puede regular desde la config con match.repescaHoras y match.repescaCadaMin;
#   si no estan, valen los defaults.
#
# Se ejecuta EN LA PC DEL LOCAL. Envolver en & { ... } al pegarlo en la consola.

& {
  $ErrorActionPreference = 'Stop'
  $ruta = 'C:\FormenConector\conector.ps1'

  function Assert-Unico {
    param([string]$Texto, [string]$Aguja, [string]$Nombre)
    $n = [regex]::Matches($Texto, [regex]::Escape($Aguja)).Count
    if ($n -ne 1) { throw "ANCLA '$Nombre': se esperaba 1 ocurrencia y hay $n. Abortado, no se toco el archivo." }
  }

  $bytes = [System.IO.File]::ReadAllBytes($ruta)
  $conBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($txt.Length -gt 0 -and $txt[0] -eq [char]0xFEFF) { $txt = $txt.Substring(1) }

  if ($txt -match 'tocaRepesca') { throw 'El parche ya estaba aplicado. No se hizo nada.' }

  $nl = if ($txt -match "`r`n") { "`r`n" } else { "`n" }

  # ── 1. Bloque de repesca, antes de consultar las ventas ────────────────────
  $anclaDesde = '$desde = [datetime]::Parse($cursor.lastTs)'
  Assert-Unico $txt $anclaDesde 'lectura del cursor en Invoke-Pasada'

  $bloqueRepesca = @(
    '$desde = [datetime]::Parse($cursor.lastTs)'
    ''
    '# Repesca: cada repescaCadaMin la consulta mira hacia atras repescaHoras, para'
    '# recuperar las ventas que quedaron sin candidato porque cuando se evaluaron el'
    '# vendedor todavia no habia terminado de cargar el formulario. Las ya asociadas'
    '# estan en processedIds, asi que no se vuelven a escribir.'
    '$repescaHoras = if ($Cfg.match.repescaHoras) { [int]$Cfg.match.repescaHoras } else { 24 }'
    '$repescaCadaMin = if ($Cfg.match.repescaCadaMin) { [int]$Cfg.match.repescaCadaMin } else { 5 }'
    '$ultimaRepesca = [datetime]::MinValue'
    'if ($cursor.PSObject.Properties[''ultimaRepesca''] -and $cursor.ultimaRepesca) {'
    '  try { $ultimaRepesca = [datetime]::Parse($cursor.ultimaRepesca) } catch {}'
    '}'
    '$tocaRepesca = (((Get-Date) - $ultimaRepesca).TotalMinutes -ge $repescaCadaMin)'
    '$desdeConsulta = if ($tocaRepesca) { (Get-Date).AddHours(-$repescaHoras) } else { $desde }'
    '$etiquetaRepesca = if ($tocaRepesca) { '' [repesca]'' } else { '''' }'
    'if ($tocaRepesca) {'
    '  $cursor | Add-Member -NotePropertyName ultimaRepesca -NotePropertyValue ((Get-Date).ToString(''o'')) -Force'
    '  Save-Cursor $cursor'
    '}'
  ) -join ($nl + '  ')

  $txt = $txt.Replace($anclaDesde, $bloqueRepesca)

  # ── 2. La consulta usa el rango de repesca ─────────────────────────────────
  $viejaConsulta = '$ventas = @(Get-VentasNuevas -Cfg $Cfg -Desde $desde |'
  Assert-Unico $txt $viejaConsulta 'consulta de ventas nuevas'
  $txt = $txt.Replace($viejaConsulta, '$ventas = @(Get-VentasNuevas -Cfg $Cfg -Desde $desdeConsulta |')

  # ── 3. El log dice desde donde miro y si fue repesca ───────────────────────
  $viejoLog = '"Dragonfish: $($ventas.Count) ventas nuevas desde $($desde.ToString(''dd/MM HH:mm''))."'
  Assert-Unico $txt $viejoLog 'log de ventas nuevas'
  $txt = $txt.Replace($viejoLog, '"Dragonfish: $($ventas.Count) ventas nuevas desde $($desdeConsulta.ToString(''dd/MM HH:mm''))$etiquetaRepesca."')

  # ── 4. Recordar cuantas iban sin candidato antes de esta venta ─────────────
  $anclaEvaluadas = '$stats.evaluadas++'
  Assert-Unico $txt $anclaEvaluadas 'contador de evaluadas'
  $txt = $txt.Replace($anclaEvaluadas, ('$stats.evaluadas++' + $nl + '    $sinCandidatoAntes = $stats.sin_candidato'))

  # ── 5. La venta sin candidato queda pendiente, no procesada ────────────────
  $viejoCom1 = '# Asociada o no, queda procesada: si el contacto no aparecio en la'
  Assert-Unico $txt $viejoCom1 'comentario del marcado (1)'
  $viejoCom2 = '# ventana, no va a aparecer mas tarde.'
  Assert-Unico $txt $viejoCom2 'comentario del marcado (2)'
  $viejoMarcado = '$cursor.processedIds += $venta.Id'
  Assert-Unico $txt $viejoMarcado 'marcado en processedIds'

  $txt = $txt.Replace($viejoCom1, '# Sin candidato NO es definitivo: el vendedor puede estar cargando el')
  $txt = $txt.Replace($viejoCom2, '# formulario todavia. Queda pendiente y la repesca la vuelve a mirar.')

  $nuevoMarcado = @(
    'if ($stats.sin_candidato -gt $sinCandidatoAntes) {'
    '  Write-Log ''debug'' "Venta $($venta.Comprobante): sin candidato por ahora, queda pendiente de repesca."'
    '} else {'
    '  $cursor.processedIds += $venta.Id'
    '}'
  ) -join ($nl + '      ')

  $txt = $txt.Replace($viejoMarcado, $nuevoMarcado)

  # ── 6. Backup, escribir y validar sintaxis ─────────────────────────────────
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = "$ruta.bak-$stamp"
  [System.IO.File]::WriteAllBytes($backup, $bytes)

  $enc = New-Object System.Text.UTF8Encoding($conBom)
  [System.IO.File]::WriteAllText($ruta, $txt, $enc)

  $errs = $null
  [System.Management.Automation.Language.Parser]::ParseFile($ruta, [ref]$null, [ref]$errs) | Out-Null
  if ($errs -and $errs.Count -gt 0) {
    [System.IO.File]::WriteAllBytes($ruta, $bytes)
    $errs | ForEach-Object { "  $($_.Extent.StartLineNumber): $($_.Message)" }
    throw "Quedaba con errores de sintaxis. SE RESTAURO el original. Backup en $backup"
  }

  "OK - parche aplicado. Backup: $backup"
}
