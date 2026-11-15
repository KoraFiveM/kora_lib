import { createContext, useContext, type ReactNode } from "react"
import type { MinigameUiLabels } from "@/lib/types"

const defaults: MinigameUiLabels = {
    titleAttempt: "%s — attempt %d of %d", titleLockpick: "Lockpick", titleSkillbar: "Skill check", titleCircuit: "Circuit",
    titleMash: "Mash", titleFishing: "Fishing", titlePinpad: "Pinpad", titleQuiz: "Quiz", titleWordguess: "Word Guess",
    titleWordscramble: "Word Scramble", titleKeys: "Keys", titleHacking: "Hacking",
    lastAttemptFailed: "Last attempt failed — try again.", cancelInstruction: "Press %s to cancel.", submit: "Submit",
    fishingSlipped: "The line slipped — cast again.", keepMarker: "Keep the marker in the bite zone.", gameCount: "Game %d of %d",
    fishingInstruction: "Press %s when the marker is in the highlighted zone. Press %s to cancel.",
    lockpickInstruction: "Press %s when the indicator is inside the highlighted zone. Press %s to cancel.",
    mashInstruction: "Press %s as fast as you can. Press %s to cancel.", keysInstruction: "Press the highlighted arrow key. Press %s to cancel.",
    skillbarInstruction: "Press %s when the indicator is inside the zone. Press %s to cancel.",
    typeLetterInstruction: "Type a letter to guess it. Press %s to cancel.", hintPrefix: "Hint:", guessedPrefix: "Guessed:",
    guessesLeft: "%d guesses left", secondsLeft: "%d s left",
}

const MinigameLocaleContext = createContext<MinigameUiLabels>(defaults)

export function MinigameLocaleProvider({ labels, children }: { labels?: MinigameUiLabels; children: ReactNode }) {
    return <MinigameLocaleContext.Provider value={labels ?? defaults}>{children}</MinigameLocaleContext.Provider>
}

export function useMinigameLabels() {
    return useContext(MinigameLocaleContext)
}

export function formatMinigameLabel(template: string, ...values: Array<string | number>) {
    let index = 0
    return template.replace(/%[sd]/g, () => String(values[index++] ?? ""))
}