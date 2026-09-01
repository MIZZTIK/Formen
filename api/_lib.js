// Helpers compartidos por las funciones de /api.
// Los archivos que empiezan con _ no son rutas: Vercel los ignora como endpoint.

import { neon } from '@neondatabase/serverless';

export { normalizar, ultimos10 } from './_numero.js';

const URL_BASE = process.env.DATABASE_URL || process.env.POSTGRES_URL;

export const sql = neon(URL_BASE);

// Horas que un numero queda silenciado desde que se carga.
// 12 y no 24: decidido con Martin el 2026-09-01. Es la ventana en la que se espera que
// el cliente conteste el mensaje que le mando el vendedor a mano.
export const HORAS_PAUSA = 12;

let tablaLista = false;

/**
 * Crea la tabla la primera vez. Es idempotente, asi que alcanza con crear la base
 * en Neon: no hace falta correr migraciones a mano.
 */
export async function asegurarTabla() {
  if (tablaLista) return;
  await sql`
    CREATE TABLE IF NOT EXISTS pausas (
      id          SERIAL PRIMARY KEY,
      numero      TEXT NOT NULL,
      ultimos10   TEXT NOT NULL,
      cargado_por TEXT,
      creado      TIMESTAMPTZ NOT NULL DEFAULT now(),
      vence       TIMESTAMPTZ NOT NULL
    )`;
  await sql`CREATE INDEX IF NOT EXISTS pausas_ultimos10_idx ON pausas (ultimos10)`;
  await sql`CREATE INDEX IF NOT EXISTS pausas_vence_idx ON pausas (vence)`;
  tablaLista = true;
}

/** La clave compartida vive en una variable de entorno de Vercel, nunca en el repo. */
export function claveValida(req) {
  const esperada = process.env.PAUSA_CLAVE;
  if (!esperada) return false;
  const dada = req.headers['x-clave'] || '';
  return dada === esperada;
}
