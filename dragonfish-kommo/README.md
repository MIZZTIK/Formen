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

**La llave es el tiempo, no el dato.** La venta no identifica al comprador (ver el
relevamiento más abajo): el teléfono lo junta el iPad del local con un formulario de Kommo,
que el vendedor pasa *después* de cobrar. Por eso el apareo es: para cada venta, buscar los
contactos creados por el usuario del iPad en los N minutos siguientes. **Uno solo → se
asocia. Dos o más → no se adivina, queda sin asociar.**

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

### Qué carga el iPad (auditado por API el 19/8)

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
es el marcador bueno, el `created_by` queda como puente mientras convivan las
cargas viejas. Cuando ya nadie cargue a mano, se saca.

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

### ⚠️ Los leads del iPad empezaron a caer en "Lead pausado" el 18/08

86 leads seguidos entre julio y el 18/08 a la mañana fueron a "Primer contacto"
(`108221247`). Los tres siguientes — 18/08 17:27, 18/08 17:29 y 19/08 08:55 —
cayeron en **"Lead pausado"** (`108221251`), que es la etapa donde el bot de
WhatsApp se queda mudo. Con tres casos no alcanza para afirmarlo, pero el corte
es limpio y esa es justo la etapa de la autopausa que se corrigió en su momento
en el workflow de n8n. **Sin diagnosticar.**

## Dejarlo como servicio en Windows

Opción simple con [NSSM](https://nssm.cc/): `nssm install FormenDFKommo "C:\Program Files\nodejs\node.exe" "C:\EspacioDeTrabajo\Formen\dragonfish-kommo\src\index.js"`.
También sirve una Tarea Programada que ejecute `npm run once` cada N minutos.
