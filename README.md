# asistentes-kommo

Asistentes IA de WhatsApp para **AVC Soluciones Empresariales** y **Formen**, sobre Kommo + n8n + OpenAI.

👉 **Empezá por [`CLAUDE.md`](CLAUDE.md)** — ahí está la arquitectura, los IDs de cada cuenta y las
restricciones que explican por qué el diseño es como es.

## Estructura

```
CLAUDE.md                  Contexto completo del proyecto (leer primero)
docs/
  gotchas.md               Bugs y límites de Kommo descubiertos a los golpes
  credenciales.md          Dónde vive cada secreto (sin secretos adentro)
avc/
  workflow-avc.json        Workflow vigente de AVC (n8n)
  AVC-guion-inversores-maquila.md
  AVC-pasos-salesbot.md
formen/
  workflow-formen.json     Workflow vigente de Formen (n8n)
  system-prompt-v6.md      Prompt del asistente (fuente del que está en el workflow)
  casos-de-uso.md          49 casos de QA derivados de la spec del cliente
  specs-cliente/           Documentos originales de Agustín (Formen)
scripts/                   Generadores Python: así se editan los workflows
```

## Qué hace cada bot

- **AVC** — responde consultas de la consultora, releva datos y **agenda reuniones** en Google Calendar
  con Meet (turnos en punto, 1 h, mínimo 2 días de antelación). Incluye un flujo de precalificación para
  **inversores / Ley de Maquila**.
- **Formen** — responde consultas del catálogo de la sastrería (precios, talles, pagos) y **deriva a un
  humano** cuando corresponde, avisando por Telegram + tarea en Kommo.

## Para tocar un workflow

No editar el JSON a mano. Se usa un script de Python que carga el workflow, modifica los nodos y escribe
la versión nueva (ver `scripts/` y la sección "Cómo se trabaja acá" del CLAUDE.md).
