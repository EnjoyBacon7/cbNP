MediaRemote adapter source
==========================

This directory vendors the original MediaRemote adapter used by `cbNP`
in `MediaRemote` mode.

- Upstream repository: https://github.com/ungive/mediaremote-adapter
- Upstream path: `bin/mediaremote-adapter.pl` + build artifacts
- Synced commit: `6bbb7d3` (master)
- Sync date: 2026-02-27

Build/source notes:

- `mediaremote-adapter.pl` is taken from upstream `bin/mediaremote-adapter.pl`
- `MediaRemoteAdapter.framework` and `MediaRemoteAdapterTestClient` are built
  from that same upstream commit with CMake

Original adapter header notes:

- Copyright (c) 2025 Jonas van den Berg
- License: BSD 3-Clause
