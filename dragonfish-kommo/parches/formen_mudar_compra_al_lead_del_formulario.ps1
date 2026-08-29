# Formen — mudanza puntual de compras mal ubicadas (28/08/2026)
#
# Para que sirve:
#   Antes del parche "la compra va al lead del formulario", las ventas de clientes
#   que ya existian en Kommo se cargaron en el lead VIEJO (el del chat de WhatsApp)
#   en vez del lead del formulario. El importe quedo en la columna equivocada del
#   embudo: $452.000 de una venta cobrada figuraban en "Lead pausado".
#
#   Este script muda productos e importe al lead del formulario y deja el viejo en
#   cero. NO toca la nota: esa vive en la ficha del contacto y esta bien ahi.
#
# Solo sirve para los casos donde el lead viejo tiene UNA sola compra y su price es
# exactamente el total de esa compra. Verificado a mano para los tres del 28/08.
# Si el lead viejo acumulara varias compras, esto no aplica.
#
# Guarda el estado previo en data\mudanza-<timestamp>.json para poder revertir.
#
# Arrancar SIEMPRE con $SoloMostrar = $true, mirar la salida, y recien despues
# ponerlo en $false.
#
# DOS COSAS QUE COSTARON UNA CORRIDA A MEDIAS (28/08):
#
#  1. Kommo recalcula el price del lead de forma ASINCRONICA al vincular cada
#     producto, y termina DESPUES del PATCH: con 3 productos el importe quedo en
#     546.770 (suma de precios de catalogo) en vez de los 452.000 de la venta.
#     Por eso Fijar-Price reintenta y verifica en vez de hacer un PATCH y confiar.
#
#  2. Kommo empezo a devolver 500 en /link despues de un rato de llamadas
#     seguidas -aceptaba los primeros dos casos y rechazo el tercero, y despues
#     rechazaba cualquier link, incluso de otros productos en otros leads-.
#     Parece throttling. Por eso cada caso va en su propio try/catch y el
#     respaldo se escribe caso por caso: si el tercero falla, los dos primeros
#     ya quedaron guardados.

& {
  $ErrorActionPreference = 'Stop'
  $SoloMostrar = $true   # <<<< poner en $false para ejecutar de verdad

  $cfg = Get-Content C:\FormenConector\conector.config.json -Raw -Encoding utf8 | ConvertFrom-Json
  $h = @{ Authorization = "Bearer $($cfg.kommo.token)"; Accept = 'application/json' }
  $hp = $h.Clone(); $hp['Content-Type'] = 'application/json; charset=utf-8'
  $b = "https://$($cfg.kommo.subdominio).kommo.com"
  $cat = [int]$cfg.productos.catalogId

  $casos = @(
    @{ quien = 'Miguel Vigier'; viejo = 20240999; form = 20399551; total = 177860 }
    @{ quien = 'Juan lopez';    viejo = 20514087; form = 20515173; total = 452000 }
    @{ quien = 'Gonzalo orti';  viejo = 20085637; form = 20519541; total = 35900 }
  )

  $respaldo = @()
  $archivo = "C:\FormenConector\data\mudanza-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

  # Kommo recalcula el price al vincular productos, y lo hace despues del PATCH.
  # Hay que insistir hasta que el valor que queremos sea el que quedo.
  function Fijar-Price {
    param($LeadId, [int]$Valor)
    for ($i = 1; $i -le 5; $i++) {
      $body = @{ price = $Valor } | ConvertTo-Json -Compress
      [void](Invoke-RestMethod -Uri "$b/api/v4/leads/$LeadId" -Headers $hp -Method Patch -Body ([System.Text.Encoding]::UTF8.GetBytes($body)))
      Start-Sleep -Seconds 4
      $l = Invoke-RestMethod -Uri "$b/api/v4/leads/$LeadId" -Headers $h
      if ([int]$l.price -eq $Valor) { return "  lead $LeadId quedo en $($l.price) (intento $i)" }
    }
    $l = Invoke-RestMethod -Uri "$b/api/v4/leads/$LeadId" -Headers $h
    return "  lead $LeadId NO se pudo fijar: quedo en $($l.price)"
  }

  foreach ($k in $casos) {
    ''; "===== $($k.quien)"

    $lv = Invoke-RestMethod -Uri "$b/api/v4/leads/$($k.viejo)" -Headers $h
    $lf = Invoke-RestMethod -Uri "$b/api/v4/leads/$($k.form)" -Headers $h

    if ([int]$lv.price -ne [int]$k.total) {
      "  SALTEADO: el lead viejo tiene price $($lv.price) y la compra es $($k.total). Revisar a mano."
      continue
    }
    if ([int]$lf.price -ne 0) {
      "  SALTEADO: el lead del formulario ya tiene price $($lf.price)."
      continue
    }

    $links = @()
    $r = Invoke-RestMethod -Uri "$b/api/v4/leads/$($k.viejo)/links" -Headers $h
    foreach ($x in @($r._embedded.links)) {
      if ("$($x.to_entity_type)" -ne 'catalog_elements') { continue }
      if ($x.metadata.catalog_id -and [int]$x.metadata.catalog_id -ne $cat) { continue }
      $links += [pscustomobject]@{ id = [int64]$x.to_entity_id; cant = [int]$x.metadata.quantity }
    }

    "  productos a mudar: $($links.Count)   importe: $($k.total)"
    "  $($k.viejo) (price $($lv.price)) --> $($k.form) (price $($lf.price))"

    $respaldo += [pscustomobject]@{
      quien = $k.quien; viejo = $k.viejo; form = $k.form
      priceViejo = [int]$lv.price; priceForm = [int]$lf.price
      productos = $links
    }

    if ($SoloMostrar) { "  [solo mostrar: no se toco nada]"; continue }

    # El respaldo se escribe ANTES de tocar, y en cada vuelta: si un caso falla
    # con 500, los anteriores ya quedaron registrados.
    ($respaldo | ConvertTo-Json -Depth 6) | Set-Content $archivo -Encoding utf8

    try {
      # 1. Vincular los productos al lead del formulario.
      if ($links.Count -gt 0) {
        $body = @($links | ForEach-Object {
            @{ to_entity_id = $_.id; to_entity_type = 'catalog_elements'
              metadata = @{ quantity = $_.cant; catalog_id = $cat } }
          })
        $json = $body | ConvertTo-Json -Depth 6 -Compress
        [void](Invoke-RestMethod -Uri "$b/api/v4/leads/$($k.form)/link" -Headers $hp -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)))
        "  vinculados $($links.Count) producto(s) al lead del formulario."

        # 2. Desvincularlos del viejo.
        $body2 = @($links | ForEach-Object {
            @{ to_entity_id = $_.id; to_entity_type = 'catalog_elements'
              metadata = @{ catalog_id = $cat } }
          })
        $json2 = $body2 | ConvertTo-Json -Depth 6 -Compress
        [void](Invoke-RestMethod -Uri "$b/api/v4/leads/$($k.viejo)/unlink" -Headers $hp -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json2)))
        "  desvinculados del lead viejo."
        Start-Sleep -Seconds 5
      }

      # 3. Los precios, al final y verificando: Kommo recalcula al vincular.
      Fijar-Price $k.form ([int]$k.total)
      Fijar-Price $k.viejo 0
    } catch {
      "  FALLO: $($_.Exception.Message)"
      "  Este caso queda a medias o sin tocar. Revisar antes de reintentar."
    }
  }

  if (-not $SoloMostrar) {
    ($respaldo | ConvertTo-Json -Depth 6) | Set-Content $archivo -Encoding utf8
    ''; "estado previo guardado en $archivo"
  }
}
