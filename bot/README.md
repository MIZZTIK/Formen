# asistentes-kommo

Automatizaciones de **Formen** (sastrería de autor, Corrientes) sobre **Kommo + n8n + OpenAI**:
el asistente de WhatsApp que atiende el chat, y el conector que lleva las ventas del local al CRM.

👉 **Empezá por [`CLAUDE.md`](CLAUDE.md)** — ahí está la arquitectura, los IDs de la cuenta y las
restricciones que explican por qué el diseño es como es.

> Formen es un proyecto de **Boomerang**. El asistente de AVC vivía acá y se mudó a su propio repo
> (`../AVC`) el 2026-08-28: son clientes de agencias distintas y no comparten servidores,
> credenciales ni repos.

## Estructura

```
CLAUDE.md                  Contexto completo del proyecto (leer primero)
docs/
  gotchas.md               Bugs y límites de Kommo descubiertos a los golpes
  credenciales.md          Dónde vive cada secreto (sin secretos adentro)
formen/
  workflow-formen.json     Workflow vigente del bot (n8n)
  system-prompt-v6.md      Prompt del asistente (fuente del que está en el workflow)
  casos-de-uso.md          49 casos de QA derivados de la spec del cliente
  specs-cliente/           Documentos originales de Agustín (Formen)
scripts/
  formen_v*.py             Generadores Python: así se editan los workflows de n8n
  formen_conector_*.ps1    Parches del conector Dragonfish (corre en la PC del local)
```

## Las dos piezas

- **El bot de WhatsApp** — responde consultas del catálogo de la sastrería (precios, talles, pagos)
  y **deriva a un humano** cuando corresponde, avisando por Telegram + tarea en Kommo.
- **El conector Dragonfish → Kommo** — lee las ventas del local en SQL Server y las carga en el
  lead del cliente: nota con el comprobante, productos y presupuesto. **No vive en este repo**:
  corre en la PC del local de Agustín y se parchea con los scripts de `scripts/`.

## Para tocar un workflow

No editar el JSON a mano. Se usa un script de Python que carga el workflow, modifica los nodos y
escribe la versión nueva (ver `scripts/` y la sección "Cómo se trabaja acá" del CLAUDE.md).
