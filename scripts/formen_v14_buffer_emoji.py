# -*- coding: utf-8 -*-
"""Formen v14: limpiar emojis del mensaje antes de guardarlo en bot_buffer."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\Formen-workflow-n8n-v13-buffer-addendum.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\Formen-workflow-n8n-v14-buffer-emoji.json"

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}

nuevo_code = (
"// IMPORTANTE: se limpian emojis (el campo bot_buffer de Kommo trunca en el primer emoji astral\n"
"// -> JSON corrupto -> el bot se traba).\n"
"const noEmoji = (s) => (s || '').toString().replace(/[\\u{10000}-\\u{10FFFF}\\uFE0F]/gu, '');\n"
"const prev = ($('Estado lead').first().json.bufferMsgs || []).map(noEmoji);\n"
"const nuevo = noEmoji($('Edit Fields1').first().json.text || '');\n"
"const msgs = prev.concat([nuevo]);\n"
"const stamp = Date.now();\n"
"return [{ json: { leadId: $('Edit Fields1').first().json.leadId, stamp: stamp, bufferJson: JSON.stringify({ msgs: msgs, ts: stamp }) } }];"
)
n["Preparar buffer"]["parameters"]["jsCode"] = nuevo_code

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("Formen Preparar buffer limpia emojis:", "noEmoji" in n["Preparar buffer"]["parameters"]["jsCode"])

# extraer el code para test node
open(r"C:\Users\marti\AppData\Local\Temp\claude\C--Users-marti\eecab5b3-e247-4ccc-82a1-3c72dd049820\scratchpad\prep_test.js",
     "w", encoding="utf-8").write(n["Preparar buffer"]["parameters"]["jsCode"])
