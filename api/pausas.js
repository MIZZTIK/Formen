// Lista de numeros a los que el bot no le tiene que contestar.
//
// El vendedor le escribe a mano a alguien que todavia no es lead. Carga el numero aca,
// y cuando esa persona escribe al WhatsApp oficial, el workflow de n8n ve que esta en la
// lista, manda el lead a "Lead pausado" y se calla. A las 24 h vence solo.
//
//   GET    /api/pausas          -> los que estan vigentes
//   POST   /api/pausas          -> alta  { numero, cargadoPor }
//   DELETE /api/pausas?id=N     -> baja
//
// Todo pide la cabecera x-clave.

import { sql, asegurarTabla, normalizar, ultimos10, claveValida, HORAS_PAUSA } from './_lib.js';

export default async function handler(req, res) {
  if (!claveValida(req)) {
    return res.status(401).json({ error: 'Clave incorrecta.' });
  }

  try {
    await asegurarTabla();

    if (req.method === 'GET') {
      const filas = await sql`
        SELECT id, numero, cargado_por, creado, vence
        FROM pausas
        WHERE vence > now()
        ORDER BY creado DESC`;
      return res.status(200).json({ pausas: filas });
    }

    if (req.method === 'POST') {
      const cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
      const numero = normalizar(cuerpo.numero);
      if (!numero) {
        return res.status(400).json({
          error: 'No pude leer ese numero. Tiene que ser un celular argentino con codigo de area, por ejemplo 3794123456.',
        });
      }
      const cargadoPor = String(cuerpo.cargadoPor || '').slice(0, 60) || null;

      // Si ya estaba, se le renueva el vencimiento en vez de duplicar la fila.
      const previa = await sql`
        SELECT id FROM pausas WHERE ultimos10 = ${ultimos10(numero)} AND vence > now() LIMIT 1`;

      const vence = new Date(Date.now() + HORAS_PAUSA * 3600 * 1000).toISOString();

      if (previa.length) {
        const [fila] = await sql`
          UPDATE pausas SET vence = ${vence}, cargado_por = COALESCE(${cargadoPor}, cargado_por)
          WHERE id = ${previa[0].id}
          RETURNING id, numero, cargado_por, creado, vence`;
        return res.status(200).json({ pausa: fila, renovada: true });
      }

      const [fila] = await sql`
        INSERT INTO pausas (numero, ultimos10, cargado_por, vence)
        VALUES (${numero}, ${ultimos10(numero)}, ${cargadoPor}, ${vence})
        RETURNING id, numero, cargado_por, creado, vence`;
      return res.status(201).json({ pausa: fila, renovada: false });
    }

    if (req.method === 'DELETE') {
      const id = Number(req.query.id);
      if (!id) return res.status(400).json({ error: 'Falta el id.' });
      await sql`DELETE FROM pausas WHERE id = ${id}`;
      return res.status(200).json({ ok: true });
    }

    res.setHeader('Allow', 'GET, POST, DELETE');
    return res.status(405).json({ error: 'Metodo no permitido.' });
  } catch (e) {
    console.error('pausas:', e);
    return res.status(500).json({ error: 'No se pudo hablar con la base.' });
  }
}
