'use strict';

// Orquestación del flujo Ventas(Dragonfish) -> Kommo:
//   1. Traer comprobantes de venta desde el cursor.
//   2. Por cada uno nuevo: resolver datos del cliente.
//   3. Buscar el contacto en Kommo (dni/tel/email) -> crear o actualizar.
//   4. Agregar una nota con el detalle de la venta.
//   5. Avanzar el cursor.

const log = require('../logger');
const { config } = require('../config');
const { Cursor } = require('../cursor');
const { DragonfishClient } = require('../dragonfish/client');
const { KommoClient } = require('../kommo/client');
const {
  mergeCliente,
  toKommoContact,
  toIdentifiers,
  toNoteText,
} = require('../mapping');

async function runOnce() {
  const cursor = new Cursor();
  const df = new DragonfishClient();
  const kommo = new KommoClient();

  const ventas = await df.getVentasDesde({
    desde: cursor.lastFecha,
    tipos: config.dragonfish.tiposVenta,
  });

  const nuevas = ventas.filter((v) => !cursor.seen(v.id));
  log.info(`Dragonfish: ${ventas.length} comprobantes traídos, ${nuevas.length} nuevos.`);

  let ok = 0;
  for (const venta of nuevas) {
    try {
      // Completar datos del cliente si el comprobante solo trae el código.
      let ficha = null;
      if (!venta.cliente.documento && !venta.cliente.telefono && venta.codigoCliente) {
        ficha = await df.getCliente(venta.codigoCliente);
      }
      const cli = mergeCliente(venta, ficha);
      const ids = toIdentifiers(cli);
      const noteText = toNoteText(venta, cli);

      if (config.dryRun) {
        log.info(`[DRY_RUN] Venta ${venta.id} -> contacto "${cli.nombre}" (${ids.telefono || ids.email || ids.dni || 's/id'})`);
        log.debug(`[DRY_RUN] Nota:\n${noteText}`);
        cursor.markProcessed(venta.id, venta.fecha);
        ok++;
        continue;
      }

      let contact = await kommo.findContactByAny(ids);
      if (contact) {
        await kommo.updateContact(contact.id, toKommoContact(cli));
        log.info(`Kommo: contacto ${contact.id} actualizado (venta ${venta.id}).`);
      } else {
        contact = await kommo.createContact(toKommoContact(cli));
        log.info(`Kommo: contacto ${contact.id} creado (venta ${venta.id}).`);
      }

      await kommo.addNote('contacts', contact.id, noteText);
      cursor.markProcessed(venta.id, venta.fecha);
      ok++;
    } catch (err) {
      // No avanzamos el cursor: se reintenta en la próxima pasada.
      log.error(`Falló la venta ${venta.id}: ${err.message}`);
    }
  }

  log.info(`Sync terminado: ${ok}/${nuevas.length} ventas procesadas.`);
  return { total: ventas.length, nuevas: nuevas.length, ok };
}

module.exports = { runOnce };
