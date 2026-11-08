import { fireEvent, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { useState } from "react"
import { describe, expect, it, vi } from "vitest"

import { FormFields, createFieldValues, submissionValues, validateFields } from "@/components/input/FormFields"
import { copyToClipboard } from "@/lib/clipboard"
import { fetchNui } from "@/lib/fetchNui"
import type { FieldValue, InputField } from "@/lib/types"

vi.mock("@/lib/clipboard", () => ({ copyToClipboard: vi.fn(async () => true) }))
vi.mock("@/lib/fetchNui", async (importOriginal) => ({ ...(await importOriginal<typeof import("@/lib/fetchNui")>()), fetchNui: vi.fn() }))

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
    it("edits typed switches without JSON and protects required rows", async () => {
        const user = userEvent.setup()
        function TypedTable() {
            const fields: InputField[] = [{ id: "rows", type: "key-value", label: "Roles", requiredKeys: ["default"],
                valueField: { id: "item", type: "checkbox", label: "Value" },
                default: [{ key: "default", value: "false" }] }]
            const [values, setValues] = useState(createFieldValues(fields))
            return <><FormFields fields={fields} values={values} errors={{}} onChange={setValues} /><output data-testid="typed-values">{JSON.stringify(values)}</output></>
        }
        render(<TypedTable />)
        expect(screen.getByLabelText("Roles row 1 key")).toHaveAttribute("readonly")
        expect(screen.getByRole("button", { name: "Delete row 1" })).toBeDisabled()
        const toggle = screen.getByRole("checkbox", { name: "Roles row 1 value" })
        expect(toggle).not.toBeChecked()
        await user.click(toggle)
        expect(screen.getByTestId("typed-values")).toHaveTextContent('"value":"true"')
    })

    it("validates typed row limits, choices and string identity", () => {
        const field: InputField = { id: "rows", type: "key-value", label: "Rates",
            valueField: { id: "item", type: "number", label: "Value", required: true, min: 0, wholeNumber: true } }
        expect(validateFields([field], { rows: [{ key: "default", value: "-1" }] }).rows).toContain("at least 0")
        expect(validateFields([field], { rows: [{ key: "default", value: "0.5" }] }).rows).toContain("whole number")
        expect(validateFields([field], { rows: [{ key: "default", value: '""' }] }).rows).toBeTruthy()
        const text: InputField = { ...field, valueField: { id: "item", type: "text", label: "Value" } }
        expect(validateFields([text], { rows: [{ key: "code", value: '"42"' }] })).toEqual({})
        expect(validateFields([text], { rows: [{ key: "code", value: "42" }] }).rows).toBeTruthy()
        const choice: InputField = { ...field, valueField: { id: "item", type: "select", label: "Value", options: [{ value: "false", label: "Off" }] } }
        expect(validateFields([choice], { rows: [{ key: "flag", value: "false" }] })).toEqual({})
        expect(validateFields([choice], { rows: [{ key: "flag", value: "true" }] }).rows).toBeTruthy()
    })

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

    it("fills a pickPosition vector from the player position, up to its dimensions", async () => {
        const user = userEvent.setup()
        vi.mocked(fetchNui).mockResolvedValueOnce({ x: 10.13, y: -20.5, z: 30.01, w: 270.46 }).mockResolvedValueOnce({})
        function PickHarness() {
            const fields: InputField[] = [{ id: "spawn", type: "vector", label: "Spawn", dimensions: 3, pickPosition: { label: "Use vehicle position", vehicle: true } }]
            const [values, setValues] = useState<Record<string, FieldValue>>(createFieldValues(fields))
            return <><FormFields fields={fields} values={values} errors={{}} onChange={setValues} /><output data-testid="vector-values">{JSON.stringify(values)}</output></>
        }
        render(<PickHarness />)
        await user.click(screen.getByRole("button", { name: "Use vehicle position" }))
        expect(fetchNui).toHaveBeenCalledWith("kora_lib:form:position", { vehicle: true })
        expect(screen.getByRole("textbox", { name: "Spawn X" })).toHaveValue("10.13")
        expect(JSON.parse(screen.getByTestId("vector-values").textContent ?? "{}").spawn).toEqual({ x: 10.13, y: -20.5, z: 30.01 })

        await user.click(screen.getByRole("button", { name: "Use vehicle position" }))
        expect(JSON.parse(screen.getByTestId("vector-values").textContent ?? "{}").spawn).toEqual({ x: 10.13, y: -20.5, z: 30.01 })
    })

    it("only shows the position button when pickPosition is set", () => {
        render(<FormFields fields={[{ id: "spawn", type: "vector", label: "Spawn", dimensions: 2 }]} values={{ spawn: { x: 1, y: 2 } }} errors={{}} onChange={() => {}} />)
        expect(screen.queryByRole("button", { name: "Use my position" })).not.toBeInTheDocument()
    })
})


describe("FormFields accepted color formats", () => {
    const formats: NonNullable<InputField["colorFormat"]>[] = ["hex", "hexa", "rgb", "rgba", "hsl", "hsla"]
    const colorFields: InputField[] = formats.map((colorFormat) => ({ id: colorFormat, type: "color", label: colorFormat, colorFormat }))
    const convert = (value: string) => submissionValues(colorFields, Object.fromEntries(formats.map((format) => [format, value])))

    it("converts all accepted RGB and HSL forms without turning HSL into white", () => {
        const red = { hex: "#ff0000", hexa: "#ff0000ff", rgb: "rgb(255, 0, 0)", rgba: "rgba(255, 0, 0, 1)", hsl: "hsl(0, 100%, 50%)", hsla: "hsla(0, 100%, 50%, 1)" }
        for (const input of ["#FF0000", "#ff0000ff", "rgb(255, 0, 0)", "rgba(255, 0, 0)", "rgb(255, 0, 0, 1)", "hsl(0, 100%, 50%)", "hsla(360, 100%, 50%)", "hsl(720, 100%, 50%, 1)"]) {
            expect(validateFields(colorFields, Object.fromEntries(formats.map((format) => [format, input])))).toEqual({})
            expect(convert(input)).toEqual(red)
        }
        expect(convert("hsl(-120, 100%, 50%)").hex).toBe("#0000ff")
        const fractional = "HSLA( 30.5 , 50.5% , 40.5% , .25 )"
        expect(validateFields(colorFields, Object.fromEntries(formats.map((format) => [format, fractional])))).toEqual({})
        expect(convert(fractional).hex).toBe("#9b6833")
        expect(convert(fractional).rgba).toBe("rgba(155, 104, 51, 0.25)")
        for (const [hue, expected] of [[60, "#ffff00"], [120, "#00ff00"], [180, "#00ffff"], [300, "#ff00ff"]]) {
            expect(convert(`hsl(${hue}, 100%, 50%)`).hex).toBe(expected)
        }
        expect(convert("hsl(240, 0%, 50%)")).toEqual({ hex: "#808080", hexa: "#808080ff", rgb: "rgb(128, 128, 128)", rgba: "rgba(128, 128, 128, 1)", hsl: "hsl(0, 0%, 50%)", hsla: "hsla(0, 0%, 50%, 1)" })
    })

    it("preserves zero, fractional and eight-digit-hex alpha in alpha-bearing outputs", () => {
        for (const input of ["rgba(255, 0, 0, .5)", "hsla(0, 100%, 50%, .5)", "hsl(0, 100%, 50%, .5)"]) {
            expect(convert(input)).toEqual({ hex: "#ff0000", hexa: "#ff000080", rgb: "rgb(255, 0, 0)", rgba: "rgba(255, 0, 0, 0.5)", hsl: "hsl(0, 100%, 50%)", hsla: "hsla(0, 100%, 50%, 0.5)" })
        }
        expect(convert("#11223380")).toEqual({ hex: "#112233", hexa: "#11223380", rgb: "rgb(17, 34, 51)", rgba: `rgba(17, 34, 51, ${128 / 255})`, hsl: "hsl(210, 50%, 13%)", hsla: `hsla(210, 50%, 13%, ${128 / 255})` })
        expect(convert("#00000000")).toEqual({ hex: "#000000", hexa: "#00000000", rgb: "rgb(0, 0, 0)", rgba: "rgba(0, 0, 0, 0)", hsl: "hsl(0, 0%, 0%)", hsla: "hsla(0, 0%, 0%, 0)" })
        expect(convert("rgb(1, 2, 3, .25)").hexa).toBe("#01020340")
    })

    it("keeps the existing supported draft syntax and invalid-color rejection", () => {
        const field: InputField[] = [{ id: "color", type: "color", label: "Color", required: true }]
        for (const input of ["#fff", "red", "rgb(256, 0, 0)", "rgba(0, 0, 0, 1.1)", "hsl(0, 101%, 50%)", "hsl(0, 0%, -1%)", "hsl(Infinity, 0%, 0%)", "rgb(255 0 0 / .5)"]) {
            expect(validateFields(field, { color: input }).color).toBe("Invalid format.")
        }
    })

    it("shows the accepted HSL draft in the native color input and submits its typed alpha", async () => {
        function ColorHarness() {
            const fields: InputField[] = [{ id: "color", type: "color", label: "Color", colorFormat: "hsla", default: "hsl(0, 100%, 50%)" }]
            const [values, setValues] = useState(createFieldValues(fields))
            return <><FormFields fields={fields} values={values} errors={validateFields(fields, values)} onChange={setValues} /><output data-testid="color-result">{JSON.stringify(submissionValues(fields, values))}</output></>
        }
        render(<ColorHarness />)
        expect(screen.getByLabelText("Color")).toHaveValue("#ff0000")
        const user = userEvent.setup()
        await user.tripleClick(screen.getByRole("textbox", { name: "Color value" }))
        await user.keyboard("hsla(240, 100%, 50%, .25)")
        expect(screen.getByLabelText("Color")).toHaveValue("#0000ff")
        expect(screen.getByTestId("color-result")).toHaveTextContent('"color":"hsla(240, 100%, 50%, 0.25)"')
    })
})


describe("FormFields required and optional date ranges", () => {
    const required: InputField[] = [{ id: "window", type: "date-range", label: "Window", required: true, returnString: false }]

    it("requires both endpoints while preserving labels and hidden-field handling", () => {
        for (const window of [[], ["2026-09-30"], ["", ""], ["", "2026-09-30"], ["2026-09-28", ""]]) {
            expect(validateFields(required, { window }).window).toBe("Required.")
        }
        expect(validateFields(required, { window: ["", "2026-09-30"] }, { required: "Choose both dates." }).window).toBe("Choose both dates.")
        expect(validateFields([{ ...required[0], visibleWhen: { fieldId: "shown", equals: true } }], { shown: false, window: ["", "2026-09-30"] })).toEqual({})
        expect(validateFields(required, { window: ["2026-09-28", "2026-09-30"] })).toEqual({})
    })

    it("rejects present invalid dates, calendar rollover and reversed ranges", () => {
        for (const window of [["not-a-date", "2026-09-30"], ["2026-02-30", "2026-09-30"], ["2026-13-01", "2026-09-30"], ["2026-09-30", "2026-09-28"]]) {
            expect(validateFields(required, { window }).window).toBe("Invalid format.")
        }
        expect(validateFields(required, { window: ["2028-02-29", "2028-03-01"] })).toEqual({})
    })

    it("preserves optional blank positions like scalar dates without NaN or JSON null", () => {
        const optional: InputField[] = [{ ...required[0], required: false }, { id: "day", type: "date", label: "Day", returnString: false }]
        const timestamp = new Date("2026-09-30T00:00:00").getTime()
        for (const [window, expected] of [[[], []], [["", ""], ["", ""]], [["", "2026-09-30"], ["", timestamp]], [["2026-09-30", ""], [timestamp, ""]], [["2026-09-30"], [timestamp]]] as [string[], (string | number)[]][]) {
            expect(validateFields(optional, { window, day: "" })).toEqual({})
            const submitted = submissionValues(optional, { window, day: "" })
            expect(submitted).toEqual({ window: expected, day: "" })
            expect(JSON.stringify(submitted)).not.toContain("null")
        }
        expect(submissionValues([{ ...optional[0], returnString: true, dateFormat: "DD/MM/YYYY" }], { window: ["", "2026-09-30"] }).window).toEqual(["", "30/09/2026"])
    })

    it("reports the real end-only input change until its start date is selected", () => {
        function DateHarness() {
            const [values, setValues] = useState(createFieldValues(required))
            return <><FormFields fields={required} values={values} errors={validateFields(required, values)} onChange={setValues} /><output data-testid="date-values">{JSON.stringify(values)}</output></>
        }
        render(<DateHarness />)
        fireEvent.change(screen.getByLabelText("Window end"), { target: { value: "2026-09-30" } })
        expect(screen.getByTestId("date-values")).toHaveTextContent('"window":["","2026-09-30"]')
        expect(screen.getByText("Required.")).toBeInTheDocument()
        fireEvent.change(screen.getByLabelText("Window start"), { target: { value: "2026-09-28" } })
        expect(screen.queryByText("Required.")).not.toBeInTheDocument()
    })
})

describe("FormFields keypad presentation options", () => {
    const pin = (extra: Partial<InputField> = {}): InputField[] => [{ id: "pin", type: "password", label: "PIN", maxLength: 4, numericOnly: true, keypad: true, ...extra }]

    it("keeps the left-aligned label and borderless action keys by default", () => {
        render(<FormFields fields={pin()} values={{ pin: "" }} errors={{}} onChange={() => undefined} />)
        expect(screen.getByText("PIN")).not.toHaveClass("justify-center")
        expect(screen.getByRole("button", { name: "Clear" })).not.toHaveClass("border")
        expect(screen.getByRole("button", { name: "Backspace" })).not.toHaveClass("border")
    })

    it("centres the label and outlines Clear and Backspace like the digit keys when asked", () => {
        render(<FormFields fields={pin({ labelAlign: "center", keypadActionVariant: "outline" })} values={{ pin: "" }} errors={{}} onChange={() => undefined} />)
        expect(screen.getByText("PIN")).toHaveClass("justify-center", "text-center")
        const digit = screen.getByRole("button", { name: "1" })
        expect(digit).toHaveClass("border", "border-control-border")
        for (const name of ["Clear", "Backspace"]) expect(screen.getByRole("button", { name })).toHaveClass("border", "border-control-border")
    })

    it("ignores unknown option values instead of changing the default look", () => {
        render(<FormFields fields={pin({ labelAlign: "middle" as never, keypadActionVariant: "solid" as never })} values={{ pin: "" }} errors={{}} onChange={() => undefined} />)
        expect(screen.getByText("PIN")).not.toHaveClass("justify-center")
        expect(screen.getByRole("button", { name: "Clear" })).not.toHaveClass("border")
    })
})

describe("FormFields copyButton", () => {
    it("renders Copy Text only when opted in and copies the current value", async () => {
        const plain: InputField[] = [{ id: "m", type: "text", label: "Model" }]
        const { unmount } = render(<FormFields fields={plain} values={{ m: "prop_a" }} errors={{}} onChange={() => undefined} />)
        expect(screen.queryByRole("button", { name: "Copy Text" })).toBeNull()
        unmount()
        render(<FormFields fields={[{ ...plain[0], copyButton: true }]} values={{ m: "prop_a" }} errors={{}} onChange={() => undefined} />)
        await userEvent.click(screen.getByRole("button", { name: "Copy Text" }))
        expect(copyToClipboard).toHaveBeenCalledWith("prop_a")
        expect(await screen.findByRole("button", { name: "Copied" })).toBeTruthy()
    })
})
