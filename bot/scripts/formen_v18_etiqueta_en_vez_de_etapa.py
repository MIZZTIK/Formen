# -*- coding: utf-8 -*-
"""Formen v18: que el silencio automatico etiquete el lead en vez de moverlo de etapa.

En v16 el bot, al encontrar el numero en la lista, mandaba el lead a "Lead pausado".
Parecia prolijo porque reusaba el mecanismo que ya existia, pero tenia un agujero:
la fila de la lista vence sola a las 12 h y la etapa NO. El lead quedaba pausado para
siempre y el cliente dejaba de recibir respuestas sin que nadie se entere.

Decidido con Martin el 2026-09-01 (opcion B de dos):

  - La LISTA es la unica fuente de verdad del silencio automatico. Vence sola con un
    "vence > now()" en la base, que no se cae ni se olvida, y no hace falta ningun
    proceso programado que despause.
  - La ETAPA "Lead pausado" queda reservada para la pausa MANUAL, la del Salesbot
    "Detener bot" de Kommo cuando alguien del local escribe desde la ficha. Esa sigue
    funcionando igual que siempre y sigue siendo indefinida a proposito.
  - El silencio automatico se marca con la etiqueta "Atendido a mano", que es señal
    visual para el equipo y no mecanismo.

El motivo de fondo para elegir esta y no un cron que despause: si esto falla, el bot
habla de mas una vez — molesto, visible, se arregla. Si fallara el cron, un lead queda
mudo para siempre y nadie se entera. Este proyecto ya tuvo dos fallas mudas (el conector
descartando ventas y el reporte -Medir mintiendo); no sumamos una tercera.

Dos cambios:
  1. "Estado lead" ahora devuelve tambien el NOMBRE de las etiquetas, para poder
     preguntar si la etiqueta ya esta antes de volver a agregarla.
  2. "Marcar Lead pausado" pasa a llamarse "Marcar atendido a mano" y, en vez de
     escribir status_id, agrega la etiqueta preservando las que ya tenia.

    python bot/scripts/formen_v18_etiqueta_en_vez_de_etapa.py
"""
import json
import os

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "formen", "workflow-formen.json")

ETIQUETA = "Atendido a mano"

wf = json.load(open(SRC, encoding="utf-8"))
nodos = {n["name"]: n for n in wf["nodes"]}
con = wf["connections"]

assert "Marcar Lead pausado" in nodos, "falta el nodo de v16: corre antes formen_v16_lista_silenciados.py"
assert "Marcar atendido a mano" not in nodos, "el parche ya se aplico"

# --- 1. las etiquetas viajan con su nombre ---------------------------------
cod = nodos["Estado lead"]["parameters"]["jsCode"]
vieja = "const tags = (emb.tags || []).map(t => ({ id: t.id }));"
assert vieja in cod, "el armado de tags de 'Estado lead' no es el esperado"
nodos["Estado lead"]["parameters"]["jsCode"] = cod.replace(
    vieja,
    "// El nombre hace falta para no volver a agregar una etiqueta que ya esta.\n"
    "const tags = (emb.tags || []).map(t => ({ id: t.id, name: t.name }));")

# --- 2. el nodo etiqueta en vez de mover de etapa --------------------------
nodo = nodos["Marcar Lead pausado"]
assert "status_id" in nodo["parameters"]["jsonBody"], nodo["parameters"]["jsonBody"]

nodo["name"] = "Marcar atendido a mano"
nodo["parameters"]["jsonBody"] = (
    "={{ JSON.stringify({ _embedded: { tags: (() => {"
    " const t = $('Estado lead').first().json.tags || [];"
    " return t.some(x => x.name === '%s') ? t : t.concat([{ name: '%s' }]);"
    " })() } }) }}" % (ETIQUETA, ETIQUETA)
)

# --- 3. el cableado sigue el nombre nuevo ----------------------------------
con["Marcar atendido a mano"] = con.pop("Marcar Lead pausado")
for destinos in con.values():
    for rama in destinos.get("main", []):
        for c in rama:
            if c["node"] == "Marcar Lead pausado":
                c["node"] = "Marcar atendido a mano"

# --- controles --------------------------------------------------------------
crudo = json.dumps(wf, ensure_ascii=False)
assert "Marcar Lead pausado" not in crudo, "quedo alguna referencia al nombre viejo"
assert crudo.count("108221251") == 1, \
    "la etapa Lead pausado tiene que quedar SOLO en la condicion de 'Pausado?' (pausa manual)"
nombres = [n["name"] for n in wf["nodes"]]
for origen, destinos in con.items():
    assert origen in nombres, origen
    for rama in destinos.get("main", []):
        for c in rama:
            assert c["node"] in nombres, c["node"]

json.dump(wf, open(SRC, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

print("OK ->", SRC)
print("  'Marcar Lead pausado' -> 'Marcar atendido a mano'")
print("  ahora agrega la etiqueta %r en vez de escribir status_id" % ETIQUETA)
print("  la etapa 108221251 queda solo en 'Pausado?', que es la pausa manual")
