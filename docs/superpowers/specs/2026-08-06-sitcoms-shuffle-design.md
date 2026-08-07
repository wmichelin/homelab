# Sitcoms Shuffle Tunarr channel (#54)

Date: 2026-08-06  
Host: G5 · Tunarr + Jellyfin TV library  
Status: design approved in chat

## Goal

Add Tunarr channel **#54 Sitcoms Shuffle** that equally mixes **Seinfeld**, **Friends**, and **The Office (US)** (shuffle within each show). Leave **#53 Seinfeld 24/7** unchanged.

## Non-goals

- Adding shows not already in the Jellyfin TV library
- Changing movie genre channels or Seinfeld 24/7
- Time-of-day schedules / blocks

## Library inventory (at design time)

| Show | ~Episodes on disk |
|------|-------------------|
| Seinfeld | 171 |
| Friends | 234 |
| The Office (US) | 185 |

No other classic sitcoms present (other TV titles are drama/reality/kids).

## Design

1. Create channel `#54`, name `Sitcoms Shuffle`, `groupTitle: TV`.
2. Random schedule (`maxDays: 30`, uniform distribution) with **three** slots of type `show`, equal `weight: 100`, `order: shuffle`, `durationSpec: { type: dynamic, programCount: 1 }`.
3. Resolve Tunarr show IDs from the Jellyfin-backed TV library for the three series titles.
4. Add a small idempotent script `scripts/tunarr-seed-sitcoms-shuffle.py` (create/update channel + schedule) and document in `docs/lan-storage.md` next to the Seinfeld note.
5. Operator: Jellyfin Live TV → Refresh Channels / Refresh Guide.

## Success

- Channel 54 appears in Tunarr and Jellyfin Live TV after refresh.
- Guide/lineup alternates among the three shows with roughly equal slot picks.
- Channel 53 still Seinfeld-only.

## Risks

| Risk | Mitigation |
|------|------------|
| Show title mismatch vs Jellyfin | Match exact library names (`The Office (US)`) |
| Seinfeld 24/7 schedule still points at wrong SC | Out of scope; do not rewrite ch 53 |
