# NEXUS OS

**NEXUS OS** is an experimental, modular Linux distribution project focused on making older computers useful through a lightweight system, a polished desktop experience, and clear security boundaries.

> **Project status:** early foundation / planning stage. This repository is the source of truth. Features are not considered implemented until their code exists and they have been tested.

## Project goals

- Run on modest hardware, with memory and storage use measured rather than guessed.
- Provide a cohesive desktop experience with a futuristic Liquid Glass-inspired visual language.
- Keep the base operating system modular and maintainable.
- Prioritise secure defaults, transparent permissions, and reproducible builds.
- Investigate gaming compatibility, including Steam, without promising support before hardware and driver testing.

## Current reality

The initial repository contained only this README. The project does **not** yet contain a Buildroot tree, a NEXUS Buildroot defconfig, a bootable image, or a working desktop shell. The documentation and diagnostic helper in this branch establish the next engineering steps; they are not a claim that the OS already boots.

## Repository layout

- `docs/ARCHITECTURE.md` — proposed system boundaries and technical decisions.
- `docs/ROADMAP.md` — staged implementation plan and acceptance criteria.
- `configs/README.md` — how configuration files will be introduced and validated.
- `scripts/nexus-doctor.sh` — read-only local environment and project audit.

## First development target

Establish a reproducible Buildroot-based image that boots in QEMU. Only after that baseline is repeatable should the project add a graphical shell and desktop services.

## Running the diagnostic

From the repository root:

```sh
bash scripts/nexus-doctor.sh
```

The script is read-only. It reports whether expected source/configuration files and common QEMU executables are present. It does not install packages, change configuration, compile, or claim that a QEMU boot succeeded.

## Design principles

1. **Measure, don't market:** memory, boot time, image size, and compatibility claims need recorded test results.
2. **Small trusted base:** keep privileged services and default background processes to a minimum.
3. **Separate layers:** base OS, compositor/window management, desktop shell, and optional applications should be independently understandable.
4. **Safe updates:** updates should be signed, verifiable, recoverable, and documented before being enabled by default.
5. **No silent assumptions:** record versions, configuration, hardware, and test commands for every release candidate.

See the [architecture](docs/ARCHITECTURE.md) and [roadmap](docs/ROADMAP.md) for the working plan.
