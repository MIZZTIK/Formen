# -*- coding: utf-8 -*-
"""Formen v16: que el bot no le conteste a quien el local ya esta atendiendo a mano.

El caso: el vendedor le escribe a un numero que todavia no es lead. Cuando esa persona
contesta al WhatsApp oficial, hoy el bot le salta encima con su bienvenida, sin saber
que un humano ya esta en esa conversacion.

La solucion no inventa ningun mecanismo nuevo: el bot YA se calla cuando el lead esta en
"Lead pausado" (108221251). Lo unico que faltaba era que el numero llegue ahi antes de que
el cliente escriba. Para eso el local carga el numero en formen.ar/pausar, y el workflow
consulta esa lista antes de contestar.

Se compara por los ULTIMOS 10 DIGITOS, no por el numero entero: en Kommo conviven tres
formatos (+5493794123331, 3794227874 y +543794403329) y ninguna persona tipea el +549.

Cadena nueva, colgada entre "Estado lead" y "Pausado?":

    Estado lead -> Traer contacto -> Telefono del contacto -> Silenciado en la lista?
                -> Silenciado? --si--> Marcar Lead pausado   (y muere: no contesta)
                              --no--> Pausado?               (todo sigue como antes)

Falla abierta a proposito: si Vercel o Neon no responden, los nodos siguen de largo con
onError=continueRegularOutput y el bot contesta como siempre. Peor que hable de mas es que
se quede mudo con todos los clientes.

Se opera IN-PLACE sobre el JSON del repo, que es el workflow vigente.

    python scripts/formen_v16_lista_silenciados.py

DESPUES DE CORRER ESTO, EN n8n:
  1. Crear la credencial Header Auth "Formen pausas" -> nombre: x-clave, valor: la misma
     clave que quedo en la variable PAUSA_CLAVE de Vercel.
  2. Abrir el nodo "Silenciado en la lista?" y elegir esa credencial (en el JSON va un id
     placeholder a proposito: las credenciales no se versionan).
"""
import json
import os

# Relativo a este archivo: el repo se unifico el 28/08 y la ruta absoluta quedo vieja.
SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "formen", "workflow-formen.json")

ETAPA_PAUSADO = 108221251
CRED_KOMMO = {"httpHeaderAuth": {"id": "XFOpX4xAM95NWBU6", "name": "Kommo ForMen"}}
CRED_PAUSAS = {"httpHeaderAuth": {"id": "REEMPLAZAR-EN-N8N", "name": "Formen pausas"}}
URL_LISTA = "https://www.formen.ar/api/silenciado"

wf = json.load(open(SRC, encoding="utf-8"))
nodos = {n["name"]: n for n in wf["nodes"]}
con = wf["connections"]

for esperado in ("Traer lead", "Estado lead", "Pausado?", "Preparar buffer"):
    assert esperado in nodos, f"falta el nodo {esperado!r}: el workflow cambio"
for nuevo in ("Traer contacto", "Telefono del contacto", "Silenciado en la lista?",
              "Silenciado?", "Marcar Lead pausado"):
    assert nuevo not in nodos, f"{nuevo!r} ya existe: el parche ya se aplico"

# --- 1. el lead tiene que traer sus contactos -------------------------------
url_lead = nodos["Traer lead"]["parameters"]["url"]
assert url_lead.endswith("}}"), url_lead
assert "with=contacts" not in url_lead, "Traer lead ya pedia los contactos"
nodos["Traer lead"]["parameters"]["url"] = url_lead + "?with=contacts"

# --- 2. "Estado lead" pasa a devolver tambien el contactId ------------------
cod = nodos["Estado lead"]["parameters"]["jsCode"]
vieja = ("return [{ json: { statusId: statusId, leadId: $('Edit Fields1').first().json.leadId, "
         "tags: tags, bufferMsgs: buffer.msgs } }];")
assert vieja in cod, "el return de 'Estado lead' no es el esperado"
nueva = (
    "// El contacto se usa para buscar el telefono en la lista de silenciados.\n"
    "const contactId = ((emb.contacts || [])[0] || {}).id || 0;\n"
    "return [{ json: { statusId: statusId, leadId: $('Edit Fields1').first().json.leadId, "
    "tags: tags, bufferMsgs: buffer.msgs, contactId: contactId } }];"
)
nodos["Estado lead"]["parameters"]["jsCode"] = cod.replace(vieja, nueva)

# --- 3. "Pausado?" deja de depender del item que le llega -------------------
# Ahora le entra lo que devuelve la consulta a la lista, no el item de "Estado lead".
cond = nodos["Pausado?"]["parameters"]["conditions"]["conditions"][0]
assert cond["leftValue"] == "={{ $json.statusId }}", cond["leftValue"]
assert int(cond["rightValue"]) == ETAPA_PAUSADO, cond["rightValue"]
cond["leftValue"] = "={{ $('Estado lead').first().json.statusId }}"

# --- 4. los nodos nuevos ----------------------------------------------------
JS_TELEFONO = """// Saca los ultimos 10 digitos del telefono del contacto, que es la clave con la que
// se compara contra la lista. Se usan los ultimos 10 y no el numero entero porque en
// Kommo el mismo telefono convive en tres formatos y ninguna persona tipea el +549.
//
// Si "Traer contacto" fallo, esto NO rompe: sigue sin telefono y el bot contesta como
// siempre. La pausa es una mejora, no puede ser un motivo para dejar mudo al bot.
let ultimos10 = '';
try {
  const j = $json;
  const raw = (j && j.data && typeof j.data === 'string') ? JSON.parse(j.data) : j;
  const cfs = (raw && raw.custom_fields_values) || [];
  const tel = cfs.find(c => c.field_code === 'PHONE' || Number(c.field_id) === 326778);
  const val = (tel && tel.values && tel.values[0]) ? String(tel.values[0].value || '') : '';
  ultimos10 = val.replace(/\\D/g, '').slice(-10);
} catch (e) {}
const est = $('Estado lead').first().json;
return [{ json: { ultimos10: ultimos10, leadId: est.leadId, contactId: est.contactId } }];"""

nuevos = [
    {
        "parameters": {
            "url": "=https://adminformenar.kommo.com/api/v4/contacts/{{ $json.contactId }}",
            "authentication": "genericCredentialType",
            "genericAuthType": "httpHeaderAuth",
            "options": {},
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.3,
        "position": [-1160, 220],
        "id": "aa000000-0000-4000-8000-00000000f001",
        "name": "Traer contacto",
        "credentials": CRED_KOMMO,
        "onError": "continueRegularOutput",
        "alwaysOutputData": True,
    },
    {
        "parameters": {"jsCode": JS_TELEFONO},
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [-1000, 220],
        "id": "aa000000-0000-4000-8000-00000000f002",
        "name": "Telefono del contacto",
    },
    {
        "parameters": {
            "url": "=" + URL_LISTA + "?ultimos10={{ $json.ultimos10 }}",
            "authentication": "genericCredentialType",
            "genericAuthType": "httpHeaderAuth",
            "options": {"timeout": 5000},
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.3,
        "position": [-840, 220],
        "id": "aa000000-0000-4000-8000-00000000f003",
        "name": "Silenciado en la lista?",
        "credentials": CRED_PAUSAS,
        "onError": "continueRegularOutput",
        "alwaysOutputData": True,
    },
    {
        "parameters": {
            "conditions": {
                "options": {"caseSensitive": True, "leftValue": "",
                            "typeValidation": "loose", "version": 3},
                "conditions": [{
                    "id": "si000000-0000-0000-0000-000000000001",
                    "leftValue": "={{ $json.silenciado }}",
                    "rightValue": "",
                    "operator": {"type": "boolean", "operation": "true", "singleValue": True},
                }],
                "combinator": "and",
            },
            "options": {},
        },
        "type": "n8n-nodes-base.if",
        "typeVersion": 2.3,
        "position": [-680, 220],
        "id": "aa000000-0000-4000-8000-00000000f004",
        "name": "Silenciado?",
    },
    {
        "parameters": {
            "method": "PATCH",
            "url": ("=https://adminformenar.kommo.com/api/v4/leads/"
                    "{{ $('Estado lead').first().json.leadId }}"),
            "authentication": "genericCredentialType",
            "genericAuthType": "httpHeaderAuth",
            "sendBody": True,
            "specifyBody": "json",
            # /leads/{id} espera un OBJETO (la coleccion /leads espera array).
            "jsonBody": "={{ JSON.stringify({ status_id: %d, pipeline_id: 14000647 }) }}" % ETAPA_PAUSADO,
            "options": {},
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.3,
        "position": [-520, 320],
        "id": "aa000000-0000-4000-8000-00000000f005",
        "name": "Marcar Lead pausado",
        "credentials": CRED_KOMMO,
        "onError": "continueRegularOutput",
    },
]
wf["nodes"].extend(nuevos)

# --- 5. cableado ------------------------------------------------------------
salida = lambda destino: {"main": [[{"node": destino, "type": "main", "index": 0}]]}

assert con["Estado lead"]["main"][0] == [{"node": "Pausado?", "type": "main", "index": 0}], \
    "Estado lead no salia a Pausado?: el workflow cambio"

con["Estado lead"] = salida("Traer contacto")
con["Traer contacto"] = salida("Telefono del contacto")
con["Telefono del contacto"] = salida("Silenciado en la lista?")
con["Silenciado en la lista?"] = salida("Silenciado?")
# rama 0 = verdadero, rama 1 = falso
con["Silenciado?"] = {"main": [
    [{"node": "Marcar Lead pausado", "type": "main", "index": 0}],
    [{"node": "Pausado?", "type": "main", "index": 0}],
]}
con["Marcar Lead pausado"] = {"main": [[]]}

json.dump(wf, open(SRC, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

print("OK ->", SRC)
print("nodos:", len(wf["nodes"]), "(se agregaron 5)")
print("Traer lead:", wf["nodes"][[n["name"] for n in wf["nodes"]].index("Traer lead")]["parameters"]["url"])
print()
print("FALTA A MANO EN n8n: crear la credencial Header Auth 'Formen pausas'")
print("  nombre del header: x-clave")
print("  valor: la misma clave que PAUSA_CLAVE en Vercel")
print("y elegirla en el nodo 'Silenciado en la lista?' (en el JSON va un id placeholder).")
