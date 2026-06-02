# Codex Windows Fast Patch Skill

Language: [中文](README.md) | English

This is the public version of the `codex-windows-fast-patch` skill. It guides agents through restoring local Codex Desktop patches and feature gates after Windows Store upgrades.

## Features

- Reapply the Windows MSIX patch after Codex Desktop upgrades.
- Verify that Fast Mode requests really send `service_tier=priority`.
- Register and repair local plugin marketplace configuration.
- Repair local plugin marketplace manifest layout.
- Refresh Windows Computer Use compatibility files.
- Unlock the Computer Control `Any App` gate when the UI reports organization or region unavailability.
- Restore Codex Desktop Chinese locale resources and i18n gates when an upgrade falls back to English UI.
- Add a local-thread `Delete chat` entry to the sidebar menu for builds that only expose archive.
- Re-enable desktop gates such as Goal / objective entry points when upgrades hide them again.

## Platform Support

This skill supports Windows only.

It depends on the Windows Store / MSIX package layout, PowerShell, `Get-AppxPackage`, `makeappx.exe`, `signtool.exe`, Windows user environment variables, and Windows Computer Use helper paths.

Do not run it on macOS. A macOS version needs a separate workflow for the Codex `.app` bundle, ASAR extraction and repacking, `codesign` or quarantine handling, shell scripts, and macOS-specific Computer Use availability gates.

## Files

- `SKILL.md`: Agent skill entrypoint.
- `MAINTENANCE.md`: Notes for future sessions, update rules, and recent merge history.
- `agents/openai.yaml`: Agent configuration.
- `scripts/repatch-codex-windows.ps1`: Workflow reference script.
- `scripts/patch_codex_fast_mode_windows_msix.ps1`: MSIX / ASAR patch reference implementation.
- `scripts/install-patched-msix.ps1`: Helper for trusting a signing certificate and installing a previously built patched MSIX.
- `scripts/install-computer-use-local.ps1`: Windows Computer Use local compatibility reference implementation.

## Install

Clone this repository, open PowerShell in the repository root, then copy only the skill files:

```powershell
$source = (Get-Location).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
  throw 'Run this command from the codex-windows-fast-patch-skill repository root.'
}

$dest = Join-Path $env:USERPROFILE '.codex\skills\codex-windows-fast-patch'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item -Force -LiteralPath (Join-Path $source 'SKILL.md') -Destination $dest
Copy-Item -Force -LiteralPath (Join-Path $source 'MAINTENANCE.md') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'agents') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'scripts') -Destination $dest
```

After installing into Codex, restart Codex so it reloads skill metadata.

## Usage

After installation, ask an agent that supports Agent Skills to use `$codex-windows-fast-patch` for the Codex Desktop issue on the current machine. This skill is intended for Windows Codex Desktop upgrades, reinstalls, missing feature gates, English UI regressions, unavailable Computer Use, broken plugin marketplaces, or Fast Mode verification.

Recommended request:

```text
Use $codex-windows-fast-patch to inspect and repair Codex Desktop on this Windows machine. Restore Fast Mode, plugin marketplace, Goal, Windows Computer Use, Chinese UI, and the sidebar Delete chat action.
```

You can also trigger a narrower repair:

```text
Use $codex-windows-fast-patch to verify whether my Fast Mode requests really send service_tier=priority.
```

```text
Use $codex-windows-fast-patch to fix the Codex Desktop Any App gate being disabled by organization or region policy.
```

```text
Use $codex-windows-fast-patch to restore the Chinese UI and add Delete chat back to the local conversation menu.
```

The scripts are reference implementations and operational templates, not a one-command fix that is guaranteed to work on every machine. A real run should first read `SKILL.md`, inspect the current Codex installation method, MSIX package path, ASAR contents, signing tools, plugin directories, locale resources, sidebar menu targets, and Computer Use file state, then decide whether to execute, adapt, or only borrow steps from the scripts.

The normal flow is to run `-DryRun` first, confirm that all patch targets are found, then run the full repair. Afterward restart Codex Desktop and verify Fast Mode, Chinese UI, plugin list, Computer Use, Goal entry points, and the `Delete chat` menu item.

## Helper Scripts

To install a previously built patched MSIX without rerunning the full repack flow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\install-patched-msix.ps1" -MsixPath "C:\Users\you\Downloads\codex-msix-repack\OpenAI.Codex_xxx\artifacts\OpenAI.Codex_xxx_patched.msix"
```

The helper can locate a certificate by publisher automatically, or you can pass `-CertThumbprint <thumbprint>` when the MSIX was signed with a known local certificate. It also supports `-StatusPath <path>` for timestamped progress logging and `-NoLaunch` if you do not want to start Codex Desktop immediately after install.

Fast Mode verification inside `scripts/patch_codex_fast_mode_windows_msix.ps1` now tries both `model_providers.OpenAI.base_url` and `openai_base_url`, captures both WebSocket frames and HTTP request bodies, disables plugins and apps during the probe, records Codex CLI output per attempt, and keeps the capture directory automatically when verification fails.

## CPA Upstream Configuration

If Codex requests go through CPA upstream, changing the local request to `service_tier=priority` is not enough by itself. Add a CPA override rule for the models that handle Codex requests and force the parameter `service_tier` to string value `priority`, so the upstream actually uses the Fast / Priority path.

The model names in the image are examples. Use the real Codex-facing model names configured in CPA.

![CPA override rule example](assets/cpa-override-rule.svg)

## Acknowledgements

Thanks to the original public work at [chen0416ccc-cpu/codex-windows-fast-patch-skill](https://github.com/chen0416ccc-cpu/codex-windows-fast-patch-skill) and to the [LinuxDo community](https://linux.do/) for the discussions and feedback around this workflow.
