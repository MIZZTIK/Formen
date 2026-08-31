# -*- coding: utf-8 -*-
"""Formen v15: bajar el tono del bot a sobrio.

Pedido de Agustin (dueno) el 2026-08-26: "que sea menos expresivo".

El bot no se habia desviado: el prompt le PEDIA ser expresivo. Sobre 133 respuestas
reales de 14 dias medimos 1,5 exclamaciones por respuesta y 38 arranques con "!Hola",
que es literalmente el ejemplo de calibracion que traia el prompt.

Cuatro cambios, todos sobre el systemMessage del nodo "AI Agent":
  1. "TONO DE VOZ (vendedor)"  -> "(sobrio)": prohibe exclamaciones, superlativos y
     celebraciones. Aclara que la INFORMACION no se recorta, solo el adorno.
  2. "LONGITUD Y ESTRUCTURA": saca "gancho de apertura" y "descripcion atractiva",
     manteniendo que la respuesta de producto sea completa (precios + vinetas + cierre).
  3. El ejemplo de calibracion de TRAJES, reescrito sobrio. Es el cambio que mas pesa:
     el modelo copiaba ese ejemplo casi textual.
  4. El ejemplo de reserva: "!Muchas gracias! Ya quedo separado tu ambo." -> "Listo, ...".
     Si queda un solo "!" de ejemplo en el prompt, el modelo lo imita.

Se opera sobre el JSON del repo IN-PLACE, porque este archivo es el workflow vigente.
La version equivalente ya fue publicada en n8n por la API el 2026-08-26; este script
deja el repo igual a produccion.

Comprobacion: al terminar, el sha1 del prompt tiene que dar 6e0dd1... (ver salida).
"""
import json
import hashlib
import os
import re

# Relativo a este archivo: el repo se unifico el 28/08 y la ruta absoluta quedo vieja.
SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "formen", "workflow-formen.json")

wf = json.load(open(SRC, encoding="utf-8"))
nodos = [n for n in wf["nodes"]
         if isinstance((n.get("parameters") or {}).get("options"), dict)
         and "systemMessage" in n["parameters"]["options"]]
assert len(nodos) == 1, f"se esperaba 1 nodo con systemMessage, hay {len(nodos)}"
prompt = nodos[0]["parameters"]["options"]["systemMessage"]

sha_viejo = hashlib.sha1(prompt.encode()).hexdigest()
assert sha_viejo.startswith("48c85f0ee3ae"), f"el prompt de partida no es el esperado: {sha_viejo[:12]}"

L = prompt.split("\n")

# --- 1. TONO DE VOZ ---------------------------------------------------------
assert L[6] == "## TONO DE VOZ (vendedor)", L[6]
assert L[10].startswith("- NO uses emojis NUNCA"), L[10]
L[6:11] = [
    "## TONO DE VOZ (sobrio)",
    "- Cordial y profesional, nunca efusivo. Español de Argentina, trato de vos.",
    '- Sin signos de exclamación, ni de apertura ni de cierre. Saludá "Hola, ¿cómo estás?" o "Buenas tardes".',
    '- Sin adjetivos publicitarios ni superlativos: nada de "excelente", "impecable", "ideal", '
    '"de primera calidad", "qué bueno", "genial", "perfecto". Los diferenciales se enuncian como hechos, '
    "no como elogios.",
    '- No celebres la compra ni la consulta ("nos alegra muchísimo", "gracias por elegirnos", '
    '"excelente elección"). Respondé lo que se preguntó.',
    "- La información va COMPLETA igual: precios, marcas, talles y diferenciales. "
    "Se recorta el adorno, no el contenido.",
    "- NO uses emojis NUNCA.",
]

# --- 2. LONGITUD Y ESTRUCTURA ----------------------------------------------
i = L.index("## LONGITUD Y ESTRUCTURA")
assert L[i + 1].startswith("Tus respuestas sobre productos NUNCA"), L[i + 1]
L[i + 1] = (
    "Las respuestas sobre productos tienen que dar la información completa, no una sola oración suelta. "
    "Estructura: una línea breve de contexto + precios (el más económico primero), enunciados en seco + "
    "diferenciales en viñetas (•) + (solo si es la primera vez que corresponde) el cierre de venta. "
    "Usá saltos de línea para separar bloques. NO uses emojis. Sin gancho de apertura ni descripciones "
    "atractivas: el dato alcanza."
)

# --- 3. EJEMPLO DE CALIBRACION (el que mas pesa) ----------------------------
j = [k for k, l in enumerate(L) if l.startswith("### Ejemplo de tono para TRAJES")][0]
assert L[j + 1].startswith('> "¡Hola!'), L[j + 1]
fin = j + 1
while not L[fin].rstrip().endswith('asesoramiento."'):
    fin += 1
L[j:fin + 1] = [
    "### Ejemplo de tono para TRAJES (calibración — sobrio, sin exclamaciones, SIN emojis)",
    '> "Hola, ¿cómo estás? Te paso los precios de los trajes.',
    ">",
    "> Arrancan desde $349.890, con opciones en $449.890, y hay más alternativas según la calidad.",
    ">",
    "> • Marcas: Rochas, La Dolfina, Hechter, Rinaldi y John Nicols.",
    "> • Talles del 42 al 70, en azul, negro, gris, beige, bordó y verde. También hay smoking.",
    "> • Los arreglos de sastrería, la tintorería y el planchado están incluidos sin costo.",
    ">",
    "> Se puede abonar en cuotas sin interés con tarjetas bancarias, o en efectivo con descuento. "
    'Te esperamos en Mendoza 758 si querés verlos en persona."',
]

# --- 4. EJEMPLO DE RESERVA --------------------------------------------------
k = [x for x, l in enumerate(L) if "separado tu ambo" in l][0]
L[k] = re.sub(r'"[^"]*separado tu ambo\."', '"Listo, quedó separado tu ambo."', L[k])
assert "Listo, qued" in L[k], L[k]

nuevo = "\n".join(L)

# --- control duro: ni una exclamacion queda en el prompt --------------------
exclamaciones = re.findall(r"[!¡]", nuevo)
assert not exclamaciones, f"quedaron {len(exclamaciones)} exclamaciones en el prompt"

nodos[0]["parameters"]["options"]["systemMessage"] = nuevo
json.dump(wf, open(SRC, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

sha_nuevo = hashlib.sha1(nuevo.encode()).hexdigest()
print("OK ->", SRC)
print(f"prompt: {len(prompt)} -> {len(nuevo)} caracteres")
print(f"sha1:   {sha_viejo[:12]} -> {sha_nuevo[:12]}")
print("exclamaciones restantes:", len(exclamaciones))
