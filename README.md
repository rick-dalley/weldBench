# weldBench

An interactive calibration tool: adjust weld process parameters ("levers"),
press **Weld**, and compare `ferrousFoam`'s simulated puddle/bead shape
against real profilometer scans of an actual welded test coupon.

## What it shows

Three side-by-side heightmaps (Z in mm over an X/Y grid):

1. **Empty groove** — a real laser-profilometer scan of the bare V-groove
   before welding.
2. **Real weld (ground truth)** — a real scan of the same groove after a
   tack weld, showing the actual deposited bead.
3. **ferrousFoam prediction** — the result of running
   [`ferrousFoam`](https://github.com/rick-dalley/ferrousFoam) (a weld-pool
   CFD solver) with the current lever settings, via a local Rust
   orchestration service.

The point is inverse calibration, not live preview: adjust parameters,
press Weld, wait for a real CFD solve (seconds to minutes), and see how
close the result gets to the real scan. Once a parameter set produces a
close match, check whether those values are actually plausible for real
shop practice.

## Data provenance

The two reference panels come from real laser-profilometer point-cloud
scans (`Transformer/data/no-tack-V-groove.ply` and `tack-V-groove.ply`),
windowed to a single tack weld at Y = 185-215mm along the groove, and
rasterized to a 300x300 grid. That rasterization happens live in
`weld_service` (see `fluid/src/bin/weld_service/reference.rs`) — this app
fetches it over HTTP rather than bundling a pre-baked copy, so there's one
authoritative code path for turning the raw scans into a heightmap.

## Backend: started automatically

This app talks to a local HTTP/JSON service (default
`http://localhost:8787`), documented in `lib/services/weld_service.dart`:
`POST /runs` to start a simulation, `GET /runs/{id}` to poll status,
`GET /runs/{id}/heightmap` for the result, and `GET /reference/*` for the
two real reference scans. That service lives in the
[`fluid`](https://github.com/rick-dalley/fluid) repo, as `weld_service`.

You don't need to start it yourself: on launch, `lib/services/service_launcher.dart`
checks whether something is already listening on port 8787 and reuses it if
so; otherwise it spawns `cargo run --bin weld_service` from a sibling `fluid`
checkout (`../fluid` relative to this repo by default, override with the
`WELD_SERVICE_DIR` environment variable) and waits for it to come up. If
weldBench started it, it stops it again on window close; if it found an
already-running instance, it leaves it alone. First launch takes a bit
longer (~15s) while the two real point-cloud scans are parsed; the app shows
a startup screen with status text while this happens.

## Related repos

- [`fluid`](https://github.com/rick-dalley/fluid) — the Rust transformer
  project and orchestration service this app talks to.
- [`ferrousFoam`](https://github.com/rick-dalley/ferrousFoam) — the weld-pool
  CFD solver actually run per request.

This is an independent research/calibration tool — not integrated with
Novarc's `weld_sim` project, by design.

## Running

```
flutter pub get
flutter run -d linux   # or macos / windows
```
