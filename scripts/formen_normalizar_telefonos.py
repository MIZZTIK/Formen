# -*- coding: utf-8 -*-
"""
Normaliza los telefonos de los contactos de Formen al formato que WhatsApp acepta: +549 + 10 digitos.

El problema: Kommo tiene los telefonos en tres formatos.
  - +5493794123331  (13 dig)  -> lo puso WhatsApp cuando el cliente escribio. FUNCIONA.
  - 3794227874      (10 dig)  -> lo tipea el mostrador a mano en Kommo. Plantilla rebota con 3126.
  - +543794403329   (12 dig)  -> lo carga el formulario del iPad, sin el 9. Plantilla rebota con 3126.

El 3126 de Kommo es el 131026 de Meta ("message undeliverable"), que es un bucket error:
Kommo lo explica como "el destinatario no acepto los terminos", pero una de las causas
documentadas es el numero mal formateado, y Argentina es caso conocido por el 9.

Por defecto corre EN SECO: muestra que haria y no toca nada.
Con --aplicar escribe, y antes guarda un backup id -> valor viejo para poder revertir.

    python scripts/formen_normalizar_telefonos.py
    python scripts/formen_normalizar_telefonos.py --aplicar
    python scripts/formen_normalizar_telefonos.py --revertir backups/telefonos_AAAAMMDD_HHMMSS.json
"""
import argparse
import datetime
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

CUENTA = "Formen"
# OJO: el campo Phone del CONTACTO es 326778. El 326786 del CLAUDE.md es el utm_content
# del LEAD, otra entidad. Kommo acepta el PATCH con 200 y descarta el campo desconocido
# sin decir nada, asi que el error es mudo. Igual el id real se toma de cada contacto leido.
CAMPO_TELEFONO = 326778

# contactos de prueba que no hay que tocar
IGNORAR = {"5455555555555", "5411111111111", "543794000001"}

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_BACKUP = os.path.join(RAIZ, "backups")


def credenciales():
    ruta = os.path.expanduser("~/.claude/kommo.json")
    with io.open(ruta, encoding="utf-8-sig") as fh:
        d = json.load(fh)
    c = d["cuentas"][CUENTA]
    return c["subdominio"], c["token"]


def api(sub, tok, path, metodo="GET", body=None):
    datos = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        "https://%s.kommo.com%s" % (sub, path),
        data=datos,
        method=metodo,
        headers={
            "Authorization": "Bearer %s" % tok,
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0",
        },
    )
    with urllib.request.urlopen(req) as r:
        crudo = r.read()
    return json.loads(crudo) if crudo else {}


def normalizar(crudo):
    """Devuelve (nuevo_valor, motivo). nuevo_valor None = no tocar."""
    dig = re.sub(r"\D", "", str(crudo))
    if not dig:
        return None, "vacio"
    if dig in IGNORAR:
        return None, "contacto de prueba"
    if dig.startswith("549") and len(dig) == 13:
        return None, "ya esta bien"
    # solo tocamos lo que parece argentino
    if dig.startswith("54"):
        resto = dig[2:]
    elif len(dig) == 10 and dig[0] in "23":
        resto = dig  # 10 digitos pelados: area + abonado
    elif len(dig) == 11 and dig.startswith("0"):
        resto = dig[1:]
    else:
        return None, "no parece argentino"
    if resto.startswith("0"):
        resto = resto[1:]
    # el 15 va despues del codigo de area (2 a 4 digitos) y sobra en formato internacional
    if len(resto) in (11, 12):
        for corte in (2, 3, 4):
            if resto[corte:corte + 2] == "15" and len(resto) - 2 == 10:
                resto = resto[:corte] + resto[corte + 2:]
                break
    if resto.startswith("9") and len(resto) == 11:
        resto = resto[1:]
    if len(resto) != 10:
        return None, "queda en %d digitos, revisar a mano" % len(resto)
    return "+549" + resto, "corregido"


def traer_contactos(sub, tok):
    for page in range(1, 40):
        try:
            r = api(sub, tok, "/api/v4/contacts?limit=250&page=%d&with=leads" % page)
        except urllib.error.HTTPError as e:
            if e.code == 204:
                return
            raise
        cs = r.get("_embedded", {}).get("contacts", [])
        if not cs:
            return
        for ct in cs:
            yield ct


def campo_telefono(ct):
    for f in ct.get("custom_fields_values") or []:
        if f.get("field_code") == "PHONE" or f.get("field_id") == CAMPO_TELEFONO:
            return f
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aplicar", action="store_true", help="escribir en Kommo (por defecto corre en seco)")
    ap.add_argument("--revertir", metavar="BACKUP", help="restaurar los valores de un backup")
    args = ap.parse_args()

    sub, tok = credenciales()

    if args.revertir:
        with io.open(args.revertir, encoding="utf-8") as fh:
            previo = json.load(fh)
        lote = []
        for reg in previo:
            lote.append({
                "id": reg["contacto"],
                "custom_fields_values": [{
                    "field_id": reg.get("field_id", CAMPO_TELEFONO),
                    "values": reg["values_antes"],
                }],
            })
        for i in range(0, len(lote), 50):
            api(sub, tok, "/api/v4/contacts", "PATCH", lote[i:i + 50])
            time.sleep(0.4)
        print("revertidos %d contactos desde %s" % (len(lote), args.revertir))
        return

    cambios, dudosos = [], []
    for ct in traer_contactos(sub, tok):
        f = campo_telefono(ct)
        if not f:
            continue
        antes = [dict(v) for v in f["values"]]
        despues = [dict(v) for v in f["values"]]
        toco = False
        for i, v in enumerate(f["values"]):
            nuevo, motivo = normalizar(v.get("value"))
            if nuevo:
                despues[i]["value"] = nuevo
                toco = True
            elif motivo.startswith("queda en"):
                dudosos.append((ct["id"], ct.get("name"), v.get("value"), motivo))
        if toco:
            cambios.append({
                "contacto": ct["id"],
                "nombre": ct.get("name"),
                "field_id": f["field_id"],
                "leads": [l["id"] for l in ct.get("_embedded", {}).get("leads", [])],
                "values_antes": antes,
                "values_despues": despues,
            })

    print("=" * 78)
    for c in cambios:
        viejo = ", ".join(str(v.get("value")) for v in c["values_antes"])
        nuevo = ", ".join(str(v.get("value")) for v in c["values_despues"])
        print("  %-9s %-26s %-16s -> %s" % (c["contacto"], str(c["nombre"] or "")[:26], viejo, nuevo))
    print("=" * 78)
    print("a corregir: %d contactos" % len(cambios))
    if dudosos:
        print("\nA REVISAR A MANO (no los toco):")
        for cid, nom, val, motivo in dudosos:
            print("  %-9s %-26s %-16s %s" % (cid, str(nom or "")[:26], val, motivo))

    if not args.aplicar:
        print("\n[EN SECO] no se escribio nada. Para aplicar: --aplicar")
        return
    if not cambios:
        return

    os.makedirs(DIR_BACKUP, exist_ok=True)
    sello = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    ruta_backup = os.path.join(DIR_BACKUP, "telefonos_%s.json" % sello)
    with io.open(ruta_backup, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(cambios, ensure_ascii=False, indent=1))
    print("\nbackup en %s" % ruta_backup)

    lote = [{
        "id": c["contacto"],
        "custom_fields_values": [{"field_id": c["field_id"], "values": c["values_despues"]}],
    } for c in cambios]

    escritos = 0
    for i in range(0, len(lote), 50):
        tanda = lote[i:i + 50]
        for intento in range(3):
            try:
                api(sub, tok, "/api/v4/contacts", "PATCH", tanda)
                escritos += len(tanda)
                break
            except urllib.error.HTTPError as e:
                print("  error %s en la tanda %d, intento %d" % (e.code, i // 50 + 1, intento + 1))
                time.sleep(3)
        time.sleep(0.4)
    print("escritos: %d/%d" % (escritos, len(lote)))

    # verificar leyendo, no confiar en el PATCH
    malos = 0
    for c in cambios[:]:
        ct = api(sub, tok, "/api/v4/contacts/%d" % c["contacto"])
        f = campo_telefono(ct)
        vals = [str(v.get("value")) for v in (f["values"] if f else [])]
        esperado = [str(v.get("value")) for v in c["values_despues"]]
        if vals != esperado:
            malos += 1
            print("  NO QUEDO: %s tiene %s, esperaba %s" % (c["contacto"], vals, esperado))
        time.sleep(0.1)
    print("verificados leyendo: %d con diferencia" % malos)


if __name__ == "__main__":
    sys.exit(main())
