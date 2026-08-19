# Conector Dragonfish → Kommo · Formen

Servicio on-premise que sincroniza **ventas de Dragonfish (Zoo Logic)** hacia **Kommo CRM**:
por cada venta nueva busca el contacto en Kommo (por DNI/teléfono/email), lo crea o
actualiza, y le agrega una **nota** con el detalle del comprobante.

> **Dirección:** Dragonfish → Kommo (solo lectura de Dragonfish, escritura en Kommo).
> **Modelo:** actualizar contacto + nota (no crea leads).

## Cómo funciona

```
Dragonfish (API REST local)  ──polling──►  Conector (Node)  ──HTTPS/OAuth──►  Kommo (cloud)
      comprobantes de venta                cursor + dedupe                   contacto + nota
```

Dragonfish **no emite webhooks**, por eso el conector consulta (polling) el servicio REST
local cada `POLL_INTERVAL_MS` y usa un cursor (`data/cursor.json`) para no reprocesar ventas.

## Requisitos

- Node.js ≥ 18 (usa `fetch` nativo, sin dependencias nativas que compilar).
- La PC/servidor donde corre debe tener **acceso de red al servicio REST de Dragonfish**
  y **salida a internet** hacia Kommo.

## Puesta en marcha

```bash
npm install
cp .env.example .env      # completar valores (ver abajo)
npm run kommo:auth <AUTHORIZATION_CODE>   # obtiene tokens de Kommo
npm run once              # una pasada de prueba (con DRY_RUN=true no escribe en Kommo)
npm start                 # loop continuo
```

### Variables de entorno (`.env`)

Ver `.env.example`. Arrancá con `DRY_RUN=true`: el conector loguea qué haría en Kommo
sin escribir nada. Cuando el mapeo esté validado, poné `DRY_RUN=false`.

## Kommo — crear la integración privada

1. En Kommo: **Ajustes → Integraciones → Crear integración** (privada).
2. Completá `redirect_uri` (puede ser `https://localhost/callback`) y otorgá permisos.
3. Copiá `client_id`, `client_secret` a `.env`.
4. En la pestaña "Claves y alcances" copiá el **authorization_code** (dura 20 min) y corré
   `npm run kommo:auth <CODE>`.
5. Identificá los IDs de campos custom (DNI, etc.) y cargalos en `KOMMO_FIELD_ID_*`.

## ⛔ PROYECTO FRENADO — relevamiento del 2026-08-19 en la PC de Formen

### 1. El servicio REST de Dragonfish no está instalado

En la PC de Formen (`DESKTOP-271F8FR`) solo corre el **"Agente de Acciones Organic"**
(`ZooLogicSA.SR.AO`, puerto 7532, no habla HTTP). No hay servicio de API, ni instalado
ni apagado: bajo `C:\Program Files (x86)\Zoo Logic\` solo está el agente Organic.
El módulo REST es un producto aparte de Zoo Logic — habría que comprarlo
(`soporteapi@zoologic.com.ar`).

Lo que sí hay: **SQL Server `MSSQL$ZOOLOGIC` local**, base `DRAGONFISH_FORMEN`,
esquema `ZooLogic`, accesible con Integrated Security.
Por eso `src/dragonfish/client.js` (cliente REST escrito a ciegas) **no sirve**: si el
proyecto se retoma, se reemplaza por consultas SELECT a esa base.

### 2. 🔴 El bloqueante real: las ventas no tienen dato de contacto

Sobre los últimos 6 meses (703 ventas):

| Dato | Cobertura |
|---|---|
| **Teléfono** | **la columna no existe** en ningún lado del circuito de venta |
| Email (`COMPROBANTEV.EMAIL`) | 1 de 703 |
| CUIT (`COMPROBANTEV.FCUIT`) | 66 de 703 |
| Cliente identificado | 633 de 703 van a `FPERSON=0000000001` (consumidor final) |

`CLIECOM`, `CLIOTRASDIR` y `CONTACTO` están **vacías** (0 filas): no hay e-commerce cargado.
La tabla `CLI` no tiene columna de teléfono.

El conector busca el contacto en Kommo por DNI/teléfono/email, y los contactos de Kommo
vienen de WhatsApp — la llave natural es el teléfono. **No hay con qué matchear.**

### 2b. El iPad del local: existe, captura teléfono, y NO sirve para aparear

En el local hay un iPad con un formulario de Kommo. Los contactos que genera se ven en la
cuenta como creados por el usuario **FormenAR (`15483335`)**, en horario de local
(8-12h y 17-21h), todos con teléfono y sin email. Son **69 entre el 1/7 y el 19/8/2026**.
No usan el campo "Términos y condiciones" (`445074`) ni hay ninguna *fuente* configurada
en la cuenta, así que no se los distingue por origen: el único marcador es `created_by`.

Se probó **aparear por cercanía temporal** (contacto del iPad ↔ venta de Dragonfish).
No funciona:

| | contactos con 1 sola venta a ±10 min | con ninguna |
|---|---|---|
| **Real** | 9 de 69 (13%) | 58 |
| **Placebo** (mismas ventas, 7 días antes) | 10 de 69 | 58 |

El placebo da *más* aciertos que el apareo real → **señal cero**. Además, los pocos
aciertos no son únicos: hay pares de contactos cargados con un minuto de diferencia que
apuntan a la misma venta. La distancia típica a la venta más cercana (-40 a -150 min,
o sea el contacto ANTES) es la que da el azar con ~4 ventas diarias en 12 horas de local.

**Conclusión: el iPad captura a quien entra al local, no a quien compra.** Los dos sistemas
registran poblaciones distintas y no hay ninguna llave que los una.

### 2c. Qué haría falta para destrabarlo

Es una decisión de Agustín sobre el proceso de atención, no de software:

- **(a)** Pedir el dato **en la caja, al cobrar**, en vez de a la entrada. Con eso el apareo
  temporal pasa a funcionar sin cambiar nada más de lo diseñado.
- **(b)** Cargar el teléfono o el DNI **en la venta de Dragonfish**. Es la llave exacta y la
  solución robusta, pero exige que el vendedor tipee en el sistema de facturación.
- **(c)** Dar vuelta el proyecto (Kommo → Dragonfish) o archivarlo.

La reproducción del análisis quedó en [`cruce.sql`](cruce.sql).

### 3. Mapeo de la base, para cuando se destrabe

Ventas: `ZooLogic.COMPROBANTEV` (cabecera) + `ZooLogic.COMPROBANTEVDET` (detalle).

| Para qué | Columna |
|---|---|
| ID de dedupe | `CODIGO` char(38) |
| Cursor de polling | `FALTAFW` + `HALTAFW` (alta en el sistema, no fecha de factura) |
| Fecha de venta | `FFCH` |
| Total | `FTOTAL` |
| Numeración | `FLETRA` + `FPTOVEN` + `FNUMCOMP` |
| Cliente | `FPERSON` → `ZooLogic.CLI.CLCOD`; además `FCLIENTE`, `FCUIT`, `EMAIL` |
| Filtro | `ANULADO = 0` |

Tipos en uso: `FACTTIPO=2` letra B (10.883, el grueso) y letra A (697).

> Ojo: `OBJECT_ID('COMPROBANTEV')` devuelve NULL — las tablas están en el esquema
> `ZooLogic`, no en el del usuario. Hay que calificarlas siempre.

En producción el conector necesita su **propio usuario SQL de solo lectura** (pedírselo al
soporte de Zoo Logic): no puede correr con las credenciales de Windows de una persona.

## Estructura

```
src/
  config.js            carga y valida .env
  logger.js            logging con niveles
  cursor.js            cursor de polling (JSON) + dedupe
  dragonfish/client.js cliente REST de Dragonfish  (⚠️ a confirmar)
  kommo/
    client.js          cliente Kommo (OAuth, contactos, notas)
    tokenStore.js      persistencia de tokens (rotan)
  mapping.js           venta DF -> contacto/nota Kommo
  sync/salesToKommo.js orquestación del flujo
  index.js             entrypoint (loop / --once)
scripts/kommo-auth.js  intercambia authorization_code por tokens
```

## ⭐ Cómo se despliega de verdad: `powershell/conector.ps1`

**En la PC del local NO hay Node** (verificado el 19/8/2026), y es la máquina de
facturación de un negocio sin nadie que la administre: instalarle un runtime y
decenas de paquetes npm es peor negocio que evitarlo. Por eso el conector que se
despliega es el de PowerShell, que **no necesita instalar nada**: usa el
`SqlClient` de .NET (ya viene con Windows) y la API REST de Kommo.

La versión Node (`src/`) queda como referencia del diseño y para el día que esto
corra en un servidor de verdad. **La que se usa es la de `powershell/`.**

```powershell
cd powershell
copy conector.config.example.json conector.config.json   # completar token
.\conector.ps1 -Once      # una pasada de prueba (dryRun=true: no escribe en Kommo)
.\conector.ps1 -Medir     # reporte de la tasa de apareo
```

Para que corra solo, Programador de tareas → tarea que ejecute
`powershell -ExecutionPolicy Bypass -File <ruta>\conector.ps1 -Once`
cada 10 minutos, con "Ejecutar tanto si el usuario inició sesión como si no".
Es más robusto que dejar el loop abierto: si la PC se reinicia, la tarea vuelve
sola.

### El orden de puesta en marcha (importante)

1. Agustín cambia el proceso: **el iPad se pasa al cobrar**, lo más pegado
   posible al cobro.
2. El conector corre con `"dryRun": true`. **No toca Kommo**, solo mide.
3. A las dos semanas, `.\conector.ps1 -Medir` da la tasa real de asociación.
4. Recién con una tasa buena se pone `"dryRun": false`.

Saltearse el paso 2 es cómo se descubre a los tres meses que media docena de
compras quedaron en la ficha equivocada.

### Pendientes antes de producción

- **Usuario SQL de solo lectura** para el conector (pedírselo al soporte de Zoo
  Logic). Requiere SQL Server en modo de autenticación mixta. Mientras tanto el
  script cae en Integrated Security, que sirve para probar pero no para dejarlo
  corriendo con las credenciales de Windows de una persona.
- **Integración privada propia en Kommo**, distinta de la del bot de n8n: si
  comparten token, al rotar uno se cae el otro.
- **Validar la sintaxis del script**, que se escribió sin poder ejecutarlo:
  ```powershell
  $e=$null; [System.Management.Automation.Language.Parser]::ParseFile("$PWD\conector.ps1",[ref]$null,[ref]$e); $e
  ```
- **Zona horaria**: el apareo compara `created_at` de Kommo (epoch UTC) contra
  la hora local de Dragonfish. Sale bien mientras la PC esté en hora argentina.

## Dejarlo como servicio en Windows

Opción simple con [NSSM](https://nssm.cc/): `nssm install FormenDFKommo "C:\Program Files\nodejs\node.exe" "C:\EspacioDeTrabajo\Formen\dragonfish-kommo\src\index.js"`.
También sirve una Tarea Programada que ejecute `npm run once` cada N minutos.
