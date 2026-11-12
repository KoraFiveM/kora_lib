import { act, render, waitFor } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { ScreenshotCapture } from "@/components/screenshot/ScreenshotCapture"
import { respondToNui } from "@/lib/fetchNui"

const graphics = vi.hoisted(() => ({
    owned: [] as any[], renderers: [] as any[], targets: [] as any[],
    importGate: undefined as Promise<void> | undefined, importStarted: false,
}))
vi.mock("@/lib/fetchNui", () => ({ respondToNui: vi.fn() }))
vi.mock("@citizenfx/three", async () => {
    graphics.importStarted = true
    if (graphics.importGate) await graphics.importGate
    const owned = (kind: string) => {
        const item = { kind, disposed: false, dispose: vi.fn(() => {
            if (item.disposed) throw new Error("Graphics resource released twice")
            item.disposed = true
        }) }
        graphics.owned.push(item)
        return item
    }
    return {
        OrthographicCamera: function () { return { position: { z: 0 } } },
        Scene: function () { return { add: vi.fn() } },
        CfxTexture: function () { return owned("texture") },
        ShaderMaterial: function () { return owned("material") },
        PlaneBufferGeometry: function () { return owned("geometry") },
        Mesh: function () { return { position: { z: 0 } } },
        WebGLRenderTarget: function (width: number, height: number) {
            const item = Object.assign(owned("target"), { width, height })
            graphics.targets.push(item)
            return item
        },
        WebGLRenderer: function () {
            const item: any = owned("renderer")
            Object.assign(item, { domElement: document.createElement("canvas"),
                setPixelRatio: vi.fn(), setSize: vi.fn(), clear: vi.fn(),
                render: vi.fn((_scene, _camera, target) => {
                    if (item.disposed || target.disposed) throw new Error("Rendered a released resource")
                }),
                readRenderTargetPixels: vi.fn((target, x, y, width, height, pixels) => {
                    if (item.disposed || target.disposed) throw new Error("Read a released resource")
                    expect([x, y, width, height]).toEqual([0, 0, target.width, target.height])
                    pixels.fill(7)
                }),
            })
            graphics.renderers.push(item)
            return item
        },
        LinearFilter: "linear", NearestFilter: "nearest", RGBAFormat: "rgba", UnsignedByteType: "byte",
    }
})

let nextFrame = 0
const frames = new Map<number, FrameRequestCallback>()
const encodings: { callback: BlobCallback; mime: string; quality: number | undefined; width: number; height: number }[] = []

beforeEach(() => {
    graphics.owned.length = 0; graphics.renderers.length = 0; graphics.targets.length = 0
    graphics.importGate = undefined; graphics.importStarted = false
    frames.clear(); encodings.length = 0; nextFrame = 0
    vi.mocked(respondToNui).mockClear()
    vi.stubGlobal("requestAnimationFrame", vi.fn((callback: FrameRequestCallback) => { frames.set(++nextFrame, callback); return nextFrame }))
    vi.stubGlobal("cancelAnimationFrame", vi.fn((id: number) => frames.delete(id)))
    vi.stubGlobal("ImageData", function (data: Uint8ClampedArray, width: number, height: number) { return { data, width, height } })
    vi.stubGlobal("FileReader", function () {
        const reader = { result: "", onload: null as (() => void) | null, onerror: null as (() => void) | null,
            readAsDataURL(blob: Blob) { reader.result = `data:${blob.type};base64,AQID`; queueMicrotask(() => reader.onload?.()) },
        }
        return reader
    })
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(() => ({ putImageData: vi.fn() }) as any)
    vi.spyOn(HTMLCanvasElement.prototype, "toBlob").mockImplementation(function (this: HTMLCanvasElement, callback, mime, quality) {
        encodings.push({ callback, mime: mime || "", quality, width: this.width, height: this.height })
    })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, text: async () => "stored" })))
    vi.stubGlobal("innerWidth", 8); vi.stubGlobal("innerHeight", 4)
})
afterEach(() => {
    for (const renderer of graphics.renderers) renderer.domElement.remove()
    vi.restoreAllMocks(); vi.unstubAllGlobals()
})

const send = (id: number, payload: Record<string, unknown> = {}, action = "screenshot:capture") => {
    act(() => window.dispatchEvent(new MessageEvent("message", { data: { action, data: { requestId: id, token: `token-${id}`, payload } } })))
}
const flush = async () => { await act(async () => { for (let index = 0; index < 12; index++) await Promise.resolve() }) }
const frame = async () => {
    const callbacks = [...frames.values()]; frames.clear()
    await act(async () => { for (const callback of callbacks) callback(0) })
}
const warm = async () => { await frame(); await frame() }
const encode = async (ok = true) => {
    const item = encodings.shift()
    expect(item).toBeDefined()
    await act(async () => item!.callback(ok ? new Blob(["pixels"], { type: item!.mime }) : null))
    await flush()
    return item!
}
const released = () => {
    expect(graphics.owned).toHaveLength(graphics.renderers.length * 5)
    for (const item of graphics.owned) expect(item.dispose).toHaveBeenCalledOnce()
    expect(document.querySelectorAll("canvas")).toHaveLength(0)
}

describe("ScreenshotCapture active queue lifecycle", () => {
    it("releases late-created graphics after unmount and retires queued captures", async () => {
        let release!: () => void
        graphics.importGate = new Promise<void>((resolve) => { release = resolve })
        const { unmount } = render(<ScreenshotCapture />)
        send(1); send(2)
        await waitFor(() => expect(graphics.importStarted).toBe(true))
        unmount()
        await act(async () => release())
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        released()
        await waitFor(() => expect(respondToNui).toHaveBeenCalledTimes(2))
        expect(vi.mocked(respondToNui).mock.calls.map(([id, token, ok]) => [id, token, ok])).toEqual([[1, "token-1", false], [2, "token-2", false]])
        expect(graphics.renderers[0].render).not.toHaveBeenCalled()
        expect(frames.size).toBe(0)
    })

    it("does no idle rendering and releases successful captures after encoding", async () => {
        render(<ScreenshotCapture />)
        expect(frames.size).toBe(0)
        send(3, { encoding: "png", quality: 0, maxWidth: 4, maxHeight: 2 })
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        await warm()
        expect(graphics.renderers[0].render.mock.calls.length).toBeGreaterThanOrEqual(2)
        expect(graphics.renderers[0].setPixelRatio).toHaveBeenCalledWith(1)
        expect(graphics.renderers[0].setSize).toHaveBeenCalledWith(4, 2, false)
        expect(encodings[0]).toMatchObject({ mime: "image/png", quality: 0, width: 4, height: 2 })
        const before = graphics.renderers[0].render.mock.calls.length
        await frame()
        expect(graphics.renderers[0].render.mock.calls.length).toBeGreaterThan(before)
        await encode()
        expect(respondToNui).toHaveBeenCalledWith(3, "token-3", true, { data: "data:image/png;base64,AQID" })
        released()
        expect(frames.size).toBe(0)
        const finished = graphics.renderers[0].render.mock.calls.length
        await frame()
        expect(graphics.renderers[0].render).toHaveBeenCalledTimes(finished)
    })

    it("reuses graphics across queued captures and requests arriving during encoding", async () => {
        render(<ScreenshotCapture />)
        send(4); send(5)
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        await warm(); await encode()
        expect(graphics.owned[0].dispose).not.toHaveBeenCalled()
        await warm()
        send(6)
        await encode()
        expect(graphics.renderers).toHaveLength(1)
        expect(graphics.owned[0].dispose).not.toHaveBeenCalled()
        await warm(); await encode()
        expect(vi.mocked(respondToNui).mock.calls.map(([id]) => id)).toEqual([4, 5, 6])
        released()
        expect(frames.size).toBe(0)
    })

    it("keeps failures from poisoning the queue and frees resources after the retry", async () => {
        render(<ScreenshotCapture />)
        send(7); send(8)
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        await warm(); await encode(false)
        expect(respondToNui).toHaveBeenCalledWith(7, "token-7", false, expect.stringContaining("could not encode"))
        expect(graphics.owned[0].dispose).not.toHaveBeenCalled()
        await warm(); await encode()
        expect(respondToNui).toHaveBeenCalledWith(8, "token-8", true, { data: "data:image/jpeg;base64,AQID" })
        released(); expect(frames.size).toBe(0)
        send(9); await flush(); await warm(); await encode()
        expect(graphics.renderers).toHaveLength(2)
        released(); expect(frames.size).toBe(0)
    })

    it("replaces different dimensions without drawing disposed targets", async () => {
        render(<ScreenshotCapture />)
        send(10); send(11, { maxWidth: 4, maxHeight: 2 })
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        await warm(); await encode()
        await waitFor(() => expect(graphics.renderers).toHaveLength(2))
        expect(graphics.targets.map(({ width, height }) => [width, height])).toEqual([[8, 4], [4, 2]])
        for (const item of graphics.owned.slice(0, 5)) expect(item.dispose).toHaveBeenCalledOnce()
        await warm(); await encode()
        released(); expect(frames.size).toBe(0)
    })

    it("stops rendering on unmount during warmup and removes its NUI listeners", async () => {
        const { unmount } = render(<ScreenshotCapture />)
        send(12)
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        await frame()
        unmount(); released()
        await frame(); await flush()
        expect(graphics.renderers[0].readRenderTargetPixels).not.toHaveBeenCalled()
        expect(respondToNui).toHaveBeenCalledWith(12, "token-12", false, expect.stringContaining("no longer mounted"))
        expect(frames.size).toBe(0)
        send(13); await flush()
        expect(graphics.renderers).toHaveLength(1)
        expect(respondToNui).toHaveBeenCalledOnce()
    })

    it("preserves raw, multipart and legacy JSON upload bodies and request tokens", async () => {
        render(<ScreenshotCapture />)
        send(14, { url: "https://example.invalid/raw", rawBody: true, encoding: "webp", headers: { Authorization: "fixture" } }, "screenshot:upload")
        send(15, { url: "https://example.invalid/form", field: "image", headers: { "Content-Type": "caller-type", Authorization: "fixture" } }, "screenshot:upload")
        send(16, { url: "https://example.invalid/json", headers: {} }, "screenshot:upload")
        await waitFor(() => expect(graphics.renderers).toHaveLength(1))
        for (let index = 0; index < 3; index++) { await warm(); await encode() }
        const calls = vi.mocked(fetch).mock.calls
        expect(calls).toHaveLength(3)
        expect(calls[0]).toEqual(["https://example.invalid/raw", { method: "POST", mode: "cors", headers: { Authorization: "fixture", "Content-Type": "image/webp" }, body: expect.any(Blob) }])
        expect(calls[1][1]).toMatchObject({ method: "POST", mode: "cors", headers: { Authorization: "fixture" }, body: expect.any(FormData) })
        expect((calls[1][1]!.body as FormData).get("image")).toMatchObject({ name: "screenshot.jpg", type: "image/jpeg" })
        expect(calls[2][1]).toEqual({ method: "POST", mode: "cors", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ data: "data:image/jpeg;base64,AQID" }) })
        expect(vi.mocked(respondToNui).mock.calls).toEqual([[14, "token-14", true, "stored"], [15, "token-15", true, "stored"], [16, "token-16", true, "stored"]])
        released(); expect(frames.size).toBe(0)
    })
})
