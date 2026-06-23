# helium-macos

macOS packaging for [Helium Reimplemented](https://github.com/keetsta/helium-reimplemented),
a personal fork of [Helium](https://github.com/imputnet/helium).

## Credits

This repo is based on
[ungoogled-chromium-macos](https://github.com/ungoogled-software/ungoogled-chromium-macos)
and on [Helium's macOS packaging](https://github.com/imputnet/helium-macos). Thanks to
everyone behind ungoogled-chromium, who made working with Chromium far easier.

## License
All code, patches, modified portions of imported code or patches, and
any other content that is unique to Helium and not imported from other
repositories is licensed under GPL-3.0. See [LICENSE](LICENSE).

Any content imported from other projects retains its original license (for
example, any original unmodified code imported from ungoogled-chromium remains
licensed under their [BSD 3-Clause license](LICENSE.ungoogled_chromium)).

## Building

The upstream, Homebrew-based build is documented in [docs/building.md](docs/building.md).

This fork is normally built through helper scripts that use a **contained
toolchain** (its own Python venv, ninja and greadlink) so nothing is installed
globally. They expect this repo and the toolchain to live side by side:

```
<root>/
  helium-reimplemented-macos/   ← this repo (the scripts live here)
  toolchain/                    ← contained toolchain, provides env.fork.sh
```

Everything else (Chromium source, downloads, `out/`) lands in `build/`, which is
git-ignored. Run the scripts from inside the repo:

| Script | What it does |
| --- | --- |
| `./fork-build [arch]` | Full clean RELEASE build: download Chromium, apply patches, compile (PGO), sign & package a `.dmg`. Hours. Also stamps the fork-sync marker. |
| `./fork-rebuild` | Fast incremental rebuild (ninja) + repackage. Use after changing source/patches already in `build/src`. Minutes. |
| `./fork-sync [-r] [-n]` | Pull new core/platform commits and apply only the **patch delta** to `build/src`, so a `fork-rebuild` picks them up without a full rebuild. `-r` runs `fork-rebuild` after; `-n` previews via a read-only fetch. Refuses (→ run `fork-build`) when a delta isn't safe. |
| `./fork-wipe-profile [-y] [-n]` | Wipe ONLY this fork's data (`net.imput.helium.reimplemented`) for a clean onboarding test. Never touches stock Helium; refuses while the fork is running. |
| `./dev.sh` | Misc local dev helpers. |

Typical loops:

- First build (any machine): `./fork-build` — also writes the `fork-sync` marker.
- After pushing core from another machine: `./fork-sync -r`.
- Testing onboarding: quit the fork, `./fork-wipe-profile -y`, relaunch the `.app`.

> `fork-sync` only handles patch-file deltas. Build-affecting non-patch changes
> (`deps.ini`, substitution lists, `*.gn`, resources) or patches that no longer
> apply cleanly make it stop and tell you to run a full `./fork-build`.
