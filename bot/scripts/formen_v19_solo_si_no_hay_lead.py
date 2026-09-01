# -*- coding: utf-8 -*-
"""Formen v19: cargar el numero solo si TODAVIA no existe como lead en Kommo.

El bot y el celular del local son la MISMA linea de WhatsApp. Eso significa que las
respuestas del bot tambien salen por ahi, y Evolution las ve como mensajes salientes.
Sin filtro, el workflow cargaria en la lista a cada cliente al que el bot le contesta,
y el bot se iria callando solo con todos despues de la primera respuesta. Una falla
muda y total.

La condicion que lo resuelve la puso Martin al describir el flujo: cargar el numero
"si el vendedor le habla Y no existe el lead de Kommo". Si el bot le contesta a alguien,
ese alguien YA tiene lead — asi que su mensaje saliente se descarta aca y el bot no se
puede silenciar a si mismo. No hace falta mirar de que dispositivo salio el mensaje.

    Webhook -> Filtrar saliente -> Buscar en Kommo -> Ya existe? -> Cargar en la lista

Ante la duda NO carga: si Kommo no responde, se descarta en vez de arriesgarse a
silenciar al bot con un cliente que si tenia lead.

    python bot/scripts/formen_v19_solo_si_no_hay_lead.py
"""
import json
import os

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "formen", "workflow-carga-silenciados.json")

CRED_KOMMO = {"httpHeaderAuth": {"id": "XFOpX4xAM95NWBU6", "name": "Kommo ForMen"}}

JS_YA_EXISTE = """// Solo cargamos numeros que todavia NO existen como lead en Kommo.
//
// Es lo que evita que el bot se silencie a si mismo: el bot y el celular del local son
// la misma linea, asi que las respuestas del bot tambien llegan aca como salientes.
// Pero a quien el bot le contesta ya tiene lead, y por eso cae en este filtro.
const filtrado = $('Filtrar saliente').first().json;
const j = $json;

// Si la llamada a Kommo fallo, NO cargamos. Cargar de mas silencia al bot con un
// cliente real durante 12 horas; no cargar solo pierde una pausa.
if (j && j.error) return [];

let tieneLead = false;
try {
  const raw = (j && j.data && typeof j.data === 'string') ? JSON.parse(j.data) : j;
  const contactos = ((raw && raw._embedded) || {}).contacts || [];
  tieneLead = contactos.some(c => ((((c || {})._embedded || {}).leads) || []).length > 0);
} catch (e) {
  return [];
}

if (tieneLead) return [];
return [{ json: filtrado }];"""

wf = json.load(open(SRC, encoding="utf-8"))
nodos = {n["name"]: n for n in wf["nodes"]}
con = wf["connections"]

assert "Cargar en la lista" in nodos, "falta el workflow base de v17"
assert "Buscar en Kommo" not in nodos, "el parche ya se aplico"
assert con["Filtrar saliente"]["main"][0] == [
    {"node": "Cargar en la lista", "type": "main", "index": 0}], "el cableado cambio"

wf["nodes"].extend([
    {
        "parameters": {
            "url": ("=https://adminformenar.kommo.com/api/v4/contacts"
                    "?query={{ $json.ultimos10 }}&with=leads"),
            "authentication": "genericCredentialType",
            "genericAuthType": "httpHeaderAuth",
            "options": {"timeout": 8000},
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.3,
        "position": [-300, 0],
        "id": "bb000000-0000-4000-8000-00000000c004",
        "name": "Buscar en Kommo",
        "credentials": CRED_KOMMO,
        # Kommo devuelve 204 sin cuerpo cuando no encuentra nada: eso no es un error.
        "onError": "continueRegularOutput",
        "alwaysOutputData": True,
    },
    {
        "parameters": {"jsCode": JS_YA_EXISTE},
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [-150, 0],
        "id": "bb000000-0000-4000-8000-00000000c005",
        "name": "Ya existe en Kommo?",
    },
])

# se cuelga entre el filtro y la carga
nodos["Cargar en la lista"]["position"] = [0, 0]
con["Filtrar saliente"] = {"main": [[{"node": "Buscar en Kommo", "type": "main", "index": 0}]]}
con["Buscar en Kommo"] = {"main": [[{"node": "Ya existe en Kommo?", "type": "main", "index": 0}]]}
con["Ya existe en Kommo?"] = {"main": [[{"node": "Cargar en la lista", "type": "main", "index": 0}]]}

nombres = [n["name"] for n in wf["nodes"]]
for origen, destinos in con.items():
    assert origen in nombres, origen
    for rama in destinos.get("main", []):
        for c in rama:
            assert c["node"] in nombres, c["node"]

json.dump(wf, open(SRC, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

print("OK ->", SRC)
print("  cadena:", " -> ".join(nombres))
print("  ahora solo carga numeros sin lead en Kommo; ante la duda, no carga")
