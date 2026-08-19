# Descubrimiento del servicio REST de Dragonfish (Zoo Logic) en la PC de Formen.
# Solo LEE: lista servicios, puertos, archivos de config y hace GETs de prueba.
# Uso:  powershell -ExecutionPolicy Bypass -File .\descubrir-dragonfish.ps1 > reporte.txt

$ErrorActionPreference = 'SilentlyContinue'
function Titulo($t) { "`n=== $t ===" }

Titulo "1. Servicios Windows con pinta de Dragonfish / Zoo Logic"
Get-Service | Where-Object { $_.Name -match '(?i)dragon|zoo|dfish' -or $_.DisplayName -match '(?i)dragon|zoo' } |
  Select-Object Status, Name, DisplayName | Format-Table -AutoSize

Titulo "2. Procesos con pinta de Dragonfish"
Get-Process | Where-Object { $_.ProcessName -match '(?i)dragon|zoo|dfish' } |
  Select-Object Id, ProcessName, Path | Format-Table -AutoSize

Titulo "3. Puertos TCP en escucha (con el proceso dueno)"
Get-NetTCPConnection -State Listen |
  Select-Object LocalAddress, LocalPort,
    @{n='Proceso';e={ (Get-Process -Id $_.OwningProcess).ProcessName }},
    @{n='Exe';e={ (Get-Process -Id $_.OwningProcess).Path }} |
  Sort-Object LocalPort | Format-Table -AutoSize

Titulo "4. Carpetas de instalacion"
$raices = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", 'C:\', 'D:\')
foreach ($r in $raices) {
  Get-ChildItem -Path $r -Directory -Depth 1 |
    Where-Object { $_.Name -match '(?i)dragon|zoo' } |
    Select-Object FullName, LastWriteTime
}

Titulo "5. Archivos de config dentro de esas carpetas"
foreach ($r in $raices) {
  $dirs = Get-ChildItem -Path $r -Directory -Depth 1 | Where-Object { $_.Name -match '(?i)dragon|zoo' }
  foreach ($d in $dirs) {
    Get-ChildItem -Path $d.FullName -Recurse -Depth 3 -Include *.config,*.json,*.ini,*.xml |
      Select-Object -First 40 FullName, Length, LastWriteTime | Format-Table -AutoSize
  }
}

Titulo "6. Sitios / puertos de IIS (si el REST corre ahi)"
Import-Module WebAdministration
Get-Website | Select-Object Name, State, PhysicalPath,
  @{n='Bindings';e={ ($_.Bindings.Collection | ForEach-Object { $_.bindingInformation }) -join ', ' }} |
  Format-Table -AutoSize

Titulo "7. Sondeo HTTP de puertos candidatos"
# 8009 es el puerto tipico del servicio; probamos tambien lo que aparezca en el punto 3.
$puertos = @(8009, 8080, 8000, 9000, 5000, 8888)
foreach ($p in $puertos) {
  foreach ($ruta in @('/', '/api.Dragonfish/', '/api.Dragonfish/Comprobante')) {
    $url = "http://localhost:$p$ruta"
    try {
      $r = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing
      "OK   $url  -> $($r.StatusCode)  [$($r.Headers['Server'])]"
      ($r.Content | Select-Object -First 1).Substring(0, [Math]::Min(400, $r.Content.Length))
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      if ($code) { "HTTP $code  $url   <- responde algo, el servicio esta ahi" }
    }
  }
}

Titulo "8. Version de Node instalada (la necesita el conector)"
node --version
npm --version

"`nListo. Guarda esta salida y pasamela entera."
