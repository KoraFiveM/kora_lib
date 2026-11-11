import { useEffect, useRef, useState } from "react"

export function useMinigameTimeout(timeLimit: number, onTimeout: () => void) {
    const callbackRef = useRef(onTimeout)
    useEffect(() => { callbackRef.current = onTimeout }, [onTimeout])
    useEffect(() => {
        const timer = window.setTimeout(() => callbackRef.current(), timeLimit)
        return () => window.clearTimeout(timer)
    }, [timeLimit])
}

export function useSecondsLeft(startedAt: number, timeLimit: number) {
    const calculate = () => Math.max(0, Math.ceil((timeLimit - (performance.now() - startedAt)) / 1000))
    const [secondsLeft, setSecondsLeft] = useState(calculate)

    useEffect(() => {
        const timer = window.setInterval(() => setSecondsLeft(calculate()), 250)
        return () => window.clearInterval(timer)
    }, [startedAt, timeLimit])

    return secondsLeft
}
