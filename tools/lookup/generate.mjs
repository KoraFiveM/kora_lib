#!/usr/bin/env node

import fs from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'

export const REVISION = 'b65684e00f689fdec405c5f1055322c802d3c895'
export const GTA_BUILD = 'v3717.0 (Online 1.72) [DLC: mp2025_02_g9ec]'
export const SOURCE_URL = 'https://github.com/DurtyFree/gta-v-data-dumps'

const sourceFiles = ['vehicles.json', 'peds.json', 'weapons.json', 'pickupTypes.json', 'ObjectList.ini']
const bundleOrder = ['vehicle', 'ped', 'object', 'weapon', 'weapon_component', 'pickup']

export function joaat(value) {
    let hash = 0
    for (const byte of Buffer.from(value.toLowerCase(), 'utf8')) {
        hash = (hash + byte) >>> 0
        hash = (hash + ((hash << 10) >>> 0)) >>> 0
        hash = (hash ^ (hash >>> 6)) >>> 0
    }
    hash = (hash + ((hash << 3) >>> 0)) >>> 0
    hash = (hash ^ (hash >>> 11)) >>> 0
    return (hash + ((hash << 15) >>> 0)) >>> 0
}

function signed(hash) {
    return hash >= 0x80000000 ? hash - 0x100000000 : hash
}

function assertHash(name, hash, signedHash, hexHash, context) {
    const expected = joaat(name)
    if (!Number.isInteger(hash) || hash < 0 || hash > 0xffffffff || hash !== expected) {
        throw new Error(`${context}: hash for ${name} is ${hash}; expected ${expected}`)
    }
    if (signedHash !== undefined && signedHash !== null && signedHash !== signed(expected)) {
        throw new Error(`${context}: signed hash for ${name} is ${signedHash}; expected ${signed(expected)}`)
    }
    if (hexHash !== undefined && hexHash !== null && Number.parseInt(hexHash, 16) !== expected) {
        throw new Error(`${context}: hexadecimal hash for ${name} is ${hexHash}; expected 0x${expected.toString(16).toUpperCase()}`)
    }
    return expected
}

function translated(value) {
    if (!value || typeof value !== 'object') return [undefined, undefined]
    return [value.English || undefined, value.Name || undefined]
}

function add(groups, namespace, hash, compact) {
    const byHash = groups[namespace]
    let bucket = byHash.get(hash)
    if (!bucket) {
        bucket = new Map()
        byHash.set(hash, bucket)
    }

    const key = compact[0].toLowerCase()
    const previous = bucket.get(key)
    if (!previous) {
        bucket.set(key, compact)
        return
    }

    // A component may belong to several weapons. Its owner list is the only
    // field that is expected to grow when identical component rows merge.
    if (namespace === 'weapon_component') {
        previous[5] = [...new Set([...(previous[5] || []), ...(compact[5] || [])])].sort()
    }
}

function buildCatalog(sources) {
    const groups = Object.fromEntries(bundleOrder.map(namespace => [namespace, new Map()]))
    const vehicles = JSON.parse(sources['vehicles.json'])
    const peds = JSON.parse(sources['peds.json'])
    const weapons = JSON.parse(sources['weapons.json'])
    const pickups = JSON.parse(sources['pickupTypes.json'])

    for (const vehicle of vehicles) {
        const hash = assertHash(vehicle.Name, vehicle.Hash, vehicle.SignedHash, vehicle.HexHash, 'vehicles.json')
        const [label, labelKey] = translated(vehicle.DisplayName)
        add(groups, 'vehicle', hash, [
            vehicle.Name, label, labelKey, vehicle.Class || undefined, vehicle.DlcName || undefined,
            vehicle.Manufacturer || undefined, vehicle.Type || undefined,
            Number.isInteger(vehicle.Seats) ? vehicle.Seats : undefined,
        ])
    }

    for (const ped of peds) {
        const hash = assertHash(ped.Name, ped.Hash, ped.SignedHash, ped.HexHash, 'peds.json')
        const [label, labelKey] = translated(ped.TranslatedDirectorName)
        add(groups, 'ped', hash, [
            ped.Name, label, labelKey, ped.Pedtype || undefined, ped.DlcName || undefined,
            ped.Pedtype || undefined,
        ])
    }

    for (const weapon of weapons) {
        const hash = assertHash(weapon.Name, weapon.Hash, weapon.IntHash, undefined, 'weapons.json')
        const [label, labelKey] = translated(weapon.TranslatedLabel)
        add(groups, 'weapon', hash, [
            weapon.Name, label, labelKey, weapon.Category || undefined, weapon.DlcName || undefined,
            weapon.ModelName || undefined, weapon.DamageType || undefined,
        ])

        for (const component of weapon.Components || []) {
            const componentHash = assertHash(component.Name, component.Hash, component.IntHash, undefined, 'weapons.json component')
            const [componentLabel, componentLabelKey] = translated(component.TranslatedLabel)
            add(groups, 'weapon_component', componentHash, [
                component.Name, componentLabel, componentLabelKey, undefined, component.DlcName || undefined,
                [weapon.Name], component.Type || undefined, component.AttachBone || undefined,
            ])
        }
    }

    for (const pickup of pickups) {
        const hash = assertHash(pickup.Name, pickup.Hash, undefined, undefined, 'pickupTypes.json')
        add(groups, 'pickup', hash, [pickup.Name, undefined, undefined, undefined, undefined, pickup.Model || undefined])
    }

    const objectNames = sources['ObjectList.ini'].split(/\r?\n/)
        .map(name => name.trim())
        .filter(name => name !== '' && !name.startsWith(';') && !name.startsWith('#'))
    for (const name of objectNames) add(groups, 'object', joaat(name), [name])

    return groups
}

function luaString(value) {
    return `"${value.replace(/[\\"\x00-\x1f\x7f]/g, character => {
        if (character === '\\') return '\\\\'
        if (character === '"') return '\\"'
        if (character === '\n') return '\\n'
        if (character === '\r') return '\\r'
        if (character === '\t') return '\\t'
        return `\\${character.charCodeAt(0).toString().padStart(3, '0')}`
    })}"`
}

function luaValue(value) {
    if (value === undefined || value === null) return 'nil'
    if (typeof value === 'string') return luaString(value)
    if (typeof value === 'number') return String(value)
    if (Array.isArray(value)) return `{${value.map(luaValue).join(',')}}`
    throw new Error(`Unsupported generated value: ${typeof value}`)
}

function trimCompact(compact) {
    let end = compact.length
    while (end > 0 && compact[end - 1] === undefined) end--
    return compact.slice(0, end)
}

function renderBundle(namespace, groups) {
    const lines = [
        '-- Generated by tools/lookup/generate.mjs. Do not edit.',
        `-- DurtyFree/gta-v-data-dumps@${REVISION}`,
        'return {',
    ]
    const hashes = [...groups[namespace].keys()].sort((left, right) => left - right)
    for (const hash of hashes) {
        const bucket = groups[namespace].get(hash)
        const candidates = [...bucket.values()].sort((left, right) => {
            const leftFolded = left[0].toLowerCase()
            const rightFolded = right[0].toLowerCase()
            if (leftFolded !== rightFolded) return leftFolded < rightFolded ? -1 : 1
            if (left[0] === right[0]) return 0
            return left[0] < right[0] ? -1 : 1
        }).map(trimCompact)
        const value = candidates.length === 1 ? luaValue(candidates[0]) : luaValue(candidates)
        lines.push(` [${hash}]=${value},`)
    }
    lines.push('}', '')
    return lines.join('\n')
}

async function readSources(inputDirectory) {
    const sources = {}
    if (inputDirectory) {
        for (const file of sourceFiles) sources[file] = await fs.readFile(path.join(inputDirectory, file), 'utf8')
        return sources
    }

    for (const file of sourceFiles) {
        const url = `https://raw.githubusercontent.com/DurtyFree/gta-v-data-dumps/${REVISION}/${file}`
        const response = await fetch(url)
        if (!response.ok) throw new Error(`Could not download ${url}: HTTP ${response.status}`)
        sources[file] = await response.text()
    }
    return sources
}

function counts(groups) {
    const result = {}
    for (const namespace of bundleOrder) {
        let entries = 0
        for (const bucket of groups[namespace].values()) entries += bucket.size
        result[namespace] = { hashes: groups[namespace].size, entries }
    }
    return result
}

export async function generate({ inputDirectory, outputDirectory, check = false, sources: suppliedSources } = {}) {
    if (!outputDirectory) throw new Error('An output directory is required.')
    const sources = suppliedSources || await readSources(inputDirectory)
    const groups = buildCatalog(sources)
    const outputs = {}
    for (const namespace of bundleOrder) outputs[`${namespace}.lua`] = renderBundle(namespace, groups)
    outputs['source.json'] = `${JSON.stringify({
        upstream: 'DurtyFree/gta-v-data-dumps',
        url: SOURCE_URL,
        revision: REVISION,
        gtaBuild: GTA_BUILD,
        files: sourceFiles,
        counts: counts(groups),
    }, null, 2)}\n`

    if (check) {
        const changed = []
        for (const [file, content] of Object.entries(outputs)) {
            let current
            try { current = await fs.readFile(path.join(outputDirectory, file), 'utf8') } catch { current = undefined }
            if (current !== content) changed.push(file)
        }
        if (changed.length) throw new Error(`Generated lookup data is out of date: ${changed.join(', ')}`)
        return { outputs, counts: counts(groups), changed: false }
    }

    await fs.mkdir(outputDirectory, { recursive: true })
    await Promise.all(Object.entries(outputs).map(([file, content]) => fs.writeFile(path.join(outputDirectory, file), content)))
    return { outputs, counts: counts(groups), changed: true }
}

function parseArguments(argv) {
    const options = { outputDirectory: path.resolve('modules/lookup/data') }
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index]
        if (argument === '--check') options.check = true
        else if (argument === '--input') options.inputDirectory = path.resolve(argv[++index])
        else if (argument === '--output') options.outputDirectory = path.resolve(argv[++index])
        else throw new Error(`Unknown argument: ${argument}`)
    }
    return options
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    try {
        const result = await generate(parseArguments(process.argv.slice(2)))
        const summary = bundleOrder.map(namespace => `${namespace}=${result.counts[namespace].entries}`).join(', ')
        console.log(`${result.changed ? 'Generated' : 'Verified'} lookup data (${summary})`)
    } catch (error) {
        console.error(error.message)
        process.exitCode = 1
    }
}
