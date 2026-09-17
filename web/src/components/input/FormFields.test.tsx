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

function KeyValueHarness() {
    const tableFields: InputField[] = [{
        id: "roles",
        type: "key-value",
        label: "Authorised roles",
        keyMode: "string",
        default: [{ key: "police", value: "true" }],
    }]
    const [values, setValues] = useState<Record<string, FieldValue>>(createFieldValues(tableFields))
    return <><FormFields fields={tableFields} values={values} errors={validateFields(tableFields, values)} onChange={setValues} /><output data-testid="table-values">{JSON.stringify(values)}</output></>
}

describe("FormFields key/value tables", () => {
    it("adds, edits, validates, and deletes rows", async () => {
        const user = userEvent.setup()
        render(<KeyValueHarness />)

        expect(screen.getByRole("textbox", { name: "Authorised roles row 1 key" })).toHaveValue("police")
        await user.click(screen.getByRole("button", { name: "Add row" }))
        await user.type(screen.getByRole("textbox", { name: "Authorised roles row 2 key" }), "ambulance")
        await user.type(screen.getByRole("textbox", { name: "Authorised roles row 2 value" }), "true")

        expect(screen.getByTestId("table-values")).toHaveTextContent('"key":"ambulance","value":"true"')
        await user.click(screen.getByRole("button", { name: "Delete row 1" }))
        expect(screen.queryByDisplayValue("police")).not.toBeInTheDocument()
        expect(screen.getByDisplayValue("ambulance")).toBeInTheDocument()
    })

    it("reports duplicate keys and malformed structured values", () => {
        const tableFields: InputField[] = [{ id: "rows", type: "key-value", label: "Rows" }]
        expect(validateFields(tableFields, { rows: [
            { key: "one", value: "true" },
            { key: "one", value: "{" },
        ] }).rows).toBe("Key “one” is used more than once.")
        expect(validateFields(tableFields, { rows: [{ key: "one", value: "{" }] }).rows).toBe("Row 1 needs a valid value.")
        expect(validateFields([{ ...tableFields[0], keyMode: "integer" }], { rows: [
            { key: "1", value: "true" },
            { key: "3", value: "true" },
        ] }).rows).toBe("List positions must run consecutively from 1.")
    })

    it("accepts sparse integer maps without list-style position rules", () => {
        const fields: InputField[] = [{ id: "rows", type: "key-value", label: "Rates", keyMode: "integer-map" }]
        expect(validateFields(fields, { rows: [
            { key: "0", value: "0.1" },
            { key: "7", value: "1.0" },
        ] })).toEqual({})
        expect(validateFields(fields, { rows: [{ key: "class", value: "1" }] }).rows)
            .toContain("whole-number")
    })

    it("accepts maps containing both text and integer keys", () => {
        const fields: InputField[] = [{ id: "rows", type: "key-value", label: "Rates", keyMode: "mixed" }]
        expect(validateFields(fields, { rows: [
            { key: "default", value: "0.5" },
            { key: "0", value: "0.1" },
        ] })).toEqual({})
    })

    it("paginates large tables so only one bounded row set is mounted", async () => {
        const user = userEvent.setup()
        const rows = Array.from({ length: 51 }, (_, index) => ({ key: String(index + 1), value: "true" }))
        function LargeTableHarness() {
            const largeFields: InputField[] = [{ id: "rows", type: "key-value", label: "Rows", keyMode: "integer", default: rows }]
            const [values, setValues] = useState<Record<string, FieldValue>>(createFieldValues(largeFields))
            return <FormFields fields={largeFields} values={values} errors={{}} onChange={setValues} />
        }
        render(<LargeTableHarness />)

        expect(screen.getByRole("textbox", { name: "Rows row 50 key" })).toBeInTheDocument()
        expect(screen.queryByRole("textbox", { name: "Rows row 51 key" })).not.toBeInTheDocument()
        await user.click(screen.getByRole("button", { name: "Next" }))
        expect(screen.getByRole("textbox", { name: "Rows row 51 key" })).toBeInTheDocument()
    })
})

describe("FormFields configuration types", () => {
    const typedFields: InputField[] = [
        { id: "count", type: "number", label: "Count", wholeNumber: true, required: true },
        { id: "colour", type: "color", label: "Colour", required: true },
        { id: "spawn", type: "vector", label: "Spawn", dimensions: 3, required: true },
    ]

    it("validates whole numbers, colour drafts, and every vector component", () => {
        expect(validateFields(typedFields, {
            count: 1.5,
            colour: "not-a-colour",
            spawn: { x: 1, y: 2, z: "bad" },
        })).toEqual({
            count: "Must be a whole number.",
            colour: "Invalid format.",
            spawn: "Every coordinate must be a finite number.",
        })
        expect(validateFields(typedFields, {
            count: 2,
            colour: "#95ff00",
            spawn: { x: 1, y: 2, z: 3 },
        })).toEqual({})
    })

    it("edits vectors through dedicated coordinate inputs", async () => {
        const user = userEvent.setup()
        function VectorHarness() {
            const fields: InputField[] = [{ id: "spawn", type: "vector", label: "Spawn", dimensions: 3,
                default: { x: 1, y: 2, z: 3 } }]
            const [values, setValues] = useState<Record<string, FieldValue>>(createFieldValues(fields))
            return <><FormFields fields={fields} values={values} errors={validateFields(fields, values)} onChange={setValues} /><output data-testid="vector-values">{JSON.stringify(values)}</output></>
        }
        render(<VectorHarness />)
        await user.clear(screen.getByRole("textbox", { name: "Spawn X" }))
        await user.type(screen.getByRole("textbox", { name: "Spawn X" }), "4.5")
        expect(screen.getByTestId("vector-values")).toHaveTextContent('"x":4.5')
    })
})
