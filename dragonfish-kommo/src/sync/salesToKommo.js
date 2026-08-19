'use strict';

// Apareo Venta (Dragonfish) -> Contacto (Kommo), por ventana de tiempo.
//
// POR QUÉ ASÍ: las ventas de Dragonfish no guardan teléfono ni identifican al
// comprador (633 de 703 van a "consumidor final"). El único dato de contacto lo
// junta el iPad del local, con un formulario de Kommo que el vendedor pasa
// DESPUÉS de cobrar. La única llave posible entre los dos sistemas es el
// momento: la venta primero, el contacto uno a diez minutos después.
// Ver README > "PROYECTO FRENADO" para los números que respaldan esto.
//
// REGLA DE ORO: si hay más de un candidato, NO se adivina. Meterle a alguien la
// compra de otro en su ficha es peor que no meterle nada, sobre todo si después
// se usa para mandarle mensajes.

const log = require('../logger');
const { config } = require('../config');
const { Cursor } = require('../cursor');
const { DragonfishSqlClient } = require('../dragonfish/sqlClient');
const { KommoClient } = require('../kommo/client');
const { toNoteText } = require('../mapping');
const reporte = require('../reporte');

const MIN = 60 * 1000;

async function runOnce() {
  const cursor = new Cursor();
  const df = new DragonfishSqlClient();
  const kommo = new KommoClient();
  const stats = { evaluadas: 0, asociadas: 0, sin_candidato: 0, ambiguas: 0, fallidas: 0 };

  try {
    const desde = cursor.lastFecha ? new Date(cursor.lastFecha) : null;
    const ventas = await df.getVentasDesde(desde);
    const nuevas = ventas.filter((v) => v.id && !cursor.seen(v.id));
    log.info(`Dragonfish: ${ventas.length} ventas leídas, ${nuevas.length} nuevas.`);

    const ahora = Date.now();
    for (const venta of nuevas) {
      // Todavía puede estar cargándose el contacto: la dejamos para la próxima
      // pasada SIN avanzar el cursor.
      if (ahora - venta.ts.getTime() < config.match.esperaMin * MIN) {
        log.debug(`Venta ${venta.comprobante}: muy reciente, se evalúa más tarde.`);
        continue;
      }

      stats.evaluadas++;
      try {
        const candidatos = await kommo.findContactsCreatedBetween(
          venta.ts,
          new Date(venta.ts.getTime() + config.match.ventanaMin * MIN),
          config.match.ipadUserId
        );

        if (candidatos.length === 0) {
          stats.sin_candidato++;
          log.debug(`Venta ${venta.comprobante}: sin contacto en la ventana.`);
          reporte.registrar('sin_candidato', venta, null);
        } else if (candidatos.length > 1) {
          stats.ambiguas++;
          log.warn(
            `Venta ${venta.comprobante}: ${candidatos.length} contactos en la ventana -> ` +
              `queda SIN asociar (ids: ${candidatos.map((c) => c.id).join(', ')}).`
          );
          reporte.registrar('ambigua', venta, candidatos);
        } else {
          const c = candidatos[0];
          const minutos = Math.round((c.created_at * 1000 - venta.ts.getTime()) / MIN);
          const nota = toNoteText(venta, { minutos });

          if (config.dryRun) {
            log.info(`[DRY_RUN] ${venta.comprobante} -> contacto ${c.id} (+${minutos} min)`);
          } else {
            await kommo.addNote('contacts', c.id, nota);
            log.info(`${venta.comprobante} -> nota en contacto ${c.id} (+${minutos} min)`);
          }
          stats.asociadas++;
          reporte.registrar('asociada', venta, candidatos, { minutos });
        }

        // Asociada o no, la venta queda procesada: si no apareció el contacto en
        // la ventana, no va a aparecer más tarde.
        cursor.markProcessed(venta.id, venta.ts.toISOString());
      } catch (err) {
        // Sin avanzar el cursor: se reintenta en la próxima pasada.
        stats.fallidas++;
        log.error(`Falló la venta ${venta.comprobante}: ${err.message}`);
      }
    }
  } finally {
    await df.close();
  }

  const tasa = stats.evaluadas ? Math.round((stats.asociadas / stats.evaluadas) * 100) : 0;
  log.info(
    `Sync: ${stats.asociadas} asociadas, ${stats.sin_candidato} sin candidato, ` +
      `${stats.ambiguas} ambiguas, ${stats.fallidas} con error (tasa ${tasa}%)` +
      (config.dryRun ? ' [DRY_RUN: no se escribió en Kommo]' : '')
  );
  reporte.acumular(stats);
  return stats;
}

module.exports = { runOnce };
