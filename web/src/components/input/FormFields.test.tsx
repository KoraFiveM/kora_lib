import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { useState } from "react"
import { describe, expect, it } from "vitest"

import { FormFields, createFieldValues, submissionValues, validateFields } from "@/components/input/FormFields"
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

function SearchableHarness() {
    const searchableFields: InputField[] = [
        { id: "shop", type: "select", label: "Shop", searchable: true, options: [{ value: "247", label: "24/7" }, { value: "robs", label: "Rob's Liquor" }] },
        { id: "jobs", type: "multiselect", label: "Jobs", searchable: true, options: [{ value: "ems", label: "Ambulance" }, { value: "police", label: "Police" }] },
    ]
    const [values, setValues] = useState<Record<string, FieldValue>>({ shop: "", jobs: [] })
    return <><FormFields fields={searchableFields} values={values} errors={{}} onChange={setValues} /><output data-testid="values">{JSON.stringify(values)}</output></>
}

describe("FormFields searchable fixed choices", () => {
    it("filters selects without committing arbitrary text", async () => {
        const user = userEvent.setup()
        render(<SearchableHarness />)
        const select = screen.getByRole("combobox", { name: "Shop" })

        await user.click(select)
        await user.type(select, "not a shop")
        expect(screen.getByText("No results")).toBeInTheDocument()
        expect(screen.getByTestId("values")).toHaveTextContent('"shop":""')

        await user.clear(select)
        await user.type(select, "Rob")
        await user.click(screen.getByRole("option", { name: "Rob's Liquor" }))
        expect(screen.getByTestId("values")).toHaveTextContent('"shop":"robs"')
    })

    it("filters multiselect options while retaining fixed option values", async () => {
        const user = userEvent.setup()
        render(<SearchableHarness />)
        await user.type(screen.getByRole("searchbox", { name: "Search Jobs" }), "pol")
        expect(screen.queryByText("Ambulance")).not.toBeInTheDocument()
        await user.click(screen.getByText("Police"))
        expect(screen.getByTestId("values")).toHaveTextContent('"jobs":["police"]')
    })
})

describe("FormFields ox-compatible temporal fields", () => {
    const numericDefault = new Date(2026, 8, 8, 17, 45).getTime()
    const temporalFields: InputField[] = [
        { id: "day", type: "date", label: "Day", default: "2026-09-08", returnString: false },
        { id: "window", type: "date-range", label: "Window", default: ["2026-09-08", "2026-09-10"], returnString: false },
        { id: "time", type: "time", label: "Time", default: "12:30" },
        { id: "colour", type: "color", label: "Colour", default: "#7c3aed" },
        { id: "formatted", type: "date", label: "Formatted", default: "2026-09-08", returnString: true, dateFormat: "DD/MM/YYYY" },
        { id: "rgba", type: "color", label: "RGBA", default: "#ff0000", colorFormat: "rgba" },
        { id: "precise", type: "number", label: "Precise", default: 1.236, precision: 2 },
        { id: "numericDay", type: "date", label: "Numeric day", default: numericDefault, returnString: true },
        { id: "numericTime", type: "time", label: "Numeric time", default: numericDefault },
        { id: "advanced", type: "date", label: "Advanced", default: "2026-09-08", returnString: true, dateFormat: "[On] dddd, MMMM Do [Q]Q YYYY" },
    ]

    it("initializes every field and converts dates and time to epoch milliseconds on submit", () => {
        const values = createFieldValues(temporalFields)
        const submitted = submissionValues(temporalFields, values)

        expect(submitted.day).toBe(new Date("2026-09-08T00:00:00").getTime())
        expect(submitted.window).toEqual([
            new Date("2026-09-08T00:00:00").getTime(),
            new Date("2026-09-10T00:00:00").getTime(),
        ])
        const time = new Date(submitted.time as number)
        expect(time.getHours()).toBe(12)
        expect(time.getMinutes()).toBe(30)
        expect(time.getSeconds()).toBe(0)
        expect(submitted.colour).toBe("#7c3aed")
        expect(submitted.formatted).toBe("08/09/2026")
        expect(submitted.rgba).toBe("rgba(255, 0, 0, 1)")
        expect(submitted.precise).toBe(1.24)
        expect(submitted.numericDay).toBe("08/09/2026")
        const numericTime = new Date(submitted.numericTime as number)
        expect(numericTime.getHours()).toBe(17)
        expect(numericTime.getMinutes()).toBe(45)
        expect(submitted.advanced).toBe("On Tuesday, September 8th Q3 2026")
    })

    it("rejects a reversed date range", () => {
        const values = createFieldValues(temporalFields)
        values.window = ["2026-09-10", "2026-09-08"]
        expect(validateFields(temporalFields, values).window).toBe("Invalid format.")
    })
})
