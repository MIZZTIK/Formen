'use strict';

// Traduce una venta de Dragonfish al texto de la nota que se pega en el
// contacto de Kommo.
//
// ⚠️ SIN EMOJIS. La base de Kommo es MySQL utf8 de 3 bytes: cualquier emoji
// trunca el campo en ese punto y la nota llega cortada a la mitad. Es el
// gotcha número uno de este cliente.

const MONEDA = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  maximumFractionDigits: 0,
});

// Normaliza un teléfono AR a solo dígitos.
function normPhone(v) {
  return v ? String(v).replace(/\D/g, '') : '';
}

function fmtFecha(d) {
  if (!d) return 's/d';
  const dt = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(dt.getTime())) return String(d);
  return dt.toLocaleString('es-AR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

// Nota que ve el vendedor en la ficha del contacto.
function toNoteText(venta, { minutos } = {}) {
  const total = venta.total != null ? MONEDA.format(venta.total) : 's/d';
  const lineas = [
    'Compra en el local',
    `Comprobante: ${venta.comprobante}`,
    `Fecha: ${fmtFecha(venta.ts)}`,
    `Total: ${total}`,
  ];
  if (minutos != null) {
    lineas.push(
      `(asociado automaticamente: el contacto se cargo ${minutos} min despues de la venta)`
    );
  }
  return quitarEmojis(lineas.join('\n'));
}

// Red de seguridad: saca todo lo que esté fuera del plano básico (4 bytes en
// utf8), que es lo que Kommo no aguanta.
function quitarEmojis(s) {
  return String(s).replace(/[\u{10000}-\u{10FFFF}]/gu, '');
}

module.exports = { toNoteText, normPhone, quitarEmojis, fmtFecha };
