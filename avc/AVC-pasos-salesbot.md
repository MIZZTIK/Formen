# AVC — Pasos para terminar el Salesbot (Fase B) y probar

> Estado: el workflow de n8n omnicanal ya está listo e importado (Fase A).
> Falta crear el Salesbot en Kommo que llama a n8n. Esta guía es desde cero.

---

## PARTE 1 — Crear el Salesbot en Kommo

1. Entrá a **`briefavc.kommo.com`** → menú lateral **Leads**.
2. Arriba a la derecha, tocá **AUTOMATIZA** (rayo ⚡).
3. En la columna **LEADS ENTRANTES**, tocá **➕ Agregar disparador**.
4. En el menú, elegí **Salesbot** (primer ícono, robotito).
5. Se abre la config del disparador. En el desplegable **"Ejecutar: ..."**:
   - Elegí (sección *Disparadores conversacionales*):
     **"Cuando se inicia un chat por mensaje entrante en cualquier canal"**.
6. Más abajo, en **Salesbot**, tocá **➕ Crea un nuevo bot**.
7. En la ventana de plantillas, tocá **Comenzar desde cero** (arriba a la izquierda).
8. Se abre el editor del bot (arriba dice "SALESBOT #…").
   - *(Opcional)* Renombralo: clic en el nombre "SALESBOT #…" arriba a la izquierda → poné **AVC Asistente**.

## PARTE 2 — Agregar el paso que llama a n8n

9. Al lado de **"Iniciar Salesbot"** aparece **"Agrega el siguiente paso"**.
10. En esa lista, **bajá con el scroll** hasta el fondo y elegí
    **"Paso personalizado (código)"** (ícono `</>`).
    - ⚠️ OJO: justo abajo está **"Widgets"** — NO es ese. Es **Paso personalizado (código)**.
11. Aparece una caja con este texto: `{"handler":"","params":{}}`.
12. Hacé clic **dentro** de la caja → **`Ctrl+A`** (seleccionar todo) → **`Ctrl+V`** para pegar
    ESTO (copialo tal cual):

```json
{"handler":"widget_request","params":{"url":"https://n8n.srv1224751.hstgr.cloud/webhook/AVC","data":{"message":"{{message.text}}","lead_id":"{{lead.id}}","name":"{{contact.name}}"}}}
```

13. Hacé clic fuera de la caja para que quede registrado el texto.

## PARTE 3 — Guardar

14. Arriba a la derecha del editor del bot, tocá **Guardar**.
15. Volvés a la config del disparador. Verificá que en **Salesbot** figure el bot recién creado
    (si dice "Ningún bot seleccionado", elegilo del desplegable).
16. Tocá **Listo**.
17. Arriba a la derecha del pipeline, tocá **Guardar**. ✅ (esto activa el disparador)

---

## PARTE 4 — Verificar n8n (antes de probar)

18. En n8n, abrí el workflow **AVC** y confirmá:
    - Está **Activo** (toggle *Active* arriba a la derecha en ON / *Publish*).
    - El nodo **Webhook** tiene *Respond: Immediately*.
    - Los nodos **Continuar Salesbot** y **Mover etapa** tienen la credencial **Kommo AVC**.

---

## PARTE 5 — Prueba real

19. Desde OTRO teléfono, escribí un WhatsApp al número de AVC (o un DM por Instagram).
    Ej: *"Hola, necesito ayuda con la contabilidad de mi empresa"*.
20. En n8n → pestaña **Executions** del workflow AVC → abrí la ejecución más reciente.
21. Mirá el nodo **Edit Fields1** / **Webhook** y fijate:
    - ¿Llegó `message` con el texto del mensaje? ✅/❌
    - ¿Llegó `lead_id`? ✅
    - ¿Llegó `return_url`? ✅
22. En el WhatsApp/Instagram, deberías recibir la respuesta del asistente.
23. En Kommo, el lead debería moverse a **Contactado**.

---

## Si algo falla — qué revisar

- **`message` vino vacío** en Executions → el placeholder `{{message.text}}` no resolvió.
  Avisame y lo cambiamos (o hacemos que n8n traiga el último mensaje por API con el `lead_id`).
- **No llegó nada a n8n** → revisá que el workflow esté *Activo* y que el pipeline se haya *Guardado*.
- **Llegó pero no respondió** → revisá el nodo *Continuar Salesbot* (que el `return_url` esté bien
  y la credencial Kommo AVC puesta). Mirá el error del nodo en Executions.
- **Respondió una sola vez y no siguió la charla** → falta el *loop*; lo agregamos después
  de confirmar que la ida-y-vuelta básica funciona.

---

## Handler JSON (para copiar de nuevo si hace falta)

```json
{"handler":"widget_request","params":{"url":"https://n8n.srv1224751.hstgr.cloud/webhook/AVC","data":{"message":"{{message.text}}","lead_id":"{{lead.id}}","name":"{{contact.name}}"}}}
```
