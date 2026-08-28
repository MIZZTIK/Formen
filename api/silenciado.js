// Lo que consulta el bot antes de contestar.
//
//   GET /api/silenciado?ultimos10=3794123456   ->  { "silenciado": true|false }
//
// Se compara por los ultimos 10 digitos a proposito: asi engancha aunque el numero
// este guardado como 3794123456, +543794123456 o +5493794123456.
//
// Si esto falla, el bot contesta igual (falla abierta). Es la decision correcta:
// peor que el bot hable de mas es que se quede mudo con todos los clientes.

import { sql, asegurarTabla, ultimos10, claveValida } from './_lib.js';

export default async function handler(req, res) {
  if (!claveValida(req)) {
    return res.status(401).json({ error: 'Clave incorrecta.' });
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Metodo no permitido.' });
  }

  const clave = ultimos10(req.query.ultimos10);
  if (clave.length !== 10) {
    return res.status(200).json({ silenciado: false, motivo: 'numero ilegible' });
  }

  try {
    await asegurarTabla();
    const filas = await sql`
      SELECT numero, vence FROM pausas
      WHERE ultimos10 = ${clave} AND vence > now()
      LIMIT 1`;

    if (!filas.length) return res.status(200).json({ silenciado: false });
    return res.status(200).json({ silenciado: true, numero: filas[0].numero, vence: filas[0].vence });
  } catch (e) {
    console.error('silenciado:', e);
    return res.status(500).json({ error: 'No se pudo hablar con la base.' });
  }
}
