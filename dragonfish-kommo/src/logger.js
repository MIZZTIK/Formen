'use strict';

const { config } = require('./config');

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = LEVELS[config.logLevel] ?? LEVELS.info;

function ts() {
  // Hora local Argentina para logs legibles en la PC de Formen.
  return new Date().toISOString();
}

function emit(level, args) {
  if (LEVELS[level] < threshold) return;
  const line = `[${ts()}] ${level.toUpperCase().padEnd(5)}`;
  const fn = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log;
  fn(line, ...args);
}

module.exports = {
  debug: (...a) => emit('debug', a),
  info: (...a) => emit('info', a),
  warn: (...a) => emit('warn', a),
  error: (...a) => emit('error', a),
};
