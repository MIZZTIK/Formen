# -*- coding: utf-8 -*-
"""AVC v14: cuando la IA detecta el nombre del cliente, lo escribe en el nombre del lead."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v13-inversores.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v14-nombre-lead.json"

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}

# 1) Parse: agregar 'nombreDetectado' (solo el que dijo el cliente, sin fallback)
p = n["Parsear respuesta IA"]["parameters"]["jsCode"]
antes = "  return { json: {\n    reply: replyFinal,\n"
despues = "  return { json: {\n    reply: replyFinal,\n    nombreDetectado: noEmoji(parsed.customerName || \"\").trim(),\n"
assert antes in p, "no se encontro el inicio del return"
n["Parsear respuesta IA"]["parameters"]["jsCode"] = p.replace(antes, despues)

# 2) Mover a etapa: si hay nombreDetectado, incluir name en el PATCH
antes2 = "={{ JSON.stringify({ status_id: $json.targetStatus, pipeline_id: 14086271 }) }}"
despues2 = ("={{ JSON.stringify(Object.assign("
            "{ status_id: $json.targetStatus, pipeline_id: 14086271 }, "
            "($('Parsear respuesta IA').first().json.nombreDetectado "
            "? { name: $('Parsear respuesta IA').first().json.nombreDetectado } : {})"
            ")) }}")
assert n["Mover a etapa"]["parameters"]["jsonBody"] == antes2, "jsonBody de Mover a etapa cambio"
n["Mover a etapa"]["parameters"]["jsonBody"] = despues2

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("parse tiene nombreDetectado:", "nombreDetectado: noEmoji" in n["Parsear respuesta IA"]["parameters"]["jsCode"])
print("Mover a etapa nuevo body:")
print("  ", n["Mover a etapa"]["parameters"]["jsonBody"])
