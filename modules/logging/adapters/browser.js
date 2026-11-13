/* Shared NUI adapter. Explicit calls only; never monkey-patches console. */
(() => {
    'use strict';
    if (globalThis.KoraLogger) return;
    const levels = { trace: 1, debug: 5, info: 9, warn: 13, error: 17, fatal: 21 };
    let state = { enabled: false, level: 'info', localLevel: 'info' };
    let tokens = 40, last = Date.now(), pending = 0, stateVersion = 0;
    function text(value) {
        if (typeof value !== 'string') return `[${typeof value}]`;
        let clean = value.slice(0, 1024).replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
        while (/\^\d/.test(clean)) clean = clean.replace(/\^\d/g, '');
        return clean.replace(/\r/g, '\\r').replace(/\n/g, '\\n').replace(/[\x00-\x1f\x7f]/g, '');
    }
    function fields(value) {
        let remaining = 128;
        const seen = new WeakSet();
        function copy(item, depth = 0) {
            if (--remaining < 0) return '[truncated]';
            if (typeof item === 'string') return text(item);
            if (typeof item === 'number') return Number.isFinite(item) ? item : '[non-finite]';
            if (item == null || typeof item === 'boolean') return item;
            if (typeof item !== 'object') return `[${typeof item}]`;
            if (depth >= 4 || seen.has(item)) return '[depth/cycle]';
            seen.add(item);
            const out = Array.isArray(item) ? [] : Object.create(null);
            let count = 0;
            for (const key in item) {
                if (!Object.hasOwn(item, key)) continue;
                if (++count > 32 || remaining < 0) break;
                const name = text(key).slice(0, 64);
                const sensitive = /password|secret|token|credential|authorization|webhook|connectionstring|apikey|^(license|ip|identifiers|params|parameters|playerdata|payload)$/i
                    .test(key.replace(/[^a-z0-9]/gi, ''));
                // Do not execute getters while logging arbitrary objects.
                const descriptor = Object.getOwnPropertyDescriptor(item, key);
                out[name] = sensitive ? '[redacted]' : descriptor && 'value' in descriptor ? copy(descriptor.value, depth + 1) : '[accessor]';
            }
            seen.delete(item);
            return out;
        }
        return copy(value || {});
    }
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    const post = data => fetch(`https://${resource}/kora_logging`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
    });
    const logger = { isEnabled(level) {
        return levels[level] >= (levels[state.localLevel] || 9)
            || (state.enabled && levels[level] >= (levels[state.level] || 9));
    } };
    for (const level of Object.keys(levels)) {
        logger[level] = (event, message, attributes) => {
            if (!logger.isEnabled(level)) return false;
            try {
                const record = { level, event: text(event).slice(0, 128), message: text(message), fields: fields(attributes) };
                if (levels[level] >= (levels[state.localLevel] || 9)) {
                    const method = level === 'fatal' ? 'error' : level === 'trace' ? 'debug' : level;
                    console[method](`[Kora/${resource || 'preview'}/nui] ${record.event}: ${record.message}`, record.fields);
                }
                if (!resource || !state.enabled || levels[level] < (levels[state.level] || 9)) return true;
                const now = Date.now();
                tokens = Math.min(40, tokens + Math.max(0, now - last) * .02); last = now;
                if (tokens < 1 || pending >= 4) return false;
                tokens--; pending++;
                if (new TextEncoder().encode(JSON.stringify(record)).length > 4096) record.fields = { truncated: true };
                post(record).catch(() => {}).finally(() => { pending--; });
                return true;
            } catch { return false; }
        };
    }
    globalThis.KoraLogger = Object.freeze(logger);
    addEventListener('message', event => {
        if (event.data?.action === 'kora_logging:state' && event.data.data) { stateVersion++; state = event.data.data; }
    });
    // One page-ready handshake, no polling or disabled forwarding work.
    if (resource) post({ action: 'ready' }).then(response => response.json()).then(value => { if (stateVersion === 0) state = value; }).catch(() => {});
})();
