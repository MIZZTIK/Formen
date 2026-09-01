# -*- coding: utf-8 -*-
"""Formen v20: enganchar la credencial real y dejar los workflows listos para publicar.

Hasta ahora los dos workflows traian el placeholder REEMPLAZAR-EN-N8N en la credencial
"Formen pausas", porque las credenciales no se versionan: en el repo va el id, nunca el
valor. Martin creo la credencial el 01/09 y su id es X9LLzlLHYy5ZZm8w.

Ademas se le pone al workflow del bot su id de PRODUCCION. Sin id, `n8n import:workflow`
crea uno nuevo que choca con el que corre por el mismo path de webhook (`formen`), el
import parece salir bien y el bot se queda con la version vieja. Con el id, la
importacion actualiza en el lugar: conserva el webhook registrado y el estado activo.

    python bot/scripts/formen_v20_enganchar_credencial.py
"""
import json
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CRED_PAUSAS = "X9LLzlLHYy5ZZm8w"        # credencial Header Auth "Formen pausas"
ID_BOT_PRODUCCION = "D3y4QTdgfbgSdtCT"  # el workflow que ya corre: "Formen - Asistente IA"

PLACEHOLDER = "REEMPLAZAR-EN-N8N"

archivos = [
    os.path.join(BASE, "formen", "workflow-formen.json"),
    os.path.join(BASE, "formen", "workflow-carga-silenciados.json"),
]

for ruta in archivos:
    with open(ruta, encoding="utf-8") as fh:
        crudo = fh.read()
    assert PLACEHOLDER in crudo, "%s no tiene el placeholder: ya se aplico?" % os.path.basename(ruta)
    crudo = crudo.replace(PLACEHOLDER, CRED_PAUSAS)

    wf = json.loads(crudo)

    if os.path.basename(ruta) == "workflow-formen.json":
        assert "id" not in wf or wf["id"] == ID_BOT_PRODUCCION, wf.get("id")
        wf = {"id": ID_BOT_PRODUCCION, **{k: v for k, v in wf.items() if k != "id"}}

    # control: el valor de la clave NUNCA puede terminar en el repo
    texto = json.dumps(wf, ensure_ascii=False)
    assert "x-clave" not in texto, "el nombre del header no va en el workflow, va en la credencial"
    assert PLACEHOLDER not in texto

    with open(ruta, "w", encoding="utf-8") as fh:
        json.dump(wf, fh, ensure_ascii=False, indent=2)

    usos = texto.count(CRED_PAUSAS)
    print("  %-32s id=%-18s credencial enganchada en %d nodo(s)"
          % (os.path.basename(ruta), wf.get("id"), usos))

print()
print("Listo para publicar por CLI:")
print("  docker exec n8n-06ir-n8n-1 n8n import:workflow --input=<archivo>")
print("y despues UN reinicio del contenedor, porque n8n mantiene en memoria los")
print("workflows activos y no toma los cambios hechos por CLI hasta reiniciar.")
