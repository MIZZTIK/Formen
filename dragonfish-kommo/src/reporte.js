'use strict';

// Medición del apareo. Es lo que decide si el conector se prende de verdad:
// se deja correr con DRY_RUN=true un par de semanas después de que el local
// empiece a pasar el iPad al cobrar, y se mira la tasa de asociación.
//
//   data/reporte.jsonl  una línea por venta evaluada (para revisar a mano)
//   data/reporte.json   acumulado por día

const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', 'data');
const DETALLE = path.join(DIR, 'reporte.jsonl');
const RESUMEN = path.join(DIR, 'reporte.json');

function hoy() {
  return new Date().toISOString().slice(0, 10);
}

function registrar(resultado, venta, candidatos, extra = {}) {
  fs.mkdirSync(DIR, { recursive: true });
  const linea = {
    ts: new Date().toISOString(),
    resultado,
    venta: venta.comprobante,
    venta_ts: venta.ts instanceof Date ? venta.ts.toISOString() : venta.ts,
    total: venta.total,
    candidatos: (candidatos || []).map((c) => c.id),
    ...extra,
  };
  fs.appendFileSync(DETALLE, JSON.stringify(linea) + '\n', 'utf8');
}

function acumular(stats) {
  fs.mkdirSync(DIR, { recursive: true });
  let data = {};
  try {
    data = JSON.parse(fs.readFileSync(RESUMEN, 'utf8'));
  } catch {
    data = {};
  }
  const d = (data[hoy()] = data[hoy()] || {
    evaluadas: 0,
    asociadas: 0,
    sin_candidato: 0,
    ambiguas: 0,
    fallidas: 0,
  });
  for (const k of Object.keys(d)) d[k] += stats[k] || 0;
  fs.writeFileSync(RESUMEN, JSON.stringify(data, null, 2), 'utf8');
}

// Reporte legible para pegarle a Martín o a Agustín.
function imprimirResumen() {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(RESUMEN, 'utf8'));
  } catch {
    console.log('Todavía no hay mediciones (data/reporte.json no existe).');
    return;
  }
  const dias = Object.keys(data).sort();
  const tot = { evaluadas: 0, asociadas: 0, sin_candidato: 0, ambiguas: 0, fallidas: 0 };

  console.log('fecha        ventas  asociadas  sin contacto  ambiguas   tasa');
  for (const dia of dias) {
    const d = data[dia];
    for (const k of Object.keys(tot)) tot[k] += d[k] || 0;
    const tasa = d.evaluadas ? Math.round((d.asociadas / d.evaluadas) * 100) : 0;
    console.log(
      `${dia}   ${String(d.evaluadas).padStart(5)}  ${String(d.asociadas).padStart(9)}  ` +
        `${String(d.sin_candidato).padStart(12)}  ${String(d.ambiguas).padStart(8)}  ${String(tasa).padStart(4)}%`
    );
  }
  const tasa = tot.evaluadas ? Math.round((tot.asociadas / tot.evaluadas) * 100) : 0;
  console.log('-'.repeat(60));
  console.log(
    `TOTAL        ${String(tot.evaluadas).padStart(5)}  ${String(tot.asociadas).padStart(9)}  ` +
      `${String(tot.sin_candidato).padStart(12)}  ${String(tot.ambiguas).padStart(8)}  ${String(tasa).padStart(4)}%`
  );
  console.log();
  console.log('Cómo leerlo:');
  console.log('  tasa alta (>60%)  -> el proceso funciona, se puede poner DRY_RUN=false.');
  console.log('  muchas "sin contacto" -> no están pasando el iPad, o lo pasan tarde');
  console.log('                           (probar subir MATCH_VENTANA_MIN).');
  console.log('  muchas "ambiguas" -> dos clientes seguidos; achicar la ventana.');
}

module.exports = { registrar, acumular, imprimirResumen };
