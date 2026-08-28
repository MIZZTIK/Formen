# Formen sobre Kommo + n8n — contexto del proyecto

Dos piezas para **Formen** (sastrería de autor en Corrientes, marca de Classic SRL), sobre
**Kommo (CRM) + n8n (orquestación) + OpenAI**:

1. **El bot de WhatsApp** — responde consultas de catálogo y **deriva a humano** (no agenda).
2. **El conector Dragonfish → Kommo** — lleva las ventas del local al CRM. Corre en la PC del
   local, no acá (ver su sección más abajo).

| | **Formen** |
|---|---|
| Rubro | Indumentaria masculina / sastrería (Corrientes, AR) |
| Canales | WhatsApp, Instagram |
| Kommo | `adminformenar.kommo.com` |
| n8n | `n8n-06ir.srv1605341.hstgr.cloud` → `/webhook/formen` |
| Workflow vigente | `formen/workflow-formen.json` |
| Modelo | gpt-4.1 |
| Agencia | **Boomerang** |

> **Formen es de Boomerang, no de Consultoría Digital.** No va al Kanban del equipo y no comparte
> servidores, cuentas ni credenciales con la otra agencia.
>
> El asistente de **AVC Soluciones Empresariales** vivía en este repo y se mudó a `../AVC`
> el 2026-08-28: es cliente de Consultoría Digital y no tenía nada que hacer acá. Comparte
> arquitectura (el mismo truco del campo vehículo y del Salesbot por API) y varios de los gotchas
> de abajo, así que si aparece un problema raro de Kommo, mirar también ese repo.

---

## ⚠️ LA RESTRICCIÓN QUE EXPLICA TODO EL DISEÑO

La cuenta tiene **WhatsApp nativo de Kommo** y está en **plan Avanzado**.
Eso impone dos límites que condicionan toda la arquitectura:

1. **n8n NO puede enviarle el mensaje al cliente.** El canal nativo de Kommo no expone API de envío.
   La única salida es el **Salesbot de Kommo**.
2. En plan **Avanzado** (no Enterprise) NO se puede:
   - usar el disparador *"cuando un campo es actualizado"*, ni
   - **insertar un campo PERSONALIZADO** en el mensaje del Salesbot (el selector solo lista los predefinidos).

### La solución: campo "vehículo" + lanzar el bot por API

```
Kommo (mensaje entrante) → webhook → n8n → AI Agent
   → n8n ESCRIBE la respuesta en un campo PREDEFINIDO del lead (utm_content)
   → n8n LANZA el Salesbot por API  →  el bot envía [utm_content] al cliente
```

- **Campo vehículo** = `utm_content` (es `tracking_data`, predefinido → sí se puede insertar en el bot).
- **Lanzar el bot**: `POST https://<subdominio>.kommo.com/api/v2/salesbot/run`
  body `[{ "bot_id": N, "entity_id": <leadId>, "entity_type": 2 }]` (2 = leads). Ojo: es **api/v2**, no v4.
- El mensaje del Salesbot es **solo** `[utm_content]`, **sin disparador** (lo lanzamos nosotros).

---

## Datos de la cuenta (IDs; los secretos NO están acá — ver `docs/credenciales.md`)

- Pipeline `14000647`. Etapas: Incoming `108058027` · Primer contacto `108221247` ·
  **Lead pausado `108221251`** · **Formulario `108223331`** (donde caen los clientes del local).
- Campos del lead: `utm_content` **`326786`** (vehículo) · `bot_buffer` `2084715` ·
  `Respuesta_bot` `1741927` *(sin uso)* · **`Dragonfish comando` `2094635`** ·
  **`Dragonfish estado` `2094637`**.
- Campos del contacto que usa el conector: `Position` (en la UI se ve como **"Cargo"**) para los
  últimos 4 del comprobante, y `Sistema de venta` (Black / Formen) para desempatar.
- Salesbot **"FORMEN N8N BOT"**, `bot_id` **`57555`**.
- Usuario Kommo (para asignar tareas): FormenAR `15483335`.
- Catálogo de productos: `catalogId` **`12088`**.
- Telegram de avisos: bot **@FormenAYBot**, chat de Agustín (dueño) **`8665518446`**.
- Credenciales n8n: Kommo `XFOpX4xAM95NWBU6` · Telegram `iHWlHjVPTlIb72xG` · OpenAI `tNtJ2bbWHUG4lYiX`.

---

## 🔴 Gotchas críticos (leer antes de tocar nada)

Ver el detalle completo en **`docs/gotchas.md`**. Los que más duelen:

1. **Kommo NO soporta emojis.** Su base es MySQL `utf8` (3 bytes), no `utf8mb4`. **Cualquier campo trunca
   en el primer emoji astral.** Esto rompe dos cosas:
   - la respuesta del bot (llega cortada a la mitad) → el prompt prohíbe emojis + el parseo los borra;
   - **el buffer**, si el *cliente* manda un emoji → el JSON queda corrupto y **el bot se traba**
     → "Preparar buffer" limpia emojis antes de guardar.
2. **Límite de caracteres del vehículo**: `utm_content` aguanta ~2000 (3000 da 400). Se trunca a 1900.
   *(Un campo de tipo texto común aguanta 256 — por eso no sirve `Respuesta_bot`.)*
3. **Kommo dispara el webhook varias veces por mensaje** → duplicados. Se resuelve con el **buffer**
   (dedup por static data NO alcanza: falla con mensajes casi simultáneos).
4. **Kommo devuelve el body como string en `$json.data`** → `JSON.parse($json.data)`.
   Los `field_id` vienen como **string** → comparar con `Number(...)`.
5. **PATCH**: `/leads/{id}` espera **objeto** `{...}`; `/leads` (colección) espera **array** `[{"id":...}]`.
6. **No hay webhook de mensajes SALIENTES** en Kommo. Por eso la pausa por intervención humana se detecta
   por **etapa del lead**, no por "el operador escribió".
7. **WhatsApp Business API tiene ventana de 24 h** (error 3108): no se puede avisar por WhatsApp a alguien
   que no escribió en las últimas 24 h. Por eso los avisos internos van por **Telegram + tarea en Kommo**.

---

## Anatomía del workflow

```
Webhook → Dedup → Edit Fields → ¿entrante? → Traer lead → Estado lead → ¿Pausado?
  └─(no pausado)→ Preparar buffer → Guardar buffer → Esperar 8s → Releer buffer
                  → ¿Último mensaje? ─(no soy el último: muere)
                  → Limpiar buffer → AI Agent
                  → Parsear respuesta IA → Mover etapa
                  → … → Escribir utm_content → Lanzar Salesbot → [notificaciones]
```

**Piezas clave:**
- **Buffer / debounce (8 s):** acumula los mensajes del cliente en `bot_buffer` con un timestamp.
  Al despertar, si el `ts` cambió es que llegó otro mensaje → esa ejecución **muere**; solo la última
  contesta, con todos los mensajes juntos. Resuelve duplicados y mensajes fragmentados.
  *(No usar `$getWorkflowStaticData` para esto: no es confiable con ejecuciones concurrentes.)*
- **Parseo robusto:** aísla el JSON del primer `{` al último `}`; si falla, rescata `reply`/`respuesta`
  con regex; si no, manda un mensaje seguro. **Nunca** puede llegarle el JSON crudo al cliente.
- **Pausa por intervención humana:** si el lead está en la etapa "Lead pausado" (`108221251`), el bot
  corta antes de responder y de mover etapas.

### Derivación y avisos
- El bot **nunca se auto-pausa** al derivar: sigue respondiendo y solo etiqueta **"Requiere humano"**.
  *(Antes se mandaba a "Lead pausado" y quedaba mudo para todo — bug corregido.)*
- Ante derivación o pedido concreto: **nota en el lead + tarea a FormenAR + aviso por Telegram** a Agustín.
- El prompt sale de la spec del cliente (`formen/specs-cliente/`), con el addendum de correcciones ya aplicado.

---

## Cómo se trabaja acá

Los workflows se editan **con scripts de Python** (`scripts/`) que cargan el JSON, modifican los nodos y
escriben una versión nueva. **No editar el JSON a mano**: es enorme y las expresiones de n8n tienen
escapado delicado.

```
python scripts/formen_v15_tono_sobrio.py   # ejemplo: toma el workflow anterior y produce el siguiente
```

*(Los parches del conector son `.ps1` y siguen la misma idea, pero se pegan en la consola de la PC
del local en vez de correrse acá — ver su sección más abajo.)*

Convenciones que conviene mantener:
- Un script por cambio, con `assert` sobre los strings que reemplaza (falla ruidoso si el nodo cambió).
- La lógica de los nodos Code se prueba con **node** antes de inyectarla (stubs de `$json`, `$now`, `$()`).
- Los IDs de credenciales van **hardcodeados** en el JSON → al importar en n8n vienen ya enganchadas.
- **Nunca** meter tokens en el repo.

### Despliegue
Import manual en n8n (Import from File) → activar el nuevo, desactivar el viejo.
*(Existe una skill `n8n-server` para publicar en caliente por la API oficial, con backup y rollback —
vale la pena usarla en lugar del import manual. Y `n8n-logs` para diagnosticar ejecuciones.)*

---

## 🏪 Formen — el conector Dragonfish → Kommo (NO es n8n)

Además del bot, Formen tiene un **segundo sistema** que no vive en este repo: un script de
PowerShell que lleva las ventas del local a Kommo. Conviene saber que existe antes de tocar nada.

- **Dónde corre:** `C:\FormenConector\conector.ps1` (~1500 líneas), **en la PC del local de
  Agustín**. No está acá y no se puede editar directo: se parchea pegando PowerShell en su
  consola. Los parches sí se versionan, en `scripts/formen_conector_*.ps1`.
- **Qué hace:** lee las ventas de SQL Server (`DRAGONFISH_FORMEN` y `DRAGONFISH_BLACK`), busca a
  qué cliente de Kommo corresponden y le carga nota, productos y presupuesto al lead.
- **Cómo empareja:** el vendedor anota en el formulario del iPad los **últimos 4 dígitos del
  comprobante** (campo `Position`, que en la UI se ve como "Cargo") y la caja (`Sistema de
  venta`: Black o Formen). El conector busca ese número con
  `GET /api/v4/contacts?query=NNNN` — **sin mirar la hora**. Si dos ventas comparten los mismos
  4 dígitos, desempata por la caja; si duda, no escribe.
- **Repesca:** la venta que no encuentra dueño **no se descarta**: queda pendiente y se reintenta
  cada `match.repescaCadaMin` (15) durante `match.repescaHoras` (24). El vendedor puede cargar el
  formulario antes, durante o horas después de facturar.
- **Carga a mano:** escribir `B 6645` o `F 6645` en el campo **`Dragonfish comando`** (`2094635`)
  de un lead vincula ese comprobante a ese lead. Busca en los últimos 30 días. **No tocar
  `Dragonfish estado`** (`2094637`): es la respuesta del conector (`vinculado` / `error`).
- **Dónde va la compra:** al lead del **formulario**, no al de la ficha vieja. La nota sí va a la
  ficha del cliente, donde está el chat.

### Trampas propias del conector

1. **PowerShell 5 manda el body en Latin-1.** Con una `ñ` Kommo rechaza el pedido **entero** con
   400 — no se pierde el carácter, se pierde la llamada. El body va como bytes UTF-8.
2. **Kommo recalcula el `price` al vincular productos, y de forma asincrónica**: termina después
   de tu `PATCH`. Leer el precio base ANTES de tocar productos, y al escribirlo reintentar y
   verificar.
3. **Los leads no se borran por API** (405, y `is_deleted` no hace nada). Para limpiar uno de
   prueba, dejarlo en `price = 0`.
4. **El chat "para SalesBot" no se puede leer por API.** Por eso el comando va en un campo.
5. **Solo 1 de cada 3 ventas llega al CRM, y está bien así**: Agustín quiere seguir a los
   clientes que dejan sus datos, no registrar toda su facturación. El importe del embudo **no es
   la venta del día**.

**Arranque:** no hay permisos para tareas programadas en esa PC. Corre desde un acceso directo en
Inicio lanzado por `wscript`, así que **arranca al iniciar sesión, no al prender la máquina**.
Para correrlo a mano hace falta `-ExecutionPolicy Bypass`.

---

## Estado y pendientes

**El bot y el conector están funcionando en producción.**

Pendientes conocidos:
- 🔐 **Rotar el token de Kommo** y el del bot de Telegram: se pegaron en chat alguna vez, y el de
  Kommo quedó expuesto de nuevo el 28/08/2026.
- **Bot**: reanudar la pausa automáticamente a las 24 h (hoy queda pausado indefinido);
  calendario de feriados (hoy da el horario normal si no se lo mencionan); probar Instagram.
- **Bot**: confirmar con Agustín que le llegan los avisos de Telegram (él los daba por rotos).
- **Conector**: el formulario del iPad crea un contacto nuevo aunque el teléfono ya exista — es la
  raíz de los duplicados; mirar el control de duplicados de la cuenta. El reporte `-Medir` quedó
  contando los reintentos de la repesca como ventas. Y el proceso no arranca si nadie inicia sesión
  en esa PC, sin nadie que avise cuando se cae.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
