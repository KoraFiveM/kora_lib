import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'

import { generate, joaat, REVISION } from './generate.mjs'

function fixtures(overrides = {}) {
    const vehicleName = 'test_vehicle'
    const pedName = 'test_ped'
    const weaponName = 'WEAPON_TEST'
    const componentName = 'COMPONENT_TEST'
    const pickupName = 'PICKUP_TEST'
    const signed = name => {
        const hash = joaat(name)
        return hash >= 0x80000000 ? hash - 0x100000000 : hash
    }
    const data = {
        'vehicles.json': JSON.stringify([{ Name: vehicleName, Hash: joaat(vehicleName), SignedHash: signed(vehicleName), HexHash: `0x${joaat(vehicleName).toString(16)}`, DisplayName: { English: 'Test Vehicle', Name: 'TESTVEH' }, Class: 'TEST', Type: 'CAR', Seats: 2 }]),
        'peds.json': JSON.stringify([{ Name: pedName, Hash: joaat(pedName), SignedHash: signed(pedName), HexHash: `0x${joaat(pedName).toString(16)}`, Pedtype: 'CIVMALE' }]),
        'weapons.json': JSON.stringify([{ Name: weaponName, Hash: joaat(weaponName), IntHash: signed(weaponName), Components: [{ Name: componentName, Hash: joaat(componentName), IntHash: signed(componentName), AttachBone: 'gun_root', Type: 'test' }] }]),
        'pickupTypes.json': JSON.stringify([{ Name: pickupName, Hash: joaat(pickupName), Model: 'w_test' }]),
        'ObjectList.ini': 'test_object\ntest_object\n',
    }
    return { ...data, ...overrides }
}

test('JOAAT is case-insensitive and uses unsigned 32-bit output', () => {
    assert.equal(joaat('adder'), 3078201489)
    assert.equal(joaat('ADDER'), 3078201489)
})

test('generation is deterministic, records collisions, and check detects changes', async () => {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'qblib-lookup-'))
    try {
        const source = fixtures({ 'ObjectList.ini': 'collision_10a4\ncollision_5kq0\n' })
        const first = await generate({ outputDirectory: directory, sources: source })
        const objectOutput = first.outputs['object.lua']
        assert.match(objectOutput, /\{\{"collision_10a4"\},\{"collision_5kq0"\}\}/)
        assert.match(first.outputs['source.json'], new RegExp(REVISION))

        const second = await generate({ outputDirectory: directory, sources: source, check: true })
        assert.equal(second.changed, false)
        await fs.appendFile(path.join(directory, 'vehicle.lua'), '-- changed\n')
        await assert.rejects(generate({ outputDirectory: directory, sources: source, check: true }), /out of date/)
    } finally {
        await fs.rm(directory, { recursive: true, force: true })
    }
})

test('generation rejects JOAAT mismatches', async () => {
    const source = fixtures()
    const vehicles = JSON.parse(source['vehicles.json'])
    vehicles[0].Hash = 1
    source['vehicles.json'] = JSON.stringify(vehicles)
    await assert.rejects(generate({ outputDirectory: '/unused', sources: source }), /expected/)
})
