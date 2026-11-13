const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '../modules/logging/adapters');

function browser(overrides = {}) {
    const calls = [], output = [], handlers = {};
    const context = {
        GetParentResourceName: () => 'kora_hud',
        fetch: async (url, options) => { calls.push({ url, data: JSON.parse(options.body) }); return { json: async () => ({ enabled: false }) }; },
        console: Object.fromEntries(['debug', 'info', 'warn', 'error'].map(level => [level, (...args) => output.push(args)])),
        addEventListener: (name, fn) => { handlers[name] = fn; },
        TextEncoder, Date, ...overrides,
    };
    vm.runInNewContext(fs.readFileSync(path.join(root, 'browser.js'), 'utf8'), context);
    return { context, calls, output, state: value => handlers.message({ data: { action: 'kora_logging:state', data: value } }) };
}

test('server adapter resolves the export on each call, preserving structured fields', () => {
    const calls = [];
    const context = { exports: { kora_lib: { logging_warn: (...args) => { calls.push(args); return true; }, logging_isEnabled: () => true } } };
    vm.runInNewContext(fs.readFileSync(path.join(root, 'server.js'), 'utf8'), context);
    assert.equal(context.KoraLogger.warn('test.event', 'message', { count: 2 }), true);
    assert.deepEqual(calls[0], ['test.event', 'message', { count: 2 }]);
    context.exports.kora_lib = { logging_warn: () => false };
    assert.equal(context.KoraLogger.warn('test.event', 'message'), false);
});

test('server bootstrap fallback is bounded and cannot reveal supplied secrets', () => {
    const output = [];
    const context = { exports: {}, GetResourceState: () => 'stopped', console: { warn: value => output.push(value) } };
    vm.runInNewContext(fs.readFileSync(path.join(root, 'server.js'), 'utf8'), context);
    for (let i = 0; i < 10; i++) context.KoraLogger.error('secret', 'secret', { password: 'secret' });
    assert.equal(output.length, 3);
    assert.ok(!output.join('').includes('secret'));
    assert.equal(context.KoraLogger.isEnabled('debug'), false);
});

test('disabled browser forwarding performs only one ready handshake; no console interception', async () => {
    const f = browser();
    await new Promise(resolve => setImmediate(resolve));
    for (let i = 0; i < 10; i++) f.context.KoraLogger.info('test', 'local');
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].data.action, 'ready');
    assert.equal(f.output.length, 10);
});

test('browser capture is filtered, redacted, bounded and sends no credential fields', async () => {
    const f = browser();
    await new Promise(resolve => setImmediate(resolve));
    f.state({ enabled: true, level: 'debug', localLevel: 'warn' });
    const fields = { password: 'secret', nested: { api_key: 'secret', value: 1 } }; fields.cycle = fields;
    let reads = 0;
    Object.defineProperty(fields, 'getter', { enumerable: true, get: () => { reads++; return 'secret'; } });
    assert.equal(f.context.KoraLogger.trace('test', 'filtered'), false);
    assert.equal(f.context.KoraLogger.debug('test', '^1line\nnext', fields), true);
    assert.equal(f.calls.length, 2);
    assert.equal(f.calls[1].data.message, 'line\\nnext');
    assert.ok(!JSON.stringify(f.calls[1]).includes('secret'));
    assert.equal(reads, 0);
    f.state({ enabled: false, localLevel: 'info' });
    f.context.KoraLogger.warn('test', 'local');
    assert.equal(f.calls.length, 2);
});

test('a dead browser callback cannot create an unbounded request backlog', async () => {
    const f = browser({ fetch: () => new Promise(() => {}) });
    f.state({ enabled: true, level: 'debug', localLevel: 'error' });
    let accepted = 0;
    for (let i = 0; i < 100; i++) if (f.context.KoraLogger.debug('test', 'record')) accepted++;
    assert.equal(accepted, 4);
});


test('late ready response cannot overwrite a newer capture state', async () => {
    let resolveReady;
    const f = browser({ fetch: () => new Promise(resolve => { resolveReady = resolve; }) });
    f.state({ enabled: true, level: 'debug', localLevel: 'warn' });
    resolveReady({ json: async () => ({ enabled: false, localLevel: 'warn' }) });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.context.KoraLogger.isEnabled('debug'), true);
});
