# -*- coding: utf-8 -*-
"""Formen v17: que los numeros se carguen solos cuando el vendedor escribe.

Hoy el local tiene que entrar a formen.ar/pausar.html y cargar el numero a mano para
que el bot no le conteste encima a un cliente que estan atendiendo ellos. Eso funciona,
pero depende de que alguien se acuerde — el tipo de habito que dura una semana.

Este workflow lo vuelve automatico. El vendedor escribe desde el celular del local como
siempre; Evolution API, vinculado a ese telefono como dispositivo, avisa por webhook, y
nosotros cargamos el numero en la misma lista que ya consulta el bot.

    Evolution (messages.upsert, fromMe) -> Webhook -> Filtrar saliente -> POST /api/pausas

Decisiones que ya vienen tomadas de la conversacion con Martin:
  - Evolution NO manda mensajes, solo escucha. El envio en frio automatizado desde un
    numero comun es el patron que WhatsApp banea, y el celular del local tiene historial
    real que no se puede perder.
  - Entra TODO 1-a-1 que no sea grupo. La linea es del negocio y no tiene chats
    personales, asi que lo unico que sobra son proveedores.
  - La pausa se renueva con cada mensaje saliente, o sea que vence 24 h despues del
    ULTIMO mensaje del humano y no del primero. Es lo que se quiere: mientras la persona
    sigue hablando, el bot sigue callado.

OJO — esto todavia NO se probo contra un payload real de Evolution, porque la instancia
no existe. El parseo es defensivo (si algo no coincide, descarta en silencio en vez de
romper), pero la PRIMERA vez que llegue un evento real hay que mirarlo con la skill
n8n-logs y confirmar que el numero se extrajo bien antes de darlo por bueno.

    python bot/scripts/formen_v17_carga_automatica.py

Despues, en n8n: importar el JSON generado, elegir la credencial "Formen pausas" en el
nodo "Cargar en la lista", activarlo, y apuntar el webhook de Evolution a su URL.
"""
import json
import os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(RAIZ, "formen", "workflow-carga-silenciados.json")

URL_ALTA = "https://www.formen.ar/api/pausas"
CRED_PAUSAS = {"httpHeaderAuth": {"id": "REEMPLAZAR-EN-N8N", "name": "Formen pausas"}}

JS_FILTRO = """// Evolution manda muchos eventos por el mismo webhook. Aca solo nos interesa uno:
// un mensaje que SALE del celular del local hacia una persona. Todo lo demas se
// descarta en silencio devolviendo [], que en n8n corta la ejecucion sin error.
const cuerpo = $json.body || $json;

// 1. Solo mensajes nuevos.
const evento = String(cuerpo.event || cuerpo.type || '').toLowerCase();
if (evento && evento.indexOf('messages.upsert') === -1) return [];

const data = cuerpo.data || cuerpo.message || {};
const key = data.key || {};

// 2. Solo salientes. Un mensaje entrante no significa que el humano este atendiendo:
//    puede ser cualquiera escribiendo al local.
if (key.fromMe !== true) return [];

// 3. Solo 1-a-1. Los grupos son @g.us y los estados @broadcast: afuera los dos.
const jid = String(key.remoteJid || '');
if (jid.indexOf('@s.whatsapp.net') === -1) return [];

// 4. El numero sale del JID. Ojo: para Argentina WhatsApp a veces entrega el JID con
//    el 9 y a veces sin el. No lo arreglamos aca a proposito: /api/pausas normaliza a
//    +549 al guardar, y la comparacion contra el bot es por los ultimos 10 digitos,
//    asi que engancha igual venga como venga.
const dig = jid.split('@')[0].replace(/\\D/g, '');
if (dig.length < 10) return [];

return [{ json: { numero: '+' + dig, ultimos10: dig.slice(-10) } }];"""

wf = {
    "name": "Formen - Cargar silenciados desde el celular",
    "nodes": [
        {
            "parameters": {
                "httpMethod": "POST",
                "path": "formen-celular",
                "options": {},
            },
            "type": "n8n-nodes-base.webhook",
            "typeVersion": 2,
            "position": [-600, 0],
            "id": "bb000000-0000-4000-8000-00000000c001",
            "name": "Webhook Evolution",
            "webhookId": "formen-celular-evolution",
        },
        {
            "parameters": {"jsCode": JS_FILTRO},
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [-400, 0],
            "id": "bb000000-0000-4000-8000-00000000c002",
            "name": "Filtrar saliente",
        },
        {
            "parameters": {
                "method": "POST",
                "url": URL_ALTA,
                "authentication": "genericCredentialType",
                "genericAuthType": "httpHeaderAuth",
                "sendBody": True,
                "specifyBody": "json",
                "jsonBody": ("={{ JSON.stringify({ numero: $json.numero, "
                             "cargadoPor: 'celular del local' }) }}"),
                "options": {"timeout": 8000},
            },
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 4.3,
            "position": [-200, 0],
            "id": "bb000000-0000-4000-8000-00000000c003",
            "name": "Cargar en la lista",
            "credentials": CRED_PAUSAS,
            # Si la carga falla, no queremos que el webhook devuelva error y Evolution
            # se ponga a reintentar: se pierde una pausa, no se rompe el circuito.
            "onError": "continueRegularOutput",
        },
    ],
    "connections": {
        "Webhook Evolution": {"main": [[{"node": "Filtrar saliente", "type": "main", "index": 0}]]},
        "Filtrar saliente": {"main": [[{"node": "Cargar en la lista", "type": "main", "index": 0}]]},
        "Cargar en la lista": {"main": [[]]},
    },
    "settings": {"executionOrder": "v1"},
    "pinData": {},
}

# --- controles antes de escribir -------------------------------------------
assert len(wf["nodes"]) == 3
nombres = [n["name"] for n in wf["nodes"]]
for origen, destinos in wf["connections"].items():
    assert origen in nombres, origen
    for rama in destinos["main"]:
        for c in rama:
            assert c["node"] in nombres, c["node"]
assert "REEMPLAZAR-EN-N8N" in json.dumps(wf), "la credencial tiene que quedar como placeholder"
assert "PAUSA_CLAVE" not in json.dumps(wf) and "clave" not in json.dumps(wf).lower().replace("formen pausas", "")

with open(DESTINO, "w", encoding="utf-8") as fh:
    json.dump(wf, fh, ensure_ascii=False, indent=2)

print("OK ->", DESTINO)
print("nodos:", " -> ".join(nombres))
print()
print("PARA PONERLO EN MARCHA, cuando exista la instancia de Evolution:")
print("  1. Importar el JSON en n8n y elegir la credencial 'Formen pausas' en")
print("     'Cargar en la lista' (en el JSON va un placeholder a proposito).")
print("  2. Activarlo y copiar la URL de produccion del webhook.")
print("  3. En Evolution, apuntar el webhook de la instancia a esa URL, con el")
print("     evento MESSAGES_UPSERT unicamente.")
print("  4. Con el PRIMER mensaje real, mirar la ejecucion con la skill n8n-logs y")
print("     confirmar que el numero se extrajo bien. El parseo no se probo todavia")
print("     contra un payload real de Evolution.")
