# -*- coding: utf-8 -*-
"""AVC v13: agrega el flujo de precalificacion de INVERSORES / Ley de Maquila al prompt."""
import json

SRC = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v12-pausa-personal.json"
OUT = r"C:\Users\marti\OneDrive\Escritorio\AVC-workflow-n8n-v13-inversores.json"

SECCION = """FLUJO ESPECIAL: INVERSORES / LEY DE MAQUILA (Paraguay)
ACTIVACION: si el cliente expresa interes en INVERTIR EN PARAGUAY (o menciona inversion extranjera, Ley de Maquila, regimen de incentivos fiscales, zona franca, radicar o constituir una empresa para invertir), DEJA el flujo general y segui ESTE guion de precalificacion. Poné servicioInteres = "Inversion extranjera (Ley de Maquila)" (en este caso especifico se permite este servicio aunque no este en la lista de los 7).

REGLAS DEL GUION:
- Haces UNA pregunta por mensaje, en orden, y esperas la respuesta. NO mandes todas las preguntas juntas.
- Usa los textos tal cual (podes adaptar minimamente, manteniendo el sentido y la formalidad).
- Interpreta respuestas afirmativas/negativas aunque el cliente conteste informal (si, no, "mas o menos", "unos 80 mil", etc.).

SECUENCIA:
1. (Primer mensaje del flujo) "Gracias por su interes en invertir en Paraguay. Le hare unas preguntas breves para identificar el regimen que podria ajustarse mejor a su proyecto." Y a continuacion hace la pregunta 2.
2. "La inversion inicial estimada sera igual o superior a USD 50.000?"
   - Si la respuesta es NO / menor a 50.000 -> anda directo al PASO 8.
   - Si es SI / igual o mayor -> segui con la 3.
3. "Su proyecto esta orientado principalmente a vender bienes o servicios a clientes del exterior?"
4. "La actividad necesita instalarse fisicamente dentro de una zona franca para almacenar, transformar, ensamblar o reexportar productos?"
5. "El proyecto incluye maquinarias, equipos, ampliacion productiva, tecnologia, empleo o materias primas industriales?"
   (Las respuestas de la 3, 4 y 5 son informativas: registralas para el asesor; NO cambian el resultado. El unico filtro duro es la 2.)
6. "Con la informacion proporcionada, su proyecto presenta compatibilidad preliminar. El siguiente paso es una reunion de diagnostico y revision documental."
7. "Para orientarle correctamente necesitamos algunos datos adicionales sobre inversion, actividad, clientes, ubicacion y proceso operativo."
   -> Luego COORDINA la reunion de diagnostico por Google Meet con las MISMAS reglas de agenda (lunes a viernes, turnos en punto, al menos 2 dias de antelacion, solo de los TURNOS DISPONIBLES REALES, reunion de 1 hora). Al confirmar, poné agendar:true con email y fechaHoraISO como siempre.
8. (NO CALIFICA para incentivos, inversion menor a USD 50.000) "Por ahora el proyecto no coincide con los criterios principales del regimen de incentivos fiscales, pero podemos evaluar alternativas de formalizacion. Podemos ayudarlo con su radicacion, constitucion y formalizacion de su empresa, emprendimiento o algun otro servicio de su interes." -> IGUAL ofrecele coordinar una reunion para ver esas alternativas (mismo mecanismo de agenda). NO lo despidas sin ofrecer la reunion.

REGISTRO PARA EL ASESOR: en el campo "tema" resumi las respuestas de la calificacion. Ej: "Inversion >=50k: si; vende al exterior: si; zona franca: no; maquinaria/tecnologia: si".

"""

wf = json.load(open(SRC, encoding="utf-8"))
n = {x["name"]: x for x in wf["nodes"]}
sm = n["AI Agent"]["parameters"]["options"]["systemMessage"]

ancla = "CANCELACION:"
assert ancla in sm, "no se encontro CANCELACION"
sm = sm.replace(ancla, SECCION + ancla, 1)
n["AI Agent"]["parameters"]["options"]["systemMessage"] = sm

json.dump(wf, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", OUT)
print("prompt nuevo:", len(sm), "chars")
print("tiene seccion inversores:", "FLUJO ESPECIAL: INVERSORES" in sm)
print("tiene el filtro 50.000:", "50.000" in sm)
print("paso 8 ofrece reunion:", "IGUAL ofrecele coordinar una reunion" in sm)
