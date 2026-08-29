# Arreglo del presupuesto acumulado del conector Dragonfish -> Kommo (Formen).
#
# Bug: al vincular productos, Kommo recalcula el Presupuesto del lead solo
# (cada entity_linked dispara un sale_field_changed). Update-LeadCompraPorIdKommo
# leia el price DESPUES de Sync-ProductosLeadKommo, o sea ya inflado, y le sumaba
# encima el total del comprobante: el importe se contaba dos veces.
#
# Sintoma: lead nuevo + comando "F 6636" (comprobante de 149.780) dejaba el
# Presupuesto en 309.560.
#
# Fix: leer el precio base antes de tocar los productos y pasarlo por parametro.
# Si no se pasa, la funcion sigue leyendo el lead como antes (compatibilidad con
# el flujo automatico, que hay que revisar aparte).

& {
  $ErrorActionPreference = 'Stop'
  $p = 'C:\FormenConector\conector.ps1'

  $bytes = [System.IO.File]::ReadAllBytes($p)
  $tieneBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $texto = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($tieneBom) { $texto = $texto.Substring(1) }

  if ($texto.Contains('$precioBaseAntes')) { throw 'El arreglo del precio base ya esta aplicado. No se toca nada.' }
  if (-not $texto.Contains('foreach ($t in $trabajos) {')) { throw 'Falta el parche de comandos por evento. No se aplica.' }

  $L = New-Object 'System.Collections.Generic.List[string]'
  foreach ($ln in ($texto -split "`r?`n")) { [void]$L.Add($ln) }

  function BuscarUnica {
    param($Lineas, [string]$Aguja)
    $idx = @()
    for ($i = 0; $i -lt $Lineas.Count; $i++) { if ($Lineas[$i].Contains($Aguja)) { $idx += $i } }
    if ($idx.Count -ne 1) { throw "Esperaba 1 linea con [$Aguja] y encontre $($idx.Count). No se aplica el parche." }
    return [int]$idx[0]
  }

  function BuscarDesde {
    param($Lineas, [string]$Aguja, [int]$Desde)
    for ($j = $Desde; $j -lt $Lineas.Count; $j++) { if ($Lineas[$j].Contains($Aguja)) { return [int]$j } }
    throw "No encontre [$Aguja] despues de la linea $Desde. No se aplica el parche."
  }

  # 1) parametro nuevo en la firma
  $fn = BuscarUnica $L 'function Update-LeadCompraPorIdKommo {'
  $j = BuscarDesde $L 'param($Cfg, [int64]$LeadId, $Venta, [string]$NombreContacto' $fn
  $L[$j] = '  param($Cfg, [int64]$LeadId, $Venta, [string]$NombreContacto = '''', $LeadCfg = $null, $PrecioBase = $null)'

  # 2) usar la base recibida en vez de releer el lead ya recalculado
  $k = BuscarDesde $L '$leadParaPrecio = Invoke-Kommo' $fn
  if (-not $L[$k + 1].Contains('ConvertTo-EnteroKommo $leadParaPrecio.price')) { throw 'No encontre la lectura del price. No se aplica el parche.' }
  if (-not $L[$k + 2].Contains('if ($null -eq $precioBase) { $precioBase = 0 }')) { throw 'No encontre el default del price. No se aplica el parche.' }
  $reemplazo = @(
    '      $precioBase = ConvertTo-EnteroKommo $PrecioBase',
    '      if ($null -eq $precioBase) {',
    '        # Sin base explicita: se lee del lead. Ojo que si ya se vincularon',
    '        # productos, Kommo recalculo el Presupuesto y este numero viene',
    '        # inflado; por eso el llamador deberia pasar -PrecioBase.',
    '        $leadParaPrecio = Invoke-Kommo -Cfg $Cfg -Metodo ''GET'' -Ruta "/api/v4/leads/$LeadId"',
    '        $precioBase = ConvertTo-EnteroKommo $leadParaPrecio.price',
    '      }',
    '      if ($null -eq $precioBase) { $precioBase = 0 }'
  )
  $L.RemoveRange($k, 3)
  $L.InsertRange($k, [string[]]$reemplazo)

  # 3) en el procesamiento de comandos, leer el price antes de tocar productos
  $m = BuscarUnica $L 'foreach ($t in $trabajos) {'
  $n = BuscarDesde $L '$detalle = Get-DetalleVenta -Cfg $Cfg -Venta $venta' $m
  $lectura = @(
    '        # El precio base se lee ANTES de vincular productos: al vincularlos,',
    '        # Kommo recalcula el Presupuesto solo y, leido despues, el importe',
    '        # del comprobante se contaria dos veces.',
    '        $leadAntes = Invoke-Kommo -Cfg $Cfg -Metodo ''GET'' -Ruta "/api/v4/leads/$leadId"',
    '        $precioBaseAntes = ConvertTo-EnteroKommo $leadAntes.price',
    '        if ($null -eq $precioBaseAntes) { $precioBaseAntes = 0 }'
  )
  $L.InsertRange($n, [string[]]$lectura)

  # 4) pasar la base en la llamada
  $q = BuscarDesde $L 'Update-LeadCompraPorIdKommo -Cfg $Cfg -LeadId $leadId -Venta $venta' $m
  $L[$q] = '        Update-LeadCompraPorIdKommo -Cfg $Cfg -LeadId $leadId -Venta $venta -PrecioBase $precioBaseAntes'

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

  'parser OK - precio base corregido'
}
