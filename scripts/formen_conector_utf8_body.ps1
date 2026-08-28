# Formen — conector Dragonfish→Kommo
# Parche: mandarle a Kommo el body en UTF-8 (bug de la Ñ).
#
# Problema que arregla (visto 25, 26, 27 y 28/08/2026):
#   Invoke-Kommo pasaba el JSON a Invoke-RestMethod como STRING con
#   ContentType 'application/json', sin charset. PowerShell 5 codifica ese string
#   en Latin-1: la 'ñ' viaja como el byte suelto 0xF1, que no es UTF-8 valido, y
#   Kommo rechaza el pedido entero con 400 "Invalid request data".
#
#   No se pierde el caracter: se pierde la llamada completa. Por eso los productos
#   con Ñ no entran nunca al catalogo y la nota detallada de esa misma compra cae
#   a "nota basica", sin el listado de prendas.
#
#   Casos: 'Pañuelo Pochette (R2401)' (25, 26 y 28/08),
#          'CHALECO PLASTRON/PAÑ (RI1402)' (26/08),
#          'MOÑO (R3008)' (28/08).
#   En las mismas pasadas, los productos sin Ñ entraron sin un solo error.
#
# Que hace el parche:
#   Convierte el JSON a bytes UTF-8 antes de mandarlo y declara el charset.
#   No cambia ninguna otra cosa: todas las llamadas a Kommo pasan por esta funcion.
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

  if ($txt -match 'UTF8\.GetBytes\(\$json\)') {
    throw 'El parche ya estaba aplicado. No se hizo nada.'
  }

  $nl = if ($txt -match "`r`n") { "`r`n" } else { "`n" }

  # ── 1. El body, como bytes UTF-8 ───────────────────────────────────────────
  $viejoBody = '$req.Body = ConvertTo-Json -InputObject $Cuerpo -Depth 6 -Compress'
  Assert-Unico $txt $viejoBody 'armado del body en Invoke-Kommo'

  $nuevoBody = @(
    '# PowerShell 5 manda el body string en Latin-1: una sola N con virgulilla o un'
    '# acento alcanza para que Kommo rechace el pedido entero con 400. Va como bytes UTF-8.'
    '$json = ConvertTo-Json -InputObject $Cuerpo -Depth 6 -Compress'
    '$req.Body = [System.Text.Encoding]::UTF8.GetBytes($json)'
  ) -join ($nl + '    ')

  $txt = $txt.Replace($viejoBody, $nuevoBody)

  # ── 2. Declarar el charset ─────────────────────────────────────────────────
  $viejoCt = "`$req.ContentType = 'application/json'"
  Assert-Unico $txt $viejoCt 'ContentType en Invoke-Kommo'
  $txt = $txt.Replace($viejoCt, "`$req.ContentType = 'application/json; charset=utf-8'")

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
    throw "Quedaba con errores de sintaxis. SE RESTAURO el original. Backup en $backup"
  }

  "OK - parche aplicado. Backup: $backup"
}
