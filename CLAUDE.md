# Asistentes IA sobre Kommo + n8n — contexto del proyecto

Dos asistentes conversacionales de WhatsApp, construidos sobre **Kommo (CRM) + n8n (orquestación) + OpenAI**.
Comparten la misma arquitectura y los mismos hallazgos técnicos, por eso viven en el mismo proyecto.

| | **AVC Soluciones Empresariales** | **Formen** |
|---|---|---|
| Rubro | Consultora empresarial (Paraguay) | Indumentaria masculina / sastrería (Corrientes, AR) |
| Qué hace el bot | Responde consultas, releva datos y **agenda reuniones** en Google Calendar con Meet | Responde consultas de catálogo y **deriva a humano** (no agenda) |
| Canales | WhatsApp, Instagram, Facebook | WhatsApp, Instagram |
| Kommo | `briefavc.kommo.com` | `adminformenar.kommo.com` |
| n8n | `n8n.srv1224751.hstgr.cloud` → `/webhook/AVC` | `n8n-06ir.srv1605341.hstgr.cloud` → `/webhook/formen` |
| Workflow vigente | `avc/workflow-avc.json` | `formen/workflow-formen.json` |
| Modelo | gpt-4.1-mini *(ver nota)* | gpt-4.1 |

> **Nota sobre el modelo de AVC:** está en `gpt-4.1-mini` para ahorrar costo, pero el prompt es complejo
> (JSON estricto, flujo de inversores, lógica de agenda, multi-idioma). Si aparecen fallas —responde en
> idioma equivocado, se saltea pasos, rompe el JSON, inventa turnos— **el modelo es el primer sospechoso**:
> subir a `gpt-4.1`.

---

## ⚠️ LA RESTRICCIÓN QUE EXPLICA TODO EL DISEÑO

Ambas cuentas tienen **WhatsApp nativo de Kommo** y están (o van a estar) en **plan Avanzado**.
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

## Datos de cada cuenta (IDs; los secretos NO están acá — ver `docs/credenciales.md`)

### AVC
- Pipeline principal `14086271`. Etapas: Incoming `108736471` · **Leads pausados `109108699`** ·
  Contactado `108736475` · Necesidad relevada `108736479` · Reunión/Diagnóstico `108736483` ·
  **Contactado por personal `109670139`** · Propuesta `108736487` · Negociación `108737583` · won `142` · lost `143`.
- Campos: `utm_content` **`1211984`** (vehículo) · `Evento_id` `1679524` · `bot_buffer` `1933244`.
- Salesbot **#4**, `bot_id` **`52978`**.
- Google Calendar: **"AVC reuniones BOT"**
  `4e6e578a870ac6a9cac365edb69974a43de621b41207be4d9d8d5ded486f1dbb@group.calendar.google.com`,
  cuenta `avcsolucionesempresariales@gmail.com`, app OAuth propia **publicada en Producción**
  (si vuelve a modo "Prueba", Google vence el token cada 7 días).
- Credenciales n8n: Kommo `BqHFVJZcWvtdH6ee` · Calendar `9yYQShk9v3idvbD3` · OpenAI `U8exa9B7bGjLh4cw`.

### Formen
- Pipeline `14000647`. Etapas: Incoming `108058027` · Primer contacto `108221247` · **Lead pausado `108221251`**.
- Campos: `utm_content` **`326786`** (vehículo) · `bot_buffer` `2084715` · `Respuesta_bot` `1741927` *(sin uso)*.
- Salesbot **"FORMEN N8N BOT"**, `bot_id` **`57555`**.
- Usuario Kommo (para asignar tareas): FormenAR `15483335`.
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
   *(El viejo `Respuesta_bot` de AVC era tipo texto = 256.)*
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

## Anatomía del workflow (ambos siguen el mismo esqueleto)

```
Webhook → Dedup → Edit Fields → ¿entrante? → Traer lead → Estado lead → ¿Pausado?
  └─(no pausado)→ Preparar buffer → Guardar buffer → Esperar 8s → Releer buffer
                  → ¿Último mensaje? ─(no soy el último: muere)
                  → Limpiar buffer → [AVC: Turnos libres → Calcular turnos] → AI Agent
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
- **Pausa por intervención humana:** si el lead está en una etapa "humana", el bot corta antes de
  responder y de mover etapas. AVC: `109108699` y `109670139`. Formen: `108221251`.
- **Etapas forward-only** (AVC): compara contra una tabla de orden y nunca retrocede el lead.

### Específico de AVC — agenda
- Reuniones **de 1 hora**, turnos **en punto** 08:00–17:00, **lunes a viernes**.
- **Mínimo 2 días de antelación** (pido lunes → ofrece miércoles). Aplicado en 3 capas: los turnos que
  ofrece, el prompt, y un **guard duro** en el parseo que anula el agendamiento y reescribe la respuesta.
- `Turnos libres` (freeBusy 14 días) + `Calcular turnos` → el bot ofrece **solo turnos realmente libres**.
- `FreeBusy` antes de crear el evento = red de seguridad contra doble reserva.
- El **calendar id aparece en 5 lugares**: `Crear evento`, `Cancelar evento`, `FreeBusy` y **`Libre?` ×2**
  (lo usa como clave). Si se olvida el de `Libre?`, da siempre "libre" y **permite doble reserva en silencio**.
- Flujo especial **Inversores / Ley de Maquila**: guion de 8 pasos, filtro duro = inversión ≥ USD 50.000.

### Específico de Formen — derivación y avisos
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
python scripts/avc_v17_idioma_intro.py     # ejemplo: toma el workflow anterior y produce el siguiente
```

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

## Estado y pendientes

**Ambos bots están funcionando en producción.**

Pendientes conocidos:
- 🔐 **Rotar tokens**: los de Kommo (AVC y Formen) y el del bot de Telegram se pegaron en chat alguna vez.
- **AVC**: validar el flujo de inversores end-to-end; evaluar subir el modelo a `gpt-4.1` (idioma).
- **Formen**: reanudar la pausa automáticamente a las 24 h (hoy queda pausado indefinido);
  calendario de feriados (hoy da el horario normal si no se lo mencionan); probar Instagram.
- **Formen**: confirmar con Agustín que le llegan los avisos de Telegram (él los daba por rotos).
