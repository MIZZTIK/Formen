# Conector Dragonfish → Kommo · Formen

Servicio on-premise que sincroniza **ventas de Dragonfish (Zoo Logic)** hacia **Kommo CRM**:
por cada venta nueva busca a qué contacto corresponde y le agrega una **nota** con el
detalle del comprobante.

> **Dirección:** Dragonfish → Kommo (solo lectura de Dragonfish, escritura en Kommo).
> **Modelo:** nota en el contacto (no crea contactos ni leads).

## Cómo funciona

```
SQL Server local  ──polling──►  conector.ps1  ──HTTPS──►  Kommo (cloud)
 DRAGONFISH_FORMEN              cursor + apareo temporal   nota en el contacto
```

Dragonfish **no emite webhooks**, por eso el conector consulta la base cada N minutos y usa
un cursor (`data/cursor.json`) para no reprocesar ventas.

La venta no identifica al comprador (ver el relevamiento más abajo), así que la
llave operativa sale del formulario de Kommo que se completa al cobrar: últimos
4 dígitos del comprobante, sistema de venta (`Black` / `Formen`) y una ventana
corta de tiempo. Con el campo de comprobante activo, el conector solo asocia si
el contacto de la ventana trae esos 4 dígitos y coinciden con la venta. Si está
configurado el campo de sistema, también exige que coincida con la base de
Dragonfish. **Uno solo → se asocia. Dos o más → no se adivina, queda sin
asociar. Ninguno con comprobante coincidente → no escribe.**

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

## Relevamiento del 2026-08-19 en la PC de Formen (por qué el diseño es este)

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

### 2d. Exploración del 24/8: Dragonfish no resuelve el dueño del encargo

Se copió `explorar-encargos.ps1` a `C:\FormenConector\` y se corrió en la PC del
local. Resultado:

| Pregunta | Resultado |
|---|---|
| Tablas de taller / encargo / pedido | existen `LIQTALLER`, `TALLER`, `TALLERPROC`, pero las tres tienen 0 filas |
| Ventas últimos 90 días | 381 ventas; `FPERSON` y `FCLIENTE` vienen cargados en todas |
| Valor real de `FCLIENTE` | 356 de 381 son `Consumidor, Final`; los nombres reales son casos aislados |
| Email | 1 de 381 |
| Teléfono en `CLI` | no hay columnas de teléfono/celular; solo nombre y email |

Conclusión: para el flujo del mostrador, Dragonfish sigue sin dar una llave
usable hacia Kommo. Si una venta queda como encargo, ese dato no aparece en las
tablas obvias de taller y la ficha `CLI` tampoco tiene teléfono. El formulario
de Kommo sigue siendo la llave principal.

El siguiente refuerzo fue pedir en el formulario un campo con los últimos 4
dígitos del comprobante. Con `comprobanteUltimos4FieldName` o
`comprobanteUltimos4FieldId` configurado, el apareo deja de ser solo temporal y
pasa a exacto dentro de la ventana. El fallback por tiempo queda apagado por
defecto (`permitirFallbackTemporalSinComprobante: false`) para evitar que una
venta se cuelgue del contacto siguiente si falta el número.

El 25/8 se confirmó que `Black` y `Formen` no son solo cajas: son bases distintas
en el SQL Server local (`DRAGONFISH_BLACK` y `DRAGONFISH_FORMEN`). El conector
soporta `sql.databases` para leer ambas, marca cada venta con el sistema según
la base de origen y puede comparar ese dato contra el campo `Sistema de venta`
del formulario (`sistemaVentaFieldName` / `sistemaVentaFieldId`). Black aparece
como `FACTTIPO=1` y Formen como `FACTTIPO=2`, así que producción necesita
`tiposVenta: [1, 2]`.

### 2e. Exploración del 24/8: recibo, productos y medios de pago

Se corrió `explorar-recibos.ps1` y después `explorar-recibos-detalle.ps1` en la
PC del local. Resultado:

| Pregunta | Resultado |
|---|---|
| Recibos | `RECIBO` y `RECIBODET` tienen 0 filas; no son la fuente para este flujo |
| Cabecera de venta | `COMPROBANTEV` guarda el comprobante, fecha, total y cliente |
| Detalle de prendas | `COMPROBANTEVDET.CODIGO = COMPROBANTEV.CODIGO` |
| Pagos | `CUPONES.COMP = COMPROBANTEV.CODIGO` |
| Caja | `MOVCAJA` sirve para ver movimientos y nombres, pero los montos confiables salen de `CUPONES` |

Medios de pago vistos en ventas recientes:

| Código | Medio |
|---|---|
| `0` | PESOS |
| `VI` | VISA |
| `NA` | NARANJA |
| `TR` | Transferencia Bancaria |
| `EL` | ELECTRON |
| `MAE` | MAESTRO |

Conclusión: para la nota de Kommo alcanza con `COMPROBANTEV` + `COMPROBANTEVDET`
y `CUPONES`. El conector agrega productos y pagos cuando ya encontró un contacto
único. Si esa lectura falla, escribe igual la nota básica para no frenar el
apareo.

Además de la nota, el conector puede actualizar campos estructurados de "última
compra" en el contacto, si están configurados en `camposCompra`:

| Campo | Uso |
|---|---|
| Última compra - fecha | filtros por clientes que compraron o no compraron hace X meses |
| Último comprobante | referencia rápida en la ficha |
| Última compra - total | segmentación por valor comprado |
| Últimos 4 comprobante | soporte al apareo y auditoría |
| Última compra - productos | resumen de prendas |
| Última compra - pagos | resumen de medios de pago |

Estos campos se pisan con cada compra nueva. El historial completo queda como
notas, una por compra.

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
cada 10 minutos. Es más robusto que dejar el loop abierto: si la PC se
reinicia, la tarea vuelve sola.

```powershell
schtasks /Create /TN "Formen - Conector Dragonfish a Kommo" /TR "powershell -ExecutionPolicy Bypass -File C:\FormenConector\conector.ps1 -Once" /SC MINUTE /MO 10 /F
```

> **Corre como el usuario logueado, a propósito.** Lo natural sería
> "ejecutar aunque el usuario no haya iniciado sesión", pero hoy el script
> entra a SQL con Integrated Security y `NT AUTHORITY\SYSTEM` no tiene
> permiso sobre `DRAGONFISH_FORMEN`: fallaría en silencio cada 10 minutos.
> Se cambia cuando exista el usuario SQL de solo lectura (ver pendientes).
> Mientras tanto la PC del local queda logueada todo el día.

### El orden de puesta en marcha

El diseño original era: cambiar el proceso, medir dos semanas con
`"dryRun": true`, mirar la tasa con `-Medir`, y recién entonces prender la
escritura. La razón de ese orden es que saltearlo es como se descubre a los tres
meses que media docena de compras quedaron en la ficha equivocada.

**El 19/8/2026 se decidió no esperar** (decisión de Martín, con la advertencia
dada): el cliente quiere ver las compras en las fichas desde el primer día, y
sin eso el proyecto no se percibe funcionando. Queda `"dryRun": false` desde el
arranque.

Lo que hace tolerable el cambio: prender la escritura **no escribe nada hasta que
el proceso del mostrador cambie**. Mientras el iPad se siga usando como antes no
hay matcheos, así que las primeras notas aparecen recién cuando los vendedores
empiezan a cargar al cobrar — con alguien mirando.

El riesgo que se acepta es el del **único candidato equivocado**: un interesado
cargado justo después de la compra de otro. La regla de ambigüedad no lo cubre
(hay un solo candidato, y es el que no es). Por eso, los primeros días hay que
mirar `data\conector.log` y las notas que aparecen en Kommo.

Para apagarlo: `"dryRun": true` de vuelta. Las notas ya escritas quedan y se
borran a mano.

### Vigilancia: qué pasa si se apaga la máquina

Corre solo en una PC de local sin nadie que la administre, así que las fallas
tienen que gritar.

**Si la máquina se apaga, no se pierde ninguna venta.** El cursor guarda hasta
dónde se procesó y al volver se pone al día, aunque hayan pasado días: como los
contactos se buscan en Kommo por ventana de `created_at`, el apareo sale igual
de bien en retrospectiva. Tres salvedades:

1. Mientras está apagada no pasa nada, obviamente.
2. **Si nadie inicia sesión en Windows, la tarea no corre** (ver más arriba por
   qué no puede correr como SYSTEM). Se arregla con el usuario SQL propio.
3. Un corte de luz **durante la escritura del cursor** dejaba el archivo cortado
   por la mitad; al arrancar volvía al principio del día y **reprocesaba ventas
   ya anotadas, duplicando notas en las fichas**. Resuelto: `Save-Cursor`
   escribe a un temporal y recién después reemplaza (`Move-Item -Force`). Si
   aun así el cursor queda ilegible, `Get-Cursor` lo deja escrito en el log
   como error, no en silencio.

Hardening de la Tarea Programada (que corra apenas puede si se perdió una
ejecución por estar apagada):

```powershell
$n = "Formen - Conector Dragonfish a Kommo"
Set-ScheduledTask -TaskName $n -Settings (New-ScheduledTaskSettingsSet `
  -StartWhenAvailable -MultipleInstances IgnoreNew `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 30))
```

**Aviso por Telegram.** `Invoke-PasadaVigilada` lleva la cuenta en
`data\estado.json` y avisa después de N pasadas fallidas seguidas (`avisos.
fallosSeguidosParaAvisar`, por defecto 3), **no repite** hasta que se recupere,
y avisa también la recuperación. El token va en `conector.config.json`, que está
en `.gitignore`. Se configura con `set-telegram.ps1` (tampoco versionado).

> El bot **solo envía**. Nunca `getUpdates` ni `setWebhook`: el mismo token lo
> usa otro bot haciendo polling y se rompería en silencio.

### Pendientes antes de producción

- **Usuario SQL de solo lectura** para el conector (pedírselo al soporte de Zoo
  Logic). Requiere SQL Server en modo de autenticación mixta. Mientras tanto el
  script cae en Integrated Security, que sirve para probar pero no para dejarlo
  corriendo con las credenciales de Windows de una persona.
- **Integración privada propia en Kommo**, distinta de la del bot de n8n: si
  comparten token, al rotar uno se cae el otro.
- **Zona horaria**: el apareo compara `created_at` de Kommo (epoch UTC) contra
  la hora local de Dragonfish. Verificado el 19/8: los horarios de los dos lados
  coinciden con el horario del local. Se rompe si alguien cambia la zona de la PC.
- **Falso positivo por uso mixto del iPad**: si el iPad se sigue usando también
  para gente que solo entra a mirar, un interesado cargado justo después de la
  venta de otro se lleva la nota equivocada. La regla de "dos candidatos → no
  asocio" no cubre este caso, porque hay un solo candidato y es el que no es.
  Se diluye cuando la carga al cobrar sea la mayoría de las cargas.
- **`limit=250` sin paginar** en `Get-ContactosEnVentana`: irrelevante con
  ventanas de 10 minutos, pero si alguien agranda `ventanaMin` mucho, trunca.

## Estado al 19/08/2026 — desplegado y escribiendo

Instalado en **`C:\FormenConector\`** (fuera del perfil de usuario, para que la
Tarea Programada lo vea), con la tarea cada 10 minutos y **`"dryRun": false`**
(ver "El orden de puesta en marcha" más arriba: se decidió no esperar las dos
semanas de medición).

Tiempo hasta que la nota aparece en Kommo: `esperaMin` (15) desde la venta, más
lo que falte para la próxima pasada de la tarea (10). **Entre 15 y 25 minutos.**
No es instantáneo y conviene decirlo, o parece que no funciona.

Verificado end to end ese día:

- SQL responde y el cursor avanza (4 ventas leídas en una pasada de prueba).
- Kommo responde **200, sin 401 ni 400** — la URL con corchetes
  (`filter[created_at][from]`) pasa bien por `Invoke-RestMethod`.
- El filtro por `created_by` del iPad devuelve lo que tiene que devolver.

**Todavía no aparea nada, y está bien:** el cambio de proceso no ocurrió.
Los 4 días previos al 19/8 muestran las dos poblaciones separadas —

| iPad | ventas |
|---|---|
| — | 15/08 18:44 · 19:58 · 20:03 |
| — | 18/08 10:13 · 11:11 |
| 18/08 17:27 · 17:29 | — |
| — | 18/08 19:17 · 19:46 |
| 19/08 08:55 | — |

Dos datos de escala que conviene tener a mano: son **~4 ventas por día**
(7 en 4 días, con el 17/8 feriado), así que aun con apareo perfecto esto son
unas 4 notas diarias; y el iPad se usa **menos que las ventas** (3 cargas
contra 7 ventas). El cuello es el uso del iPad, no el software.

### 🔴 CORRECCIÓN del 20/8: `created_by 15483335` es el aviso de "prenda lista"

Todo lo que sigue en esta sección se escribió creyendo que los contactos creados
por el usuario FormenAR (`15483335`) eran las cargas del iPad. **Casi seguro que
no lo son.** Al revisar cuatro de ellos el 20/8:

| | |
|---|---|
| Contactos | Sergio Kunzi, Ariel Romero, bruno ramirez, Lucas Godoy |
| Todos | `created_by 15483335`, teléfono en 10 dígitos pelados, sin etiqueta |
| Todos | lead en "Lead pausado" **con conversación de chat** |
| Sergio Kunzi | **dos leads creados con 2 minutos de diferencia** |

Se revisaron dos de esas fichas en la interfaz (leads `19804915` y `19815643`) y
la secuencia es siempre la misma:

```
17:35  FormenAR   El valor del campo «Teléfono» se establece en «3794655853»
17:36  FormenAR   "¡Buenas! Me comunico de Formen para informarle que su ambo
                   ya se encuentra listo para retirar. ¡Lo esperamos!"  Entregado
17:36  SalesBot (Detener bot)  Nuevo estatus: Lead pausado <- de Primer contacto
17:40  Lucas Godoy  "Voy enseguida. Hasta que hora tienen abierto?"
```

Son **cargas manuales del personal, de otro proceso: avisar que el ambo está
listo para retirar.** No son capturas de comprador en el mostrador.

Eso explica de una todo lo que se venía arrastrando:

- el teléfono en 10 dígitos pelados lo tipea una persona, tal cual;
- **el misterio de "Lead pausado" queda resuelto y no es un bug**: lo hace un
  Salesbot llamado "Detener bot" cuando el personal manda un mensaje manual,
  para que el bot no le hable encima al operador. Por diseño. Lo que cambió el
  18/8 fue que empezaron a usar este flujo, no el workflow de n8n;
- nunca coincidían con las ventas porque a esta gente se la carga **cuando la
  prenda está lista, días después de haber comprado**.

**Las "69 cargas del iPad" medidas el 19/8 nunca fueron cargas del iPad**, y los
números de esta sección hay que leerlos con esa advertencia.

**Consecuencia operativa, ya aplicada:** con la escritura prendida ese marcador
es peligroso, y por una razón más fuerte que "es confuso" — marca **una
población distinta y activa**. A esa gente le avisan que su prenda está lista,
contesta "voy enseguida" y **puede aparecer a pagar veinte minutos después**.
Con el marcador viejo, esa venta se le pegaba a quien recibió el aviso, aunque
el que pagó fuese otro. Se desactivó poniendo **`kommo.ipadUserId = -1`** en la
config del local: `Test-ContactoDelLocal` reconoce **solo la etiqueta del
formulario**. No cuesta nada, porque el matcheo estaba en 0 de 6.

### Qué carga el iPad (auditado por API el 19/8, ver corrección arriba)

Hasta el 19/8/2026 **no había ningún formulario de por medio**: los 89 leads del
usuario FormenAR tienen `source_id` en `null`, sin nota de envío y con el campo
de lead "Formulario" (`535306`) vacío. Era **carga manual desde la app de Kommo**
logueada como FormenAR. El formulario web existía —hasta con una etapa propia
"Formulario" (`108223331`) en el embudo— pero **nunca se había usado ni una vez**.

Ese mismo día se lo configuró y se lo puso en marcha:

| | |
|---|---|
| Link | `https://forms.kommo.com/rzrcvzw` (formulario `1716275`) |
| Campos obligatorios | Nombre completo, Teléfono |
| Campos opcionales | Correo, Fecha de nacimiento |
| Etiqueta | **`local`** |
| Etapa del lead | Formulario (`108223331`) |
| Responsable | FormenAR (`15483335`) |

Antes de tocarlo, Correo y **Fecha de nacimiento** eran obligatorios y el nombre
no: al lado de la caja, con el cliente yéndose, eso es exactamente el formulario
que no se usa (y de 703 ventas, una sola tenía email). Se le desactivó también
el autocompletado del navegador: en un dispositivo de mostrador compartido
ofrece los datos del cliente anterior.

### ⚠️ El formulario crea los contactos con `created_by = 0`

Verificado con un envío de prueba (contacto `43230669`): el formulario **no**
crea los contactos a nombre de FormenAR sino con `created_by = 0`. El filtro
original del conector —"contactos creados por el usuario del iPad"— los habría
dejado pasar de largo, y **todas las ventas habrían dado "sin candidato" sin un
solo error en el log**.

La buena noticia del mismo envío: **la etiqueta `local` queda tanto en el lead
como en el contacto**, y la consulta por ventana de `created_at` ya devuelve
`_embedded.tags` sin pedir nada extra. Por eso `Test-ContactoDelLocal` acepta un
contacto si tiene la etiqueta **o** si lo creó el usuario FormenAR: la etiqueta
es el marcador bueno, el `created_by` era el puente mientras convivieran las
cargas viejas.

**Ese puente está desactivado desde el 20/8** (`kommo.ipadUserId = -1`, ver la
corrección más arriba): el `created_by` no marcaba el mostrador sino, muy
probablemente, la sesión de WhatsApp Lite. El código lo sigue soportando por si
alguna vez hace falta un segundo marcador; hoy la etiqueta es el único.

Se captura **nombre y teléfono, y nada más**: nunca email, nunca "Position", y
el checkbox "Términos y condiciones" (`445074`) no se usó jamás. Tampoco hay
*fuentes* configuradas en la cuenta, así que `created_by` sigue siendo el único
marcador.

Ojo con ese marcador: **`created_by 15483335` no es solo el iPad.** El 24/06 a
las 03:53 entraron **192 contactos de una importación masiva** con el mismo
usuario. Para el apareo es inofensivo (a esa hora no hay ventas), pero el
marcador significa "el usuario FormenAR", no "el iPad".

### 🔴 El teléfono se guarda en dos formatos y genera fichas duplicadas

| origen | formato | casos |
|---|---|---|
| iPad | `3794801505` (10 dígitos pelados) | 65 de 69 |
| WhatsApp y otros canales | `+5493794801505` | 2422 de 2547 |

Kommo no los reconoce como la misma persona: **17 de las 69 cargas del iPad
(25%) son un duplicado de un contacto que ya existe**. Sin corregirlo, la nota
de la compra cae en el mellizo y la ficha donde vive toda la conversación no se
entera de nada.

El conector lo resuelve en `Resolve-ContactoDestino`: normaliza a los últimos 10
dígitos, busca por `query=`, y si aparece **una sola** ficha con el mismo
teléfono creada por otro usuario, escribe ahí.

> **El criterio no es la antigüedad.** Lo intuitivo es "el viejo es el original",
> y está mal: en los casos medidos el mellizo de WhatsApp suele ser **más nuevo**
> (la persona se carga en el local y escribe entre 12 y 52 minutos después). Lo
> que distingue a la ficha buena es **quién la creó** — la que vino por un canal
> tiene la conversación, la del iPad es un nombre y un teléfono.

Simulado sobre las 69 cargas reales: **17 redirigen, 50 se quedan en la ficha del
iPad, 2 sin teléfono usable, 0 ambiguas.**

Queda una limitación que no se puede tapar desde acá: si el mellizo de WhatsApp
todavía no existe cuando el conector corre (aparece 52 minutos después y el
conector mira a los 10), la nota queda en la ficha del local.

> **El formulario NO resuelve esto**, contra lo que parecía al ver el prefijo
> `+54` en el editor. El envío de prueba guardó **`+543794000001`**: el prefijo
> es el del país, sin el `9` de celular que sí lleva WhatsApp
> (`+5493794000001`). Siguen siendo dos textos distintos para Kommo, así que
> **los duplicados se van a seguir creando** y la normalización del conector
> sigue haciendo falta. Para que coincidieran de verdad, el vendedor tendría que
> tipear el `9` adelante — frágil, no vale la pena pedirlo. Limpiar los
> duplicados que ya existen en la base es un trabajo aparte, de higiene de CRM.

### ~~Los leads del iPad empezaron a caer en "Lead pausado" el 18/08~~ — resuelto

Se había anotado como posible regresión del workflow de n8n: 86 leads seguidos a
"Primer contacto" y de golpe, el 18/08, tres a "Lead pausado".

**No es un bug.** Lo hace un Salesbot de Kommo llamado **"Detener bot"** cuando
el personal manda un mensaje manual desde la ficha, para que el bot no le hable
encima al operador. Lo que cambió el 18/08 fue que empezaron a usar el flujo de
"tu prenda está lista", no el workflow.

## Dejarlo como servicio en Windows

Opción simple con [NSSM](https://nssm.cc/): `nssm install FormenDFKommo "C:\Program Files\nodejs\node.exe" "C:\EspacioDeTrabajo\Formen\dragonfish-kommo\src\index.js"`.
También sirve una Tarea Programada que ejecute `npm run once` cada N minutos.
