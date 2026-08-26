# Mismo arreglo de precio base, para el flujo automatico (ventas que el conector
# detecta solo en Dragonfish). Ver formen_conector_precio_base.ps1: alla se
# corrigio el camino de los comandos manuales.
#
# El bloque automatico hace Sync-ProductosLeadKommo y despues
# Update-LeadCompraPorIdKommo sin -PrecioBase, asi que el importe del
# comprobante se cuenta dos veces igual que en el otro camino.
#
# $precioBaseAuto se reinicia junto a $leadDestino: el bloque esta adentro de un
# bucle por venta y, si el GET falla, un valor colgado de la vuelta anterior
# escribiria un presupuesto de otro lead.

& {
  $ErrorActionPreference = 'Stop'
  $p = 'C:\FormenConector\conector.ps1'

  $bytes = [System.IO.File]::ReadAllBytes($p)
  $tieneBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $texto = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($tieneBom) { $texto = $texto.Substring(1) }

  if ($texto.Contains('$precioBaseAuto')) { throw 'El arreglo del flujo automatico ya esta aplicado. No se toca nada.' }
  if (-not $texto.Contains('$precioBaseAntes')) { throw 'Falta el arreglo del camino manual. No se aplica.' }

  $L = New-Object 'System.Collections.Generic.List[string]'
  foreach ($ln in ($texto -split "`r?`n")) { [void]$L.Add($ln) }

  function BuscarUnica {
    param($Lineas, [string]$Aguja)
    $idx = @()
    for ($i = 0; $i -lt $Lineas.Count; $i++) { if ($Lineas[$i].Contains($Aguja)) { $idx += $i } }
    if ($idx.Count -ne 1) { throw "Esperaba 1 linea con [$Aguja] y encontre $($idx.Count). No se aplica el parche." }
    return [int]$idx[0]
  }

  # 1) reiniciar la base en cada vuelta del bucle
  $a = BuscarUnica $L '$leadDestino = $null'
  $L.Insert($a + 1, '            $precioBaseAuto = $null')

  # 2) leer el precio antes de vincular productos
  $s = BuscarUnica $L 'Sync-ProductosLeadKommo -Cfg $Cfg -LeadId $leadDestino.LeadId'
  $lectura = @(
    '                # Precio base antes de vincular productos: Kommo recalcula el',
    '                # Presupuesto al vincularlos y, leido despues, cuenta doble.',
    '                $leadAntesAuto = Invoke-Kommo -Cfg $Cfg -Metodo ''GET'' -Ruta "/api/v4/leads/$($leadDestino.LeadId)"',
    '                $precioBaseAuto = ConvertTo-EnteroKommo $leadAntesAuto.price',
    '                if ($null -eq $precioBaseAuto) { $precioBaseAuto = 0 }'
  )
  $L.InsertRange($s, [string[]]$lectura)

  # 3) pasar la base en la llamada
  $q = BuscarUnica $L 'Update-LeadCompraPorIdKommo -Cfg $Cfg -LeadId $leadDestino.LeadId'
  $L[$q] = '                Update-LeadCompraPorIdKommo -Cfg $Cfg -LeadId $leadDestino.LeadId -Venta $venta -NombreContacto $leadDestino.Contacto.name -PrecioBase $precioBaseAuto'

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

  'parser OK - flujo automatico corregido'
}
