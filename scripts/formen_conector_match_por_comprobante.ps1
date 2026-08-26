# Formen — conector Dragonfish→Kommo
# Parche: emparejar la venta con el cliente POR EL NUMERO DE COMPROBANTE, no por la hora.
#
# Problema que arregla (26/08/2026):
#   Invoke-Pasada buscaba los contactos con Get-ContactosEnVentana, que filtra por
#   created_at entre la hora de la venta y +ventanaMin (10 min). Como el vendedor carga
#   al cliente ANTES de facturar, el contacto quedaba fuera de la ventana — a veces por
#   un solo minuto — y el conector reportaba "sin contacto en la ventana".
#   El 26/08 quedaron 10 ventas seguidas sin asociar por esto.
#
#   Caso testigo: contacto 43900575 (Marcos Matias Hanke), creado 11:42 con Position=6643;
#   venta B 0001-00006643 facturada 11:43. Ventana 11:43→11:53. Nunca lo iba a encontrar.
#
# Que hace el parche:
#   1. Agrega Get-ContactosParaVenta, que busca en Kommo por los ultimos 4 del comprobante
#      (/api/v4/contacts?query=NNNN) y ademas conserva la busqueda vieja por ventana,
#      uniendo ambas listas sin duplicados.
#   2. Invoke-Pasada pasa a usar esa funcion en lugar de Get-ContactosEnVentana directo.
#
# Por que la union es segura: Select-CandidatosParaVenta sigue exigiendo comprobante exacto
# (permitirFallbackTemporalSinComprobante = false), asi que un contacto que entre solo por
# cercania temporal se descarta igual. La ventana queda como red por si el indice de
# busqueda de Kommo tarda en actualizarse.
#
# Se ejecuta EN LA PC DEL LOCAL. Envolver en & { ... } al pegarlo en la consola: si no,
# un throw no frena las lineas siguientes y el archivo queda a medio escribir.

& {
  $ErrorActionPreference = 'Stop'
  $ruta = 'C:\FormenConector\conector.ps1'

  function Assert-Unico {
    param([string]$Texto, [string]$Aguja, [string]$Nombre)
    $n = [regex]::Matches($Texto, [regex]::Escape($Aguja)).Count
    if ($n -ne 1) { throw "ANCLA '$Nombre': se esperaba 1 ocurrencia y hay $n. Abortado, no se toco el archivo." }
  }

  # ── Leer preservando el BOM ────────────────────────────────────────────────
  $bytes = [System.IO.File]::ReadAllBytes($ruta)
  $conBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($txt.Length -gt 0 -and $txt[0] -eq [char]0xFEFF) { $txt = $txt.Substring(1) }

  if ($txt -match 'function Get-ContactosParaVenta') {
    throw 'El parche ya estaba aplicado (existe Get-ContactosParaVenta). No se hizo nada.'
  }

  $nl = if ($txt -match "`r`n") { "`r`n" } else { "`n" }

  # ── 1. Insertar Get-ContactosParaVenta antes de Get-ContactosEnVentana ─────
  $anclaInsert = '# Contactos cargados en el mostrador entre dos momentos.'
  Assert-Unico $txt $anclaInsert 'comentario de Get-ContactosEnVentana'

  $funcionNueva = @(
    '# Candidatos para una venta: primero por NUMERO DE COMPROBANTE (sin mirar la hora),'
    '# despues los de la ventana temporal como red. Se unen sin duplicados.'
    '# Select-CandidatosParaVenta igual exige comprobante exacto, asi que la ventana no'
    '# puede vincular de mas: solo cubre el caso de que Kommo tarde en indexar la busqueda.'
    'function Get-ContactosParaVenta {'
    '  param($Cfg, $Venta)'
    ''
    '  $vistos = @{}'
    '  $salida = @()'
    ''
    '  $ultimos4 = Get-Ultimos4Comprobante $Venta'
    '  if ($ultimos4) {'
    '    $r = Invoke-Kommo -Cfg $Cfg -Metodo ''GET'' -Ruta "/api/v4/contacts?query=$ultimos4&limit=250"'
    '    if ($r) {'
    '      foreach ($c in @($r._embedded.contacts)) {'
    '        if (-not (Test-ContactoDelLocal -Cfg $Cfg -Contacto $c)) { continue }'
    '        $k = "$($c.id)"'
    '        if ($vistos.ContainsKey($k)) { continue }'
    '        $vistos[$k] = $true'
    '        $salida += $c'
    '      }'
    '    }'
    '    if ($salida.Count -gt 0) {'
    '      Write-Log ''debug'' "Venta $($Venta.Comprobante): $($salida.Count) contacto(s) por comprobante $ultimos4."'
    '    }'
    '  }'
    ''
    '  $ventana = if ($Cfg.match.ventanaMin) { [int]$Cfg.match.ventanaMin } else { 10 }'
    '  foreach ($c in @(Get-ContactosEnVentana -Cfg $Cfg -Desde $Venta.Ts -Hasta $Venta.Ts.AddMinutes($ventana))) {'
    '    $k = "$($c.id)"'
    '    if ($vistos.ContainsKey($k)) { continue }'
    '    $vistos[$k] = $true'
    '    $salida += $c'
    '  }'
    ''
    '  return @($salida)'
    '}'
    ''
  ) -join $nl

  $txt = $txt.Replace($anclaInsert, $funcionNueva + $anclaInsert)

  # ── 2. Invoke-Pasada usa la funcion nueva ──────────────────────────────────
  $viejoLlamado = '$hasta = $venta.Ts.AddMinutes($Cfg.match.ventanaMin)'
  Assert-Unico $txt $viejoLlamado 'calculo de $hasta en Invoke-Pasada'

  $viejoGet = '$todos = Get-ContactosEnVentana -Cfg $Cfg -Desde $venta.Ts -Hasta $hasta'
  Assert-Unico $txt $viejoGet 'llamada a Get-ContactosEnVentana en Invoke-Pasada'

  # Se borra la linea del $hasta entera (con su indentacion y su salto).
  $txt = [regex]::Replace($txt, '[ \t]*' + [regex]::Escape($viejoLlamado) + '\r?\n', '')
  $txt = $txt.Replace($viejoGet, '$todos = @(Get-ContactosParaVenta -Cfg $Cfg -Venta $venta)')

  # ── 3. Backup, escribir y validar sintaxis ─────────────────────────────────
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
    throw "El archivo quedaba con errores de sintaxis. SE RESTAURO el original. Backup en $backup"
  }

  "OK - parche aplicado. Backup: $backup"
  "Ahora el conector busca al cliente por el numero de comprobante, sin mirar la hora."
}
