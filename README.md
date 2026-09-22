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

`assets/reference/reference_empty_groove.json` and
`reference_welded_groove.json` are rasterized (300x300 grid) from real
laser-profilometer point-cloud scans (`Transformer/data/no-tack-V-groove.ply`
and `tack-V-groove.ply`), windowed to a single tack weld at
Y = 185-215mm along the groove. See the heightmap JSON format in
`lib/models/heightmap.dart`.

## Backend contract

This app talks to a local HTTP/JSON service (default
`http://localhost:8787`) documented in `lib/services/weld_service.dart`:
`POST /runs` to start a simulation, `GET /runs/{id}` to poll status, and
`GET /runs/{id}/heightmap` to fetch the result once done. That service
lives in the [`fluid`](https://github.com/rick-dalley/fluid) repo.

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
