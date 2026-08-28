// Funciones puras, sin dependencias, para poder probarlas con node antes de publicar.

/**
 * Deja el numero como lo entrega WhatsApp: +549 + 10 digitos.
 *
 * Nadie tipea el +549, y sin el Kommo no reconoce que el mensaje entrante es de esta
 * misma persona: crea un contacto nuevo y el bot contesta igual. Por eso la normalizacion
 * no es cosmetica, es lo que hace que la pausa enganche.
 *
 * Devuelve null si no se puede llevar a esa forma, asi el que carga se entera en el
 * momento en vez de descubrirlo cuando el bot ya habló de más.
 */
export function normalizar(crudo) {
  let dig = String(crudo || '').replace(/\D/g, '');
  if (!dig) return null;

  if (dig.startsWith('549') && dig.length === 13) return '+' + dig;

  if (dig.startsWith('54')) dig = dig.slice(2);
  if (dig.startsWith('0')) dig = dig.slice(1);

  // el 15 va despues del codigo de area (2 a 4 digitos) y sobra en formato internacional
  if (dig.length === 11 || dig.length === 12) {
    for (const corte of [2, 3, 4]) {
      if (dig.slice(corte, corte + 2) === '15' && dig.length - 2 === 10) {
        dig = dig.slice(0, corte) + dig.slice(corte + 2);
        break;
      }
    }
  }
  if (dig.startsWith('9') && dig.length === 11) dig = dig.slice(1);

  if (dig.length !== 10) return null;

  // Los codigos de area argentinos arrancan con 1 (solo el 11), 2 o 3. Un numero que
  // empieza con 15 es alguien que escribio el 15 sin la caracteristica: no se puede
  // adivinar de que ciudad es, asi que se rechaza en vez de inventar uno que parezca
  // valido y despues no le llegue a nadie.
  if (dig.startsWith('15') || !'123'.includes(dig[0])) return null;

  return '+549' + dig;
}

/** Clave de comparacion: aguanta cualquier formato que a alguien se le ocurra escribir. */
export function ultimos10(numero) {
  return String(numero || '').replace(/\D/g, '').slice(-10);
}
