# -*- coding: utf-8 -*-
"""AVC v16: los emojis en el mensaje ENTRANTE rompian el buffer (el campo bot_buffer trunca en
   el emoji -> JSON invalido -> el bot se traba). Fix: limpiar emojis antes de guardar en el buffer."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v15-no-resaluda.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v16-buffer-emoji.json"

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}

nuevo_code = (
"// Acumula el mensaje nuevo sobre lo que ya habia y estampa la hora.\n"
"// IMPORTANTE: se limpian emojis (el campo bot_buffer de Kommo trunca en el primer emoji astral\n"
"// -> JSON corrupto -> el bot se traba). Astral = 4 bytes (utf8mb4 no soportado por Kommo).\n"
"const noEmoji = (s) => (s || '').toString().replace(/[\\u{10000}-\\u{10FFFF}\\uFE0F]/gu, '');\n"
"const prev = ($('Estado lead').first().json.bufferMsgs || []).map(noEmoji);\n"
"const nuevo = noEmoji($('Edit Fields1').first().json.text || '');\n"
"const msgs = prev.concat([nuevo]);\n"
"const stamp = Date.now();\n"
"return [{ json: {\n"
"  leadId: $('Edit Fields1').first().json.leadId,\n"
"  stamp: stamp,\n"
"  bufferJson: JSON.stringify({ msgs: msgs, ts: stamp })\n"
"} }];"
)
n["Preparar buffer"]["parameters"]["jsCode"] = nuevo_code

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("Preparar buffer limpia emojis:", "noEmoji" in n["Preparar buffer"]["parameters"]["jsCode"])
