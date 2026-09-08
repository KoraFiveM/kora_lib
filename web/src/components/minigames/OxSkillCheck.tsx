import { useCallback, useEffect, useRef, useState } from "react"

import type { OxSkillCheckDifficulty, OxSkillCheckPayload } from "@/lib/types"
import { useNuiRequest } from "@/lib/useNuiRequest"

const OFFSETS = { easy: 50, medium: 40, hard: 25 } as const
const MULTIPLIERS = { easy: 1, medium: 1.5, hard: 1.75 } as const
const CIRCUMFERENCE = 2 * Math.PI * 50

function stageValues(difficulty: OxSkillCheckDifficulty) {
    return typeof difficulty === "string"
        ? { offset: OFFSETS[difficulty], multiplier: MULTIPLIERS[difficulty] }
        : { offset: difficulty.areaSize, multiplier: difficulty.speedMultiplier }
}

function randomAngle(offset: number) {
    return -90 + Math.floor(Math.random() * Math.max(1, 240 - offset)) + 120
}

function keyboardKey(event: KeyboardEvent) {
    if (event.key.charCodeAt(0) < 880) return event.key.toLowerCase()
    if (event.code.startsWith("Key") && event.code.length === 4) return event.code.charAt(3).toLowerCase()
    if (event.code.startsWith("Digit") && event.code.length === 6) return event.code.charAt(5)
    return event.key.toLowerCase()
}

export function OxSkillCheck() {
    const [stageIndex, setStageIndex] = useState(0)
    const [key, setKey] = useState("e")
    const [angle, setAngle] = useState(0)
    const indicatorRef = useRef<SVGCircleElement>(null)
    const indicatorAngleRef = useRef(-90)

    const { payload, isOpen, respond } = useNuiRequest<OxSkillCheckPayload, boolean>(
        "oxSkillCheck",
        useCallback((data: OxSkillCheckPayload) => {
            const first = Array.isArray(data.difficulty) ? data.difficulty[0] : data.difficulty
            const { offset } = stageValues(first)
            setStageIndex(0)
            setAngle(randomAngle(offset))
            const inputs = data.inputs?.filter((input) => typeof input === "string" && input.length > 0)
            setKey(inputs?.[Math.floor(Math.random() * inputs.length)]?.toLowerCase() ?? "e")
        }, []),
    )

    const stages = payload ? (Array.isArray(payload.difficulty) ? payload.difficulty : [payload.difficulty]) : []
    const stage = stages[stageIndex]
    const values = stage ? stageValues(stage) : { offset: 50, multiplier: 1 }

    const advance = useCallback((success: boolean) => {
        if (!success || stageIndex >= stages.length - 1) {
            respond(success)
            return
        }
        const nextIndex = stageIndex + 1
        const nextValues = stageValues(stages[nextIndex])
        const inputs = payload?.inputs?.filter((input) => typeof input === "string" && input.length > 0)
        setStageIndex(nextIndex)
        setAngle(randomAngle(nextValues.offset))
        setKey(inputs?.[Math.floor(Math.random() * inputs.length)]?.toLowerCase() ?? "e")
    }, [payload?.inputs, respond, stageIndex, stages])

    useEffect(() => {
        if (!isOpen || !stage) return
        let frame = 0
        let start: number | undefined
        let complete = false
        const duration = 2000 / Math.max(values.multiplier, 0.0001)

        const tick = (now: number) => {
            if (start === undefined) start = now
            const progress = Math.min((now - start) / duration, 1)
            const current = -90 + progress * 360
            indicatorAngleRef.current = current
            indicatorRef.current?.setAttribute("transform", `rotate(${current} 50 50)`)
            if (progress >= 1) {
                complete = true
                advance(false)
                return
            }
            frame = requestAnimationFrame(tick)
        }

        const onKeyDown = (event: KeyboardEvent) => {
            if (event.repeat || complete) return
            const pressed = keyboardKey(event)
            const allowed = payload?.inputs?.map((input) => input.toLowerCase())
            if (allowed && !allowed.includes(pressed)) return
            complete = true
            event.preventDefault()
            cancelAnimationFrame(frame)
            advance(pressed === key && indicatorAngleRef.current >= angle && indicatorAngleRef.current <= angle + values.offset)
        }

        window.addEventListener("keydown", onKeyDown)
        frame = requestAnimationFrame(tick)
        return () => {
            complete = true
            cancelAnimationFrame(frame)
            window.removeEventListener("keydown", onKeyDown)
        }
    }, [advance, angle, isOpen, key, payload?.inputs, stage, values.multiplier, values.offset])

    if (!isOpen || !payload || !stage) return null
    const areaLength = Math.PI * 50 * values.offset / 180

    return <div className="pointer-events-none fixed inset-0 z-overlay" aria-label="Skill check">
        <svg className="absolute left-1/2 top-1/2 h-[min(50vh,500px)] w-[min(50vh,500px)] -translate-x-1/2 -translate-y-1/2" viewBox="0 0 100 100">
            <circle cx="50" cy="50" r="50" fill="transparent" stroke="hsl(var(--muted))" strokeWidth="4" />
            <circle cx="50" cy="50" r="50" fill="transparent" stroke="hsl(var(--primary))" strokeWidth="4" strokeDasharray={`${areaLength} ${CIRCUMFERENCE - areaLength}`} transform={`rotate(${angle} 50 50)`} />
            <circle ref={indicatorRef} cx="50" cy="50" r="50" fill="transparent" stroke="hsl(var(--destructive))" strokeWidth="7" strokeDasharray={`2 ${CIRCUMFERENCE - 2}`} transform="rotate(-90 50 50)" />
        </svg>
        <div className="absolute left-1/2 top-1/2 flex h-8 w-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-md bg-muted text-sm font-semibold uppercase text-foreground shadow-floating">{key}</div>
    </div>
}
