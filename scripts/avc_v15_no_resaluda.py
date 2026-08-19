# -*- coding: utf-8 -*-
"""AVC v15: que el bot NO se re-presente/salude en cada mensaje. Lo ata a la etapa del lead."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v14-nombre-lead.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v15-no-resaluda.json"

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}
sm = n["AI Agent"]["parameters"]["options"]["systemMessage"]

# 1) Separar 'Contactado' de 'Leads entrantes' en el contexto de etapa
antes1 = "- 'Contactado' o 'Leads entrantes': recien empieza; releva nombre y necesidad."
despues1 = ("- 'Leads entrantes' o 'Incoming leads': es el PRIMER mensaje. SOLO aca te presentas como AVC y saludas.\n"
            "- 'Contactado': la conversacion YA EMPEZO y ya te presentaste. NO vuelvas a saludar, NO te presentes de nuevo, "
            "NO repitas 'AVC Soluciones Empresariales'. Continua directo relevando nombre/necesidad.")
assert antes1 in sm, "no se encontro el bullet de contexto"
sm = sm.replace(antes1, despues1)

# 2) Regla de saludo mas fuerte
antes2 = "- Saluda solo al inicio."
despues2 = ("- SALUDA Y PRESENTATE COMO AVC UNA SOLA VEZ, en el primer mensaje (etapa 'Leads entrantes'). "
            "En cualquier otra etapa la conversacion ya empezo: PROHIBIDO volver a saludar, presentarte o "
            "repetir 'AVC Soluciones Empresariales'. Anda directo al punto.")
assert antes2 in sm
sm = sm.replace(antes2, despues2)

# 3) FLUJO paso 1: aclarar que es solo la primera vez
antes3 = "1. Saluda presentandote como AVC y pedi el nombre (customerName)."
despues3 = "1. SOLO en el primer mensaje (etapa 'Leads entrantes'): saluda presentandote como AVC y pedi el nombre (customerName). Si la etapa ya es 'Contactado' o posterior, NO saludes de nuevo."
assert antes3 in sm
sm = sm.replace(antes3, despues3)

n["AI Agent"]["parameters"]["options"]["systemMessage"] = sm
json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("split Contactado/Leads:", "la conversacion YA EMPEZO" in sm)
print("regla fuerte saludo:", "UNA SOLA VEZ" in sm)
print("flujo paso 1 aclarado:", "SOLO en el primer mensaje (etapa 'Leads entrantes')" in sm)
