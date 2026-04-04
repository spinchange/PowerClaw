# Personal Overlay

Machine-specific note and knowledge-base tools live here so the main repo stays
portable by default.

## Included tools

- `Search-MyJoNotes`
- `Search-MnVault`

## Enable workflow

1. Run `pwsh -File .\Install-PowerClawOverlay.ps1 -OverlayName personal` from
   the repo root or installed module root.
2. Or manually copy tool files from `overlays\personal\tools\` into the active
   `tools\` directory and add their names to the active `tools-manifest.json`.
3. Only enable these on machines that actually have the required local paths.

## Why this exists

These tools are valid local customizations, but they are not part of the
portable default PowerClaw product.
