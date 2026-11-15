/* Kora Framework: load as a server_script before JavaScript consumers. */
(() => {
    'use strict';
    let fallbackCount = 0;
    const levels = ['trace', 'debug', 'info', 'warn', 'error', 'fatal'];
    const logger = {
        isEnabled(level) {
            try { return globalThis.exports.kora_lib.logging_isEnabled(level); }
            catch { return false; }
        },
    };
    for (const level of levels) {
        logger[level] = (event, message, fields) => {
            try {
                return globalThis.exports.kora_lib[`logging_${level}`](event, message, fields || {});
            } catch {
                // Never print raw fields/errors during bootstrap: they may contain secrets.
                if (typeof GetResourceState === 'function' && GetResourceState('kora_lib') !== 'started'
                    && fallbackCount++ < 3) {
                    console.warn('[Kora/logging] shared logger unavailable; diagnostic dropped');
                }
                return false;
            }
        };
    }
    globalThis.KoraLogger = Object.freeze(logger);
})();
