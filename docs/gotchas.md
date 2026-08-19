# Gotchas y hallazgos — Kommo + n8n

Todo lo que descubrimos a los golpes. Cada uno costó una sesión de debugging; están medidos, no supuestos.

---

## 1. Kommo NO soporta emojis (el más importante)

La base de Kommo usa MySQL `utf8` (3 bytes), no `utf8mb4` (4 bytes). **Cualquier campo trunca en el
primer emoji astral.** Medido en `utm_content`, `Tracking number`, `Delivery address` y un custom
`textarea`: **todos cortan**. Es account-wide y no se puede cambiar (es el server de Kommo).

```
ENVIADO : "Antes del emoji 👔 despues del emoji texto final"   (48 chars)
GUARDADO: "Antes del emoji "                                    (16 chars)
```

**Rompe dos cosas distintas:**

| Dónde | Síntoma | Fix |
|---|---|---|
| **Respuesta del bot** | El cliente recibe el mensaje cortado a la mitad | El prompt prohíbe emojis **+** el parseo los borra con `.replace(/[\u{10000}-\u{10FFFF}️]/gu, '')` |
| **Buffer** (mensaje del cliente) | El JSON del buffer queda corrupto → `JSON.parse` falla → **el bot se traba y no responde más** | "Preparar buffer" limpia emojis **antes** de guardar |

> Caso real: un cliente brasileño escribió *"...Santa Catarina 🇧🇷"* y el bot quedó mudo en ese chat.
> Para destrabar un lead así: vaciar su campo `bot_buffer` a mano en Kommo.

**Consecuencia de negocio:** los emojis en las respuestas son **técnicamente imposibles** con esta
arquitectura. No es preferencia de diseño. *(Un emoji fijo escrito en el mensaje del Salesbot podría
funcionar —vive en la definición del bot, no en un campo— pero no está probado.)*

---

## 2. Límite de caracteres del campo vehículo

Medido en `utm_content` de Formen: **2000 OK · 3000 → 400 Bad Request**. Se trunca a **1900** por seguridad.

**Peligro silencioso:** si la respuesta supera el límite, el PATCH devuelve 400, pero con
`onError: continueRegularOutput` el flujo sigue y el Salesbot **envía el valor VIEJO del campo** →
el cliente recibe la respuesta anterior sin que se note en el log.

*(El viejo `Respuesta_bot` de AVC era tipo "text" = máx. 256 chars, y no se puede convertir a textarea
después de creado.)*

---

## 3. El webhook dispara varias veces por mensaje

Kommo manda ~5 eventos por mensaje. Sumado a clientes que escriben en fragmentos, el bot contestaba
2-3 veces lo mismo.

- Un dedup con `$getWorkflowStaticData` **no alcanza**: falla con ejecuciones casi simultáneas.
- La solución real es el **buffer** (ver CLAUDE.md), que además junta los mensajes fragmentados y
  reduce llamadas a OpenAI. Beneficio extra: al lanzar el Salesbot 1 vez en vez de N, desaparecen los
  choques de *"ya hay un bot corriendo para esta entidad"*.

---

## 4. Formas de la API de Kommo

- **GET** devuelve el body como **string dentro de `$json.data`** → `JSON.parse($json.data)`.
- Los `field_id` vienen como **string** → comparar con `Number(c.field_id) === N`.
- **PATCH** `/leads/{id}` espera **objeto** `{...}`; `/leads` (colección) espera **array** `[{"id":...}]`.
  Mandar la forma equivocada devuelve 200 y **no guarda nada**.
- El GET del lead trae `_embedded.tags` → para agregar una etiqueta sin pisar las existentes hay que
  leerlas y concatenar.
- Endpoints del Salesbot: **`api/v2`** (`/api/v2/salesbot/run`). El resto de la API es `api/v4`.
- Los `bot_id` no se listan por API: se sacan del `PUT /ajax/v2/salesbot/<ID>` en la pestaña Network (F12)
  al guardar el bot.
- Leads en **"Incoming leads"** no ejecutan automatizaciones → hay que moverlos a una etapa real primero.
- **Error 110 "Invalid user name or password"** = el token del Header Auth está mal.
  El valor debe ser `Bearer <token>` (con el prefijo).

---

## 5. Lo que NO existe en Kommo

- **No hay webhook de mensajes salientes.** Por eso la "pausa por intervención humana" se detecta por
  **etapa del lead** (una automatización de Kommo mueve el lead cuando el operador escribe), no por evento.
- **No se puede mover un lead de vuelta a "Incoming leads".**
- `widget_request` desde un "Paso personalizado (código)" **no dispara** sin un widget registrado.

---

## 6. Diferencias de plan (Avanzado vs Enterprise)

Exclusivo de **Enterprise**:
- Disparador *"cuando un campo es actualizado"*.
- **Insertar un campo PERSONALIZADO** en el mensaje del Salesbot (en Avanzado el selector, al escribir `[`,
  solo lista campos predefinidos: `utm_*`, totales, etc.).

En **Avanzado** sí están: los Salesbots ("Bots sin código"), lanzarlos por API, y los campos predefinidos.
De ahí sale todo el truco del **campo vehículo** + `salesbot/run`.

---

## 7. WhatsApp Business API: ventana de 24 horas

Meta solo permite mensajes libres a alguien que escribió en las últimas 24 h. Fuera de eso: **error 3108**
("El destinatario ha estado inactivo durante más de 24 horas") y hay que usar una **plantilla aprobada**.

Impacto: **no sirve para avisos internos** al dueño (que casi nunca le escribe al bot) → los avisos van por
**Telegram** (sin ventana, gratis, y **sí soporta emojis** porque no pasa por Kommo) + **tarea/nota en Kommo**
como respaldo que nunca falla.

---

## 8. La IA rompe el JSON de vez en cuando

Un cliente recibió el objeto crudo `{"respuesta":"...","derivar":false,...}` porque `JSON.parse` falló
(la IA devolvió el JSON con texto alrededor) y el fallback mandaba el `raw`.

**Parseo robusto** (en ambos bots):
1. Aísla del primer `{` al último `}` antes de parsear.
2. Si falla, rescata el valor de `reply`/`respuesta` con regex.
3. Si nada funciona, manda un mensaje seguro y deriva.
4. Nunca respuesta vacía, nunca JSON crudo.

---

## 9. Google Calendar (AVC)

- El nodo **nativo** de Google Calendar no agrega invitados, ni manda mail, ni crea el Meet bien.
  → se usa **HTTP Request** a `POST /calendar/v3/calendars/{CAL}/events?sendUpdates=all&conferenceDataVersion=1`
  con `attendees` + `conferenceData.createRequest` (hangoutsMeet) + `reminders.overrides`.
- La app OAuth debe estar **publicada en Producción**. En modo "Prueba", Google **vence el refresh token
  cada 7 días** y el calendario se rompe todas las semanas.
- Al autorizar aparece "Google no ha verificado esta app" → *Configuración avanzada → Ir a…*. Es normal
  con un solo usuario, no requiere verificación.
- **No re-autenticar una credencial compartida con otro proyecto**: se le rompe al otro.
- El **calendar id aparece en 5 lugares** del workflow (ver CLAUDE.md).

---

## 10. Cosas del entorno (Windows)

- Al leer respuestas de la API con PowerShell: usar **`Invoke-RestMethod`**.
  `Invoke-WebRequest` devuelve `.Content` como bytes y parece que los campos vinieran vacíos/`null`.
- Para leer PDFs acá no hay poppler → usar **`fitz` (PyMuPDF)**. Para `.docx`, descomprimir el XML.
- La consola de Windows (cp1252) revienta al imprimir emojis/símbolos: volcar a archivo UTF-8 y leerlo.
