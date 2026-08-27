# Vehicle module

Small client-side helpers for transient vehicle operations. Persistent garage,
ownership, impound, and payment rules belong in qbcore or the resource that
owns them.

- `QB.vehicle.requestControl(entity, timeout?)` requests network control.
- `QB.vehicle.delete(vehicle, { timeout? })` obtains control, marks the
  vehicle as mission-owned, and deletes it. Authorize this server-side first.
- `QB.vehicle.isDriver(vehicle)` checks the local player occupies the driver seat.
- `QB.vehicle.model(vehicle)` returns a vehicle model hash or `false`.
