// Run against a locally served production build and a headless Chromium with
// --remote-debugging-port=9229. No game, browser library or production data needed.
// This measures browser rendering only, not FiveM/server round-trip latency.
import assert from 'node:assert/strict'

const pages = await (await fetch('http://127.0.0.1:9229/json')).json()
const socket = new WebSocket(pages.find(page => page.type === 'page').webSocketDebuggerUrl)
await new Promise(resolve => socket.addEventListener('open', resolve, { once: true }))
let nextId = 0
const pending = new Map()
socket.addEventListener('message', event => {
    const response = JSON.parse(event.data)
    const callback = pending.get(response.id)
    if (callback) {
        pending.delete(response.id)
        response.error ? callback.reject(response.error) : callback.resolve(response.result)
    }
})
function send(method, params = {}) {
    return new Promise((resolve, reject) => {
        const id = ++nextId
        pending.set(id, { resolve, reject })
        socket.send(JSON.stringify({ id, method, params }))
    })
}
async function evaluate(expression) {
    const response = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    assert(!response.exceptionDetails, JSON.stringify(response.exceptionDetails))
    return response.result.value
}
try {
    await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false })
    await send('Page.navigate', { url: 'http://127.0.0.1:4199/' })
    await new Promise(resolve => setTimeout(resolve, 1000))
    const result = await evaluate(`(async () => {
        const nextPaint = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
        const fields = [{ id: 'rates', label: 'Consumption rates', type: 'key-value', keyMode: 'mixed', requiredKeys: ['default'],
            valueField: { id: 'item', label: 'Value', type: 'number', min: 0, required: true },
            default: Array.from({ length: 500 }, (_, index) => ({ key: index === 0 ? 'default' : String(index), value: '0.035' })) }]
        const app = { id: 'test:config', title: 'Configuration', navigation: Array.from({ length: 60 }, (_, index) => ({
            id: 'resource' + index, label: 'Resource ' + index,
            content: index === 0 ? { title: 'Fuel settings', description: 'A long description explaining consumption rates, their units and the effect of changing them. '.repeat(8), blocks: [{ id: 'rates', type: 'form', fields, action: { id: 'save', label: 'Save setting' } }] }
                : { title: 'Resource ' + index, blocks: [] }
        })) }
        const start = performance.now()
        window.dispatchEvent(new MessageEvent('message', { data: { action: 'openApp', data: { requestId: 1, token: 'browser-test', payload: { app, viewId: 'resource0' } } } }))
        await nextPaint()
        const openMs = performance.now() - start
        const keyInputs = [...document.querySelectorAll('input')].filter(input => input.getAttribute('aria-label')?.endsWith(' key'))
        const next = [...document.querySelectorAll('button')].find(button => button.textContent === 'Next')
        if (!next) throw new Error('Table pagination missing')
        next.click()
        await nextPaint()
        const nextPage = Boolean(document.querySelector('[aria-label="Consumption rates row 51 key"]'))
        const other = [...document.querySelectorAll('button')].find(button => button.textContent.trim() === 'Resource 1')
        if (!other) throw new Error('Resource navigation missing')
        other.click()
        await nextPaint()
        return { openMs, mountedRows: keyInputs.length, requiredReadOnly: keyInputs[0]?.readOnly, nextPage,
            navigated: !document.querySelector('[aria-label="Consumption rates row 51 key"]'),
            viewportOverflow: document.documentElement.scrollWidth > innerWidth }
    })()`)
    assert.equal(result.mountedRows, 50)
    assert.equal(result.requiredReadOnly, true)
    assert.equal(result.nextPage, true)
    assert.equal(result.navigated, true)
    assert.equal(result.viewportOverflow, false)
    console.log(JSON.stringify(result, null, 2))
} finally {
    socket.close()
}
