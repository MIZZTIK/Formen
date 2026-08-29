# -*- coding: utf-8 -*-
"""Formen v13: buffer (anti-duplicado) + notificar en toda derivacion + prompt v6 (addendum).
   Credenciales reales enganchadas."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\Formen-workflow-n8n-v12-telegram.json"
PROMPT = r"C:\Users\marti\OneDrive\Escritorio\Formen-AI-System-Prompt-v6.md"
OUT = r"C:\Users\marti\OneDrive\Escritorio\Formen-workflow-n8n-v13-buffer-addendum.json"

SUB = "adminformenar.kommo.com"
FIELD_BUFFER = 2084715
SEG = 8
KCRED = {"id": "XFOpX4xAM95NWBU6", "name": "Kommo ForMen"}
TGCRED = {"id": "iHWlHjVPTlIb72xG", "name": "Telegram account"}

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}

# ---------- credenciales reales en todos los nodos Kommo ----------
for node in wf["nodes"]:
    creds = node.get("credentials", {})
    if "httpHeaderAuth" in creds:
        creds["httpHeaderAuth"] = dict(KCRED)
    if "telegramApi" in creds:
        creds["telegramApi"] = dict(TGCRED)

# ---------- prompt v6 ----------
md = open(PROMPT, encoding="utf-8").read()
marca = "Sos el asistente virtual de **Formen**"
system_message = md[md.find(marca):].strip()
n["AI Agent"]["parameters"]["options"]["systemMessage"] = system_message

# ---------- Estado lead: extraer tambien el buffer ----------
n["Estado lead"]["parameters"]["jsCode"] = (
"const j = $json;\n"
"const raw = (j && j.data && typeof j.data === 'string') ? JSON.parse(j.data) : j;\n"
"const statusId = Number(raw.status_id) || 0;\n"
"const emb = raw._embedded || {};\n"
"const tags = (emb.tags || []).map(t => ({ id: t.id }));\n"
"const cfs = (raw && raw.custom_fields_values) || [];\n"
"const fb = cfs.find(c => Number(c.field_id) === %d);\n"
"const bufferRaw = (fb && fb.values && fb.values[0]) ? fb.values[0].value : '';\n"
"let buffer = { msgs: [], ts: 0 };\n"
"try { if (bufferRaw) buffer = JSON.parse(bufferRaw); } catch (e) {}\n"
"if (!Array.isArray(buffer.msgs)) buffer.msgs = [];\n"
"return [{ json: { statusId: statusId, leadId: $('Edit Fields1').first().json.leadId, tags: tags, bufferMsgs: buffer.msgs } }];" % FIELD_BUFFER
)

# ---------- nodos del buffer ----------
preparar = (
"const prev = $('Estado lead').first().json.bufferMsgs || [];\n"
"const nuevo = $('Edit Fields1').first().json.text || '';\n"
"const msgs = prev.concat([nuevo]);\n"
"const stamp = Date.now();\n"
"return [{ json: { leadId: $('Edit Fields1').first().json.leadId, stamp: stamp, bufferJson: JSON.stringify({ msgs: msgs, ts: stamp }) } }];"
)
ultimo = (
"const raw = ($json && $json.data && typeof $json.data === 'string') ? JSON.parse($json.data) : ($json || {});\n"
"const cfs = (raw && raw.custom_fields_values) || [];\n"
"const fb = cfs.find(c => Number(c.field_id) === %d);\n"
"const bufferRaw = (fb && fb.values && fb.values[0]) ? fb.values[0].value : '';\n"
"let buffer = { msgs: [], ts: 0 };\n"
"try { if (bufferRaw) buffer = JSON.parse(bufferRaw); } catch (e) {}\n"
"const miStamp = $('Preparar buffer').first().json.stamp;\n"
"if (Number(buffer.ts) !== Number(miStamp)) { return []; }\n"
"const texto = (buffer.msgs || []).join('\\n');\n"
"return [{ json: { leadId: $('Preparar buffer').first().json.leadId, textoJunto: texto } }];" % FIELD_BUFFER
)
buf_nodes = [
    {"parameters": {"jsCode": preparar}, "type": "n8n-nodes-base.code", "typeVersion": 2,
     "position": [15104, 2260], "id": "bf000001-f0f0-f0f0-f0f0-prepararbuff", "name": "Preparar buffer"},
    {"parameters": {"method": "PATCH", "url": "=https://%s/api/v4/leads/{{ $json.leadId }}" % SUB,
        "authentication": "genericCredentialType", "genericAuthType": "httpHeaderAuth", "sendBody": True, "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ custom_fields_values: [{ field_id: %d, values: [{ value: $json.bufferJson }] }] }) }}" % FIELD_BUFFER, "options": {}},
     "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.3, "position": [15296, 2260],
     "id": "bf000002-f0f0-f0f0-f0f0-guardarbuff0", "name": "Guardar buffer", "credentials": {"httpHeaderAuth": dict(KCRED)}, "onError": "continueRegularOutput"},
    {"parameters": {"amount": SEG}, "type": "n8n-nodes-base.wait", "typeVersion": 1.1,
     "position": [15488, 2260], "id": "bf000003-f0f0-f0f0-f0f0-esperarbuff0", "name": "Esperar", "webhookId": "formen-buffer-wait-8s"},
    {"parameters": {"url": "=https://%s/api/v4/leads/{{ $('Preparar buffer').first().json.leadId }}" % SUB,
        "authentication": "genericCredentialType", "genericAuthType": "httpHeaderAuth", "options": {}},
     "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.3, "position": [15680, 2260],
     "id": "bf000004-f0f0-f0f0-f0f0-releerbuff00", "name": "Releer buffer", "credentials": {"httpHeaderAuth": dict(KCRED)}, "onError": "continueRegularOutput"},
    {"parameters": {"jsCode": ultimo}, "type": "n8n-nodes-base.code", "typeVersion": 2,
     "position": [15872, 2260], "id": "bf000005-f0f0-f0f0-f0f0-ultimomsg000", "name": "Ultimo mensaje?"},
    {"parameters": {"method": "PATCH", "url": "=https://%s/api/v4/leads/{{ $json.leadId }}" % SUB,
        "authentication": "genericCredentialType", "genericAuthType": "httpHeaderAuth", "sendBody": True, "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ custom_fields_values: [{ field_id: %d, values: [{ value: '' }] }] }) }}" % FIELD_BUFFER, "options": {}},
     "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.3, "position": [16064, 2260],
     "id": "bf000006-f0f0-f0f0-f0f0-limpiarbuff0", "name": "Limpiar buffer", "credentials": {"httpHeaderAuth": dict(KCRED)}, "onError": "continueRegularOutput"},
]
wf["nodes"].extend(buf_nodes)

# ---------- recablear Pausado?[false] -> buffer -> AI Agent ----------
wf["connections"]["Pausado?"] = {"main": [[], [{"node": "Preparar buffer", "type": "main", "index": 0}]]}
wf["connections"]["Preparar buffer"] = {"main": [[{"node": "Guardar buffer", "type": "main", "index": 0}]]}
wf["connections"]["Guardar buffer"] = {"main": [[{"node": "Esperar", "type": "main", "index": 0}]]}
wf["connections"]["Esperar"] = {"main": [[{"node": "Releer buffer", "type": "main", "index": 0}]]}
wf["connections"]["Releer buffer"] = {"main": [[{"node": "Ultimo mensaje?", "type": "main", "index": 0}]]}
wf["connections"]["Ultimo mensaje?"] = {"main": [[{"node": "Limpiar buffer", "type": "main", "index": 0}]]}
wf["connections"]["Limpiar buffer"] = {"main": [[{"node": "AI Agent", "type": "main", "index": 0}]]}

# ---------- AI Agent usa el texto juntado ----------
n["AI Agent"]["parameters"]["text"] = "={{ $('Ultimo mensaje?').first().json.textoJunto }}"

# ---------- Notificar en TODA derivacion + textos genericos ----------
n["Notificar a Agustin?"]["parameters"]["conditions"]["conditions"][0]["leftValue"] = \
    "={{ $('Parsear respuesta IA').first().json.derivar || $('Parsear respuesta IA').first().json.notificarAgustin }}"

TJ = "$('Ultimo mensaje?').first().json.textoJunto"
NM = "$('Edit Fields1').first().json.name"
MO = "$('Parsear respuesta IA').first().json.motivo"

n["Nota consulta"]["parameters"]["jsonBody"] = (
"={{ JSON.stringify([{ note_type: 'common', params: { text: "
"('[BOT] Lead para atender. Cliente: ' + (%s || 's/d') + '. Dijo: ' + (%s || '') + '. Motivo: ' + (%s || '')).toString().substring(0, 900) "
"} }]) }}" % (NM, TJ, MO))

n["Tarea Agustin"]["parameters"]["jsonBody"] = (
"={{ JSON.stringify([{ task_type_id: 1, "
"text: ('Atender lead (bot) - ' + (%s || 's/d') + ': ' + (%s || '') + (%s ? ' [' + %s + ']' : '')).toString().substring(0, 200), "
"complete_till: Math.round($now.plus({ hours: 4 }).toSeconds()), "
"entity_id: Number($('Edit Fields1').first().json.leadId), entity_type: 'leads', responsible_user_id: 15483335 }]) }}" % (NM, TJ, MO, MO))

# Telegram: texto plano (sin markdown para no romper con caracteres del cliente)
n["Aviso Telegram"]["parameters"]["text"] = (
"=Nuevo lead para atender en Formen\n\n"
"Cliente: {{ %s }}\n"
"Dijo: {{ %s }}\n"
"Motivo: {{ %s }}\n\n"
"Entra a Kommo para responderle." % (NM, TJ, MO))
n["Aviso Telegram"]["parameters"]["additionalFields"] = {}

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("nodos:", len(wf["nodes"]))
print()
print("Pausado?[false] ->", [t['node'] for t in wf["connections"]["Pausado?"]["main"][1]])
for a in ["Preparar buffer","Guardar buffer","Esperar","Releer buffer","Ultimo mensaje?","Limpiar buffer"]:
    print("  %-16s ->" % a, [t['node'] for b in wf["connections"][a]["main"] for t in b])
print("AI Agent text:", n["AI Agent"]["parameters"]["text"])
print("Notificar cond:", n["Notificar a Agustin?"]["parameters"]["conditions"]["conditions"][0]["leftValue"])
