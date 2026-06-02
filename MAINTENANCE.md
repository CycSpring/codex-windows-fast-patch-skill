# Codex Windows Fast Patch Maintenance Notes

This file is the short-term memory for future updates to this skill repo.
Read it before changing the patch flow, the Fast Mode probe, the Chinese UI
restoration, the local Delete chat menu patch, or the Windows Computer Use
compatibility pieces.

## Current Layout

The repo currently has four important scripts:

- `scripts/repatch-codex-windows.ps1`
  - Wrapper workflow for the normal end-to-end repatch flow.
- `scripts/patch_codex_fast_mode_windows_msix.ps1`
  - MSIX copy, ASAR patch, sign, install, and Fast Mode wire verification.
  - Also contains the desktop webview patchers for Goal, Computer Use, Chinese
    locale restoration, and the local `Delete chat` menu entry.
- `scripts/install-computer-use-local.ps1`
  - Local `computer-use@openai-bundled` compatibility plugin install and verify.
- `scripts/install-patched-msix.ps1`
  - Helper for trusting a signing certificate and installing a previously built
    patched MSIX without rerunning the full repack flow.

## Legacy Standalone Scripts That Were Absorbed

On SpringChen's local machine there were two ad hoc scripts in
`D:\Codex_Programs`:

- `codex_install_admin.ps1`
- `codex_verify_fastmode.ps1`

Their useful behavior has been folded into this repo:

- `codex_install_admin.ps1`
  - Replaced by `scripts/install-patched-msix.ps1`
  - The new helper keeps the install/trust behavior but removes hardcoded
    thumbprints, MSIX paths, and machine-specific launch assumptions.

- `codex_verify_fastmode.ps1`
  - Folded into `Invoke-FastModeVerification` inside
    `scripts/patch_codex_fast_mode_windows_msix.ps1`
  - The repo now keeps the stronger probe behavior:
    - tries both `model_providers.OpenAI.base_url` and `openai_base_url`
    - disables plugins and apps during the probe
    - captures WebSocket frames and HTTP request bodies
    - stores Codex CLI output per attempt
    - keeps the capture directory automatically when verification fails

Do not reintroduce the old standalone scripts as the main workflow unless a
future debugging session needs a throwaway local probe.

## Source Of Truth

For future maintenance, treat this GitHub repo as the canonical working copy.
If the installed local skill and the repo drift:

1. Make the behavior change in the repo copy first.
2. Update `SKILL.md`, `README.en.md`, `README.md`, and this file in the same pass.
3. After the repo is correct, sync the same change into the installed local
   skill under `$env:USERPROFILE\.codex\skills\codex-windows-fast-patch`.
4. Reinstall or refresh the local skill only after the repo copy is in sync.

## Rules For Future Changes

- Keep machine-specific paths out of the main scripts unless they are only
  fallback diagnostics.
- Keep `install-patched-msix.ps1` parameterized.
- Keep Fast Mode verification in the main patch script, not in a separate
  hardcoded helper, unless there is a temporary debugging need.
- If Fast Mode verification changes again, preserve the current diagnostics:
  body capture, frame capture, disabled plugins/apps, per-attempt output, and
  automatic retention of failed capture logs.
- Do not remove the current marketplace manifest repair logic unless the Codex
  plugin loader behavior clearly changes.
- Do not remove the Chinese locale, `Delete chat`, Goal, or Computer Use gate
  patch notes without rechecking the latest target asset patterns.

## Minimum Validation After Editing

After editing any PowerShell script in this repo, run a parser check:

```powershell
$repo = (Get-Location).ProviderPath
$files = @(
  (Join-Path $repo 'scripts\repatch-codex-windows.ps1'),
  (Join-Path $repo 'scripts\patch_codex_fast_mode_windows_msix.ps1'),
  (Join-Path $repo 'scripts\install-computer-use-local.ps1'),
  (Join-Path $repo 'scripts\install-patched-msix.ps1')
)

foreach ($file in $files) {
  $null = $tokens = $null
  $null = $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    Write-Host "PARSE_ERROR $file"
    $errors | ForEach-Object { Write-Host $_.Message }
  } else {
    Write-Host "PARSE_OK $file"
  }
}
```

If Fast Mode verification was changed, also do at least one focused probe run.
If the probe fails, inspect the kept capture directory before changing logic
again.

## Update Checklist

Use this checklist whenever a future session changes the repo:

1. Update the target script or doc.
2. Update `SKILL.md` if behavior, guardrails, or entrypoint usage changed.
3. Update `README.en.md` and `README.md` if a user-facing helper or workflow changed.
4. Update this file if the architectural story changed.
5. Parse-check the edited PowerShell scripts.
6. Run the smallest useful validation command.
7. Sync the same change back into the installed local skill if the local copy is still used.

## Quick Reminder For Next Session

If a future session starts cold, the shortest useful summary is:

- this repo is the canonical copy
- `install-patched-msix.ps1` is the supported replacement for the old install helper
- Fast Mode verification lives in `patch_codex_fast_mode_windows_msix.ps1`
- Chinese UI, Goal, Delete chat, and Computer Use gates are all patched in the main ASAR patch flow
- any new divergence should be documented here and then synced to the installed local skill
