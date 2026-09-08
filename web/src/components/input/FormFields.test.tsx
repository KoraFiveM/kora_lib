import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { useState } from "react"
import { describe, expect, it } from "vitest"

import { FormFields } from "@/components/input/FormFields"
import type { FieldValue, InputField } from "@/lib/types"

const fields: InputField[] = [{
    id: "vehicle",
    type: "combobox",
    label: "Vehicle",
    options: [
        { value: "adder", label: "Adder", disabled: true },
        { value: "banshee", label: "Banshee" },
        { value: "comet", label: "Comet" },
    ],
}]

function FormHarness() {
    const [values, setValues] = useState<Record<string, FieldValue>>({ vehicle: "" })
    return <FormFields fields={fields} values={values} errors={{}} onChange={setValues} />
}

describe("FormFields combobox", () => {
    it("supports arrow navigation, skips disabled choices, and selects with Enter", async () => {
        const user = userEvent.setup()
        render(<FormHarness />)
        const input = screen.getByRole("combobox", { name: "Vehicle" })

        await user.click(input)
        expect(input).toHaveAttribute("aria-activedescendant", "field-vehicle-listbox-1")

        await user.keyboard("{ArrowDown}{Enter}")

        expect(input).toHaveValue("comet")
        expect(input).toHaveAttribute("aria-expanded", "false")
    })
})
