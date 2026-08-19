# -*- coding: utf-8 -*-
"""AVC v17: (1) regla de idioma FUERTE (responder en el idioma del cliente; muchos son de Brasil/portugues);
   (2) presentacion formal y profesional. Ademas: credencial OpenAI real 'AVC' y modelo gpt-4.1-mini
   (para matchear el flujo en vivo de Martin)."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v16-buffer-emoji.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v17-idioma-intro.json"

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}

# ---------- credencial OpenAI real + modelo (matchear el flujo en vivo) ----------
n["OpenAI Chat Model"]["credentials"]["openAiApi"] = {"id": "U8exa9B7bGjLh4cw", "name": "AVC"}
n["OpenAI Chat Model"]["parameters"]["model"]["value"] = "gpt-4.1-mini"
n["OpenAI Chat Model"]["parameters"]["model"]["cachedResultName"] = "gpt-4.1-mini"

sm = n["AI Agent"]["parameters"]["options"]["systemMessage"]

# ---------- 1) REGLA DE IDIOMA fuerte ----------
antes_idioma = "IDIOMA: Detecta el idioma del cliente y responde en ese idioma (Espanol, Ingles o Portugues). Por defecto Espanol (Paraguay), tono profesional, cordial y breve."
despues_idioma = ("IDIOMA (REGLA CRITICA, NO LA IGNORES): Responde SIEMPRE en el MISMO idioma en que te escribe el cliente. "
"MUCHOS clientes son de BRASIL y escriben en PORTUGUES: en ese caso responde TODO en portugues (saludo, preguntas, "
"agenda, cierre, absolutamente todo). Si te escribe en ingles, responde en ingles. "
"PROHIBIDO responder en espanol a alguien que te escribio en portugues o en ingles. "
"Solo usa espanol (Paraguay) si el cliente escribe en espanol o si no se puede determinar el idioma. "
"Fijate en el 'Mensaje del cliente' para detectar el idioma en CADA respuesta. Tono profesional, cordial y de confianza.")
assert antes_idioma in sm, "no se encontro la linea IDIOMA"
sm = sm.replace(antes_idioma, despues_idioma)

# ---------- 2) PRESENTACION formal ----------
antes_p1 = "1. SOLO en el primer mensaje (etapa 'Leads entrantes'): saluda presentandote como AVC y pedi el nombre (customerName). Si la etapa ya es 'Contactado' o posterior, NO saludes de nuevo."
despues_p1 = ("1. SOLO en el primer mensaje (etapa 'Leads entrantes'): presentate de forma FORMAL y PROFESIONAL, que inspire "
"confianza y seriedad, con el nombre completo 'AVC Soluciones Empresariales', y pedi el nombre del cliente (customerName). "
"Adapta el saludo al IDIOMA del cliente. Ejemplos del tono buscado:\n"
"   - Espanol: 'Le damos la bienvenida a AVC Soluciones Empresariales, su consultora de confianza en asesoria empresarial integral. Sera un gusto acompanarlo. Para comenzar, con quien tengo el gusto de hablar?'\n"
"   - Portugues: 'Seja bem-vindo a AVC Soluciones Empresariales, sua consultoria de confianca em assessoria empresarial integral. Sera um prazer acompanha-lo. Para comecar, com quem eu tenho o prazer de falar?'\n"
"   Si la etapa ya es 'Contactado' o posterior, NO saludes ni te presentes de nuevo.")
assert antes_p1 in sm, "no se encontro el paso 1 del flujo"
sm = sm.replace(antes_p1, despues_p1)

n["AI Agent"]["parameters"]["options"]["systemMessage"] = sm

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("OpenAI cred:", n["OpenAI Chat Model"]["credentials"]["openAiApi"])
print("modelo:", n["OpenAI Chat Model"]["parameters"]["model"]["value"])
print("regla idioma fuerte:", "REGLA CRITICA" in sm)
print("presentacion formal:", "su consultora de confianza" in sm)
print("presentacion portugues:", "sua consultoria de confianca" in sm)
