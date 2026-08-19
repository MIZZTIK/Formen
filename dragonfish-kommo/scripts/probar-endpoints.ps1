# Prueba endpoints del REST de Dragonfish y volca la FORMA REAL de la respuesta.
# Correr DESPUES de descubrir-dragonfish.ps1, cuando ya sabes puerto y credenciales.
#
# Uso:
#   .\probar-endpoints.ps1 -Base "http://localhost:8009" -Token "xxx" -IdCliente "yyy" -BaseDeDatos "DEPOSITO"
#
# Solo hace GET. No escribe nada en ningun lado.

param(
  [Parameter(Mandatory=$true)][string]$Base,
  [string]$Token = '',
  [string]$IdCliente = '',
  [string]$BaseDeDatos = '',
  [string]$Salida = 'muestras-dragonfish.json'
)

$ErrorActionPreference = 'SilentlyContinue'

# Los nombres de header varian por version: probamos las variantes conocidas.
$variantesHeaders = @(
  @{ nombre = 'A: Authorization + IdCliente + BaseDeDatos'
     h = @{ 'Content-Type'='application/json'; 'Authorization'=$Token; 'IdCliente'=$IdCliente; 'BaseDeDatos'=$BaseDeDatos } },
  @{ nombre = 'B: Bearer'
     h = @{ 'Content-Type'='application/json'; 'Authorization'="Bearer $Token"; 'IdCliente'=$IdCliente; 'BaseDeDatos'=$BaseDeDatos } },
  @{ nombre = 'C: sin auth (ver que error da)'
     h = @{ 'Content-Type'='application/json' } }
)

$rutas = @(
  '/api.Dragonfish/Comprobante',
  '/api.Dragonfish/Comprobante/',
  '/api.Dragonfish/Cliente',
  '/api.Dragonfish/Articulo',
  '/api.Dragonfish/Stock',
  '/api.Dragonfish/Consulta',
  '/Comprobante',
  '/Cliente'
)

$muestras = @{}

foreach ($v in $variantesHeaders) {
  "`n########## HEADERS $($v.nombre) ##########"
  foreach ($ruta in $rutas) {
    $url = "$Base$ruta"
    try {
      $r = Invoke-WebRequest -Uri $url -Headers $v.h -TimeoutSec 8 -UseBasicParsing
      "`n--- OK $($r.StatusCode)  $ruta"
      $cuerpo = $r.Content
      # Mostramos las primeras 1500 letras: alcanza para ver los nombres de campo.
      $cuerpo.Substring(0, [Math]::Min(1500, $cuerpo.Length))
      if (-not $muestras.ContainsKey($ruta)) { $muestras[$ruta] = $cuerpo }
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      $msg  = $_.Exception.Message
      if ($code) { "--- HTTP $code  $ruta   ($msg)" }
      else       { "--- sin respuesta  $ruta" }
    }
  }
}

if ($muestras.Count -gt 0) {
  $muestras | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 $Salida
  "`nGuardadas $($muestras.Count) muestras en $Salida  <- pasame ESTE archivo."
} else {
  "`nNinguna ruta respondio 200. Anotá que codigo devolvio cada una (401 = existe pero falta auth; 404 = ruta equivocada; sin respuesta = puerto equivocado)."
}
