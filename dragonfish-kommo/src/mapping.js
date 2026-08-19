'use strict';

// Traduce una venta normalizada de Dragonfish a la forma que espera Kommo:
// el objeto de contacto (para crear/actualizar) y el texto de la nota.

const { config } = require('./config');

// Normaliza un teléfono AR a solo dígitos para mejorar el match en Kommo.
function normPhone(v) {
  return v ? String(v).replace(/\D/g, '') : '';
}

// Construye custom_fields_values de Kommo solo con los campos configurados.
function customFields({ documento, telefono, email }) {
  const cf = [];
  if (config.kommo.fieldIdDni && documento) {
    cf.push({ field_id: Number(config.kommo.fieldIdDni), values: [{ value: String(documento) }] });
  }
  if (config.kommo.fieldIdTelefono && telefono) {
    cf.push({
      field_id: Number(config.kommo.fieldIdTelefono),
      values: [{ value: String(telefono) }],
    });
  }
  if (config.kommo.fieldIdEmail && email) {
    cf.push({ field_id: Number(config.kommo.fieldIdEmail), values: [{ value: String(email) }] });
  }
  return cf;
}

// Datos de cliente: preferimos los del comprobante y completamos con la ficha.
function mergeCliente(venta, ficha) {
  return {
    nombre: venta.cliente.nombre || ficha?.nombre || 'Cliente sin nombre',
    documento: venta.cliente.documento || ficha?.documento || null,
    telefono: venta.cliente.telefono || ficha?.telefono || null,
    email: venta.cliente.email || ficha?.email || null,
  };
}

function toKommoContact(cli) {
  const contact = { name: cli.nombre };
  const cf = customFields(cli);
  if (cf.length) contact.custom_fields_values = cf;
  return contact;
}

function toIdentifiers(cli) {
  return {
    dni: cli.documento ? String(cli.documento) : null,
    telefono: cli.telefono ? normPhone(cli.telefono) : null,
    email: cli.email || null,
  };
}

function toNoteText(venta, cli) {
  const money =
    venta.total != null
      ? new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(
          Number(venta.total)
        )
      : 's/d';
  return [
    `🛒 Venta registrada en Dragonfish`,
    `Comprobante: ${venta.tipo} ${venta.numero ?? 'S/N'}`,
    `Fecha: ${venta.fecha ?? 's/d'}`,
    `Total: ${money}`,
    cli.documento ? `Doc: ${cli.documento}` : null,
  ]
    .filter(Boolean)
    .join('\n');
}

module.exports = { mergeCliente, toKommoContact, toIdentifiers, toNoteText, normPhone };
