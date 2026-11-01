import { useCallback, useEffect, useRef } from "react"

import { respondToNui } from "@/lib/fetchNui"
import type { NuiRequestEnvelope } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

type ScreenshotEncoding = "jpg" | "png" | "webp"

interface CapturePayload {
    encoding?: ScreenshotEncoding
    quality?: number
    maxWidth?: number | false
    maxHeight?: number | false
    includeNui?: boolean
}

interface UploadPayload extends CapturePayload {
    url: string
    field?: string
    headers?: Record<string, string>
    rawBody?: boolean
}

interface CaptureResources {
    width: number
    height: number
    renderer: any
    renderTarget: any
    scene: any
    camera: any
    material: any
    geometry: any
    gameTexture: any
}

interface ThreeRuntime {
    OrthographicCamera: any
    Scene: any
    WebGLRenderTarget: any
    LinearFilter: any
    NearestFilter: any
    RGBAFormat: any
    UnsignedByteType: any
    CfxTexture: any
    ShaderMaterial: any
    PlaneBufferGeometry: any
    Mesh: any
    WebGLRenderer: any
}

const MIME_TYPES: Record<ScreenshotEncoding, string> = {
    jpg: "image/jpeg",
    png: "image/png",
    webp: "image/webp",
}

let threeRuntime: Promise<ThreeRuntime> | undefined

function loadThree() {
    // The CfxTexture renderer is sizeable and unused by all normal menus/HUD
    // flows. Vite therefore places it in a separate chunk that downloads only
    // for the first actual screenshot request.
    threeRuntime ??= import("@citizenfx/three") as Promise<ThreeRuntime>
    return threeRuntime
}

function isRequestEnvelope(value: unknown): value is NuiRequestEnvelope<UploadPayload> {
    if (!value || typeof value !== "object") return false
    const candidate = value as Partial<NuiRequestEnvelope<UploadPayload>>
    return typeof candidate.requestId === "number" && typeof candidate.token === "string" && !!candidate.payload
}

function isUploadPayload(value: unknown): value is UploadPayload {
    return !!value && typeof value === "object" && typeof (value as Partial<UploadPayload>).url === "string"
}

function normalizedEncoding(value: unknown): ScreenshotEncoding {
    return value === "png" || value === "webp" || value === "jpg" ? value : "jpg"
}

function normalizedQuality(value: unknown): number {
    return typeof value === "number" && value >= 0 && value <= 1 ? value : 0.92
}

function outputDimensions(payload: CapturePayload): { width: number; height: number } {
    const maxWidth = typeof payload.maxWidth === "number" ? payload.maxWidth : Number.POSITIVE_INFINITY
    const maxHeight = typeof payload.maxHeight === "number" ? payload.maxHeight : Number.POSITIVE_INFINITY
    const scale = Math.min(1, maxWidth / window.innerWidth, maxHeight / window.innerHeight)

    return {
        width: Math.max(1, Math.floor(window.innerWidth * scale)),
        height: Math.max(1, Math.floor(window.innerHeight * scale)),
    }
}

async function createResources(width: number, height: number): Promise<CaptureResources> {
    const three = await loadThree()
    const camera = new three.OrthographicCamera(width / -2, width / 2, height / 2, height / -2, -10000, 10000)
    camera.position.z = 100

    const scene = new three.Scene()
    const gameTexture = new three.CfxTexture()
    gameTexture.needsUpdate = true

    const material = new three.ShaderMaterial({
        uniforms: { tDiffuse: { value: gameTexture } },
        vertexShader: `
            varying vec2 vUv;
            void main() {
                vUv = vec2(uv.x, 1.0 - uv.y);
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }
        `,
        fragmentShader: `
            varying vec2 vUv;
            uniform sampler2D tDiffuse;
            void main() {
                gl_FragColor = texture2D(tDiffuse, vUv);
            }
        `,
    })
    const geometry = new three.PlaneBufferGeometry(width, height)
    const quad = new three.Mesh(geometry, material)
    quad.position.z = -100
    scene.add(quad)

    const renderTarget = new three.WebGLRenderTarget(width, height, {
        minFilter: three.LinearFilter,
        magFilter: three.NearestFilter,
        format: three.RGBAFormat,
        type: three.UnsignedByteType,
    })
    const renderer = new three.WebGLRenderer()
    // The target resolution is explicitly capped above; using DPR here would
    // silently allocate another oversized buffer on high-DPI clients.
    renderer.setPixelRatio(1)
    renderer.setSize(width, height, false)
    renderer.autoClear = false
    renderer.domElement.style.display = "none"
    document.body.appendChild(renderer.domElement)

    return { width, height, renderer, renderTarget, scene, camera, material, geometry, gameTexture }
}

function destroyResources(resources: CaptureResources) {
    resources.renderTarget.dispose()
    resources.geometry.dispose()
    resources.material.dispose()
    resources.gameTexture.dispose()
    resources.renderer.dispose()
    resources.renderer.domElement.remove()
}

function waitForFrame(): Promise<void> {
    return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())))
}

function blobFromCanvas(canvas: HTMLCanvasElement, mime: string, quality: number): Promise<Blob> {
    return new Promise((resolve, reject) => {
        canvas.toBlob((blob) => {
            if (blob) resolve(blob)
            else reject(new Error("The browser could not encode the screenshot."))
        }, mime, quality)
    })
}

function dataUrlFromBlob(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.onerror = () => reject(new Error("The browser could not read the screenshot."))
        reader.onload = () => resolve(String(reader.result))
        reader.readAsDataURL(blob)
    })
}

function isStringRecord(value: unknown): value is Record<string, string> {
    if (!value || typeof value !== "object") return false
    return Object.values(value).every((item) => typeof item === "string")
}

/**
 * A permanently mounted but invisible capture service. Keep CfxTexture
 * rendering while captures are pending, then release the capture resources.
 */
export function ScreenshotCapture() {
    const resourcesRef = useRef<CaptureResources | null>(null)
    const queueRef = useRef<Promise<unknown>>(Promise.resolve())
    const pendingRef = useRef(0)
    const frameRef = useRef<number | null>(null)
    const mountedRef = useRef(true)

    const releaseCapture = useCallback(() => {
        if (frameRef.current !== null) cancelAnimationFrame(frameRef.current)
        frameRef.current = null
        if (resourcesRef.current) destroyResources(resourcesRef.current)
        resourcesRef.current = null
    }, [])

    const capture = useCallback(async (payload: CapturePayload, includeDataUrl = true): Promise<{ blob: Blob; data?: string }> => {
        if (!mountedRef.current) throw new Error("Screenshot capture is no longer mounted.")
        const { width, height } = outputDimensions(payload)
        let resources = resourcesRef.current
        if (!resources || resources.width !== width || resources.height !== height) {
            if (resources) destroyResources(resources)
            resourcesRef.current = null
            resources = await createResources(width, height)
            if (!mountedRef.current) {
                destroyResources(resources)
                throw new Error("Screenshot capture is no longer mounted.")
            }
            resourcesRef.current = resources
        }

        // CfxTexture is fed by the game view. Waiting for two browser frames
        // lets the requested game frame reach the texture without keeping a
        // permanent render loop alive between captures.
        await waitForFrame()
        if (!mountedRef.current) throw new Error("Screenshot capture is no longer mounted.")
        resources.renderer.clear()
        resources.renderer.render(resources.scene, resources.camera, resources.renderTarget, true)

        const pixels = new Uint8Array(width * height * 4)
        resources.renderer.readRenderTargetPixels(resources.renderTarget, 0, 0, width, height, pixels)

        const canvas = document.createElement("canvas")
        canvas.width = width
        canvas.height = height
        const context = canvas.getContext("2d")
        if (!context) throw new Error("The browser has no 2D canvas context.")
        context.putImageData(new ImageData(new Uint8ClampedArray(pixels.buffer), width, height), 0, 0)

        const encoding = normalizedEncoding(payload.encoding)
        const blob = await blobFromCanvas(canvas, MIME_TYPES[encoding], normalizedQuality(payload.quality))
        // Server-initiated uploads and multipart uploads consume the Blob
        // directly. Avoid creating a second base64-sized copy unless the API
        // actually needs the legacy data-URI result.
        return { blob, data: includeDataUrl ? await dataUrlFromBlob(blob) : undefined }
    }, [])

    const enqueue = useCallback(<T,>(task: () => Promise<T>): Promise<T> => {
        pendingRef.current += 1
        if (pendingRef.current === 1) {
            const renderGameView = () => {
                if (!mountedRef.current || pendingRef.current === 0) return
                const resources = resourcesRef.current
                if (resources) {
                    resources.renderer.clear()
                    resources.renderer.render(resources.scene, resources.camera, resources.renderTarget, true)
                }
                frameRef.current = requestAnimationFrame(renderGameView)
            }
            frameRef.current = requestAnimationFrame(renderGameView)
        }
        const run = async () => {
            try {
                return await task()
            } finally {
                pendingRef.current -= 1
                if (pendingRef.current === 0) releaseCapture()
            }
        }
        const next = queueRef.current.then(run, run)
        // A failed capture must not poison the next request in the queue.
        queueRef.current = next.catch(() => undefined)
        return next
    }, [releaseCapture])

    useNuiEvent<NuiRequestEnvelope<CapturePayload>>("screenshot:capture", (message) => {
        void enqueue(() => capture(message.payload))
            .then(({ data }) => respondToNui(message.requestId, message.token, true, { data }))
            .catch((error) => respondToNui(message.requestId, message.token, false, String(error)))
    })

    useNuiEvent<UploadPayload | NuiRequestEnvelope<UploadPayload>>("screenshot:upload", (message) => {
        const envelope = isRequestEnvelope(message) ? message : undefined
        const payload: unknown = envelope ? envelope.payload : message
        if (!isUploadPayload(payload)) return

        void enqueue(() => capture(payload, !payload.rawBody && !payload.field))
            .then(async ({ blob, data }) => {
                const headers = isStringRecord(payload.headers) ? { ...payload.headers } : {}
                let body: BodyInit

                if (payload.rawBody) {
                    headers["Content-Type"] = blob.type
                    body = blob
                } else if (payload.field) {
                    // Let the browser supply multipart's boundary even when a
                    // caller provided unrelated authentication headers.
                    delete headers["Content-Type"]
                    const formData = new FormData()
                    formData.append(payload.field, blob, `screenshot.${normalizedEncoding(payload.encoding)}`)
                    body = formData
                } else {
                    headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
                    body = JSON.stringify({ data })
                }

                const response = await fetch(payload.url, {
                    method: "POST",
                    mode: "cors",
                    headers,
                    body,
                })
                const text = await response.text()
                if (!response.ok) throw new Error(`Screenshot upload failed: ${response.status} ${text}`)
                return text
            })
            .then((text) => {
                if (envelope) respondToNui(envelope.requestId, envelope.token, true, text)
            })
            .catch((error) => {
                if (envelope) respondToNui(envelope.requestId, envelope.token, false, String(error))
                else console.error("[kora_lib] server-requested screenshot upload failed:", error)
            })
    })

    useEffect(() => {
        mountedRef.current = true
        return () => {
            mountedRef.current = false
            releaseCapture()
        }
    }, [releaseCapture])

    return null
}
