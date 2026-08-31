# Formen — conector Dragonfish→Kommo
# Parche: la compra va al lead del formulario, no al de la ficha vieja.
#
# Problema que arregla (28/08/2026):
#   Cuando el cliente ya existia en Kommo, el formulario del iPad crea un contacto
#   nuevo. Resolve-ContactoDestino detecta el duplicado y manda la NOTA a la ficha
#   vieja -la del chat de WhatsApp-, que esta bien: el historial queda junto.
#
#   Pero Resolve-LeadCompraDestino usaba esa misma ficha vieja para decidir donde
#   cargar la COMPRA, y ahi el importe aterrizaba en el lead equivocado. En el
#   tablero se veia asi:
#
#       LEAD PAUSADO   juan lopez              $452.000   <- venta cobrada
#       FORMULARIO     Juan lopez #20515173          $0   <- la venta del local
#
#   El embudo miente en las dos puntas: "Lead pausado" suma plata que no es de esa
#   etapa y "Formulario" muestra menos de lo que se vendio. El mismo dia paso con
#   Juan lopez, Gonzalo orti y Miguel Vigier: 3 de 17 leads reales.
#
# Que hace el parche:
#   Invierte la preferencia. La compra (productos + presupuesto) va al lead del
#   contacto que cargo el formulario -el que matcheo por comprobante, y que vive
#   en la etapa Formulario- y solo cae al lead de la ficha vieja si aquel no tiene
#   ninguno. La nota sigue yendo a la ficha del cliente: eso no cambia.
#
#   Cuando no hay duplicado, candidato y destino son el mismo contacto y el
#   comportamiento queda identico al de antes.
#
# Decidido con Martin el 28/08: el lead real de la venta del local es el del
# formulario; la fusion del lead viejo con ese se hace despues, a mano en Kommo.
#
# Se ejecuta EN LA PC DEL LOCAL. Envolver en & { ... } al pegarlo en la consola.

& {
  $ErrorActionPreference = 'Stop'
  $ruta = 'C:\FormenConector\conector.ps1'

  $bytes = [System.IO.File]::ReadAllBytes($ruta)
  $conBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($txt.Length -gt 0 -and $txt[0] -eq [char]0xFEFF) { $txt = $txt.Substring(1) }

  if ($txt -match 'van al lead del formulario') { throw 'El parche ya estaba aplicado. No se hizo nada.' }

  $nl = if ($txt -match "`r`n") { "`r`n" } else { "`n" }

  # Ubicar la funcion por AST: no depende de la indentacion ni del texto exacto.
  $errs = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) { throw 'El archivo ya tenia errores de sintaxis. Abortado.' }

  $fns = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Resolve-LeadCompraDestino'
      }, $true))
  if ($fns.Count -ne 1) { throw "Se esperaba 1 Resolve-LeadCompraDestino y hay $($fns.Count). Abortado." }
  $ext = $fns[0].Extent

  $nueva = @(
    'function Resolve-LeadCompraDestino {'
    '  param($Cfg, $ContactoDestino, $ContactoCandidato)'
    ''
    '  # La compra es la venta del local: va al lead del contacto que cargo el'
    '  # formulario, que es el que vive en la etapa Formulario. Mandarla al lead de la'
    '  # ficha vieja -la del chat- hace que el importe aparezca en la columna'
    '  # equivocada del embudo (28/08: $452.000 de una venta cobrada figuraban en'
    '  # "Lead pausado") y deja el lead del formulario en $0.'
    '  # La nota sigue yendo a la ficha del cliente: eso lo decide Resolve-ContactoDestino.'
    '  if ($ContactoCandidato) {'
    '    $leadId = Get-LeadParaContacto -Cfg $Cfg -ContactoId ([int64]$ContactoCandidato.id)'
    '    if ($leadId) {'
    '      if ([int64]$ContactoCandidato.id -ne [int64]$ContactoDestino.id) {'
    '        Write-Log ''info'' ("Compra y productos van al lead del formulario (contacto $($ContactoCandidato.id)), " +'
    '          "no al de la ficha $($ContactoDestino.id).")'
    '      }'
    '      return [pscustomobject]@{'
    '        LeadId   = $leadId'
    '        Contacto = $ContactoCandidato'
    '      }'
    '    }'
    '  }'
    ''
    '  # El contacto del formulario no tiene lead: queda el de la ficha vieja.'
    '  $leadId = Get-LeadParaContacto -Cfg $Cfg -ContactoId ([int64]$ContactoDestino.id)'
    '  if ($leadId) {'
    '    Write-Log ''info'' ("El contacto del formulario no tiene lead; la compra va al de la ficha $($ContactoDestino.id).")'
    '    return [pscustomobject]@{'
    '      LeadId   = $leadId'
    '      Contacto = $ContactoDestino'
    '    }'
    '  }'
    ''
    '  return $null'
    '}'
  ) -join $nl

  $txt = $txt.Substring(0, $ext.StartOffset) + $nueva + $txt.Substring($ext.EndOffset)

  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = "$ruta.bak-$stamp"
  [System.IO.File]::WriteAllBytes($backup, $bytes)

  $enc = New-Object System.Text.UTF8Encoding($conBom)
  [System.IO.File]::WriteAllText($ruta, $txt, $enc)

  $errs2 = $null
  [System.Management.Automation.Language.Parser]::ParseFile($ruta, [ref]$null, [ref]$errs2) | Out-Null
  if ($errs2 -and $errs2.Count -gt 0) {
    [System.IO.File]::WriteAllBytes($ruta, $bytes)
    $errs2 | ForEach-Object { "  $($_.Extent.StartLineNumber): $($_.Message)" }
    throw "Quedaba con errores de sintaxis. SE RESTAURO el original. Backup en $backup"
  }

  "OK - parche aplicado. Backup: $backup"
}
