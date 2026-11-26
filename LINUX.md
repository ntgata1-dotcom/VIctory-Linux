# VIctory on Linux

This repository is [VIctory](https://github.com/Marvisak/VIctory) with the fixes it needs on Linux merged in, and scripts for building and running it there. The title runs the same way it does on Windows: the Windows build of `victory.exe`, under Wine, with Direct3D 12 on Vulkan through vkd3d-proton.

You need your own copy of the game. Nothing from the game is in this repository, and nothing from it may be added (see [docs/asset-policy.md](docs/asset-policy.md); `cargo xtask policy` checks it).

## What is merged on top of upstream

Open upstream pull requests, merged with their original commits and authors:

| Upstream PR | What it does on Linux | Author |
|---|---|---|
| [#2913](https://github.com/Marvisak/VIctory/pull/2913) (carries [#1279](https://github.com/Marvisak/VIctory/pull/1279)) | The indirect-argument clamp is a shader Wine's own `d3dcompiler_47` can build. Without it every indirect draw is dropped and the world stays black | arogan178 (Andrea Bugeja), carrying Mumogg's #1279 |
| [#2919](https://github.com/Marvisak/VIctory/pull/2919) | The depth converter (16-bit depth the title writes through unordered views) is one Wine's compiler builds too | arogan178 (Andrea Bugeja) |
| [#2723](https://github.com/Marvisak/VIctory/pull/2723) (carries [#177](https://github.com/Marvisak/VIctory/pull/177)) | A resource read as float and used by an atomic gets a handle of each type, as the host needs. Merged for the startup abort in dxil-spirv (`Invalid type ID in cast<T>`) that current `main` hits under Wine; that it is the fix is not yet checked on its own | andyeox-systemd, with Ortomanic and gingertonik |
| [#2977](https://github.com/Marvisak/VIctory/pull/2977) | Loops are shaped as DXC shapes them, so dxil-spirv doesn't recurse until its stack runs out on 9 of the title's programs | neonbyte1 |
| [#2703](https://github.com/Marvisak/VIctory/pull/2703) | A root constant's fifth dword is a value, not a view offset, so those draws aren't dropped | Calvix2k |
| [#1722](https://github.com/Marvisak/VIctory/pull/1722) | The host pipeline library works under vkd3d-proton, so pipelines are kept between runs | Impre-visible |
| [#2101](https://github.com/Marvisak/VIctory/pull/2101) | The one castable format vkd3d-proton has no mapping for is left out, so it no longer refuses castable formats altogether | Deilach |
| [#2249](https://github.com/Marvisak/VIctory/pull/2249) | Two network functions Wine's `ws2_32` lacks fail cleanly instead of aborting | slaktarn, opened by desplmfao |
| [#2644](https://github.com/Marvisak/VIctory/pull/2644) | `VICTORY_STEP_OVER=63966f,5149aec` steps over the title's pool-full stop ([#698](https://github.com/Marvisak/VIctory/issues/698)). Here in release builds too, not only diagnostics ones | Pierrot1398 |
| [#454](https://github.com/Marvisak/VIctory/pull/454) | `VICTORY_NO_WATCHDOG=1` keeps the title's watchdog from ending a slow run ([#1118](https://github.com/Marvisak/VIctory/issues/1118)) | ruvenesh |
| [#2195](https://github.com/Marvisak/VIctory/pull/2195) | Tests: the library test's shaders compile with Wine's compiler | winne42 |
| [#2973](https://github.com/Marvisak/VIctory/pull/2973), six of its commits | Crash records stay whole under Wine; five tests that assumed Windows or one GPU | neonbyte1 |
| [#2334](https://github.com/Marvisak/VIctory/pull/2334) (carries [#1017](https://github.com/Marvisak/VIctory/pull/1017)) | The workspace builds, passes clippy and tests on Linux, for development | Jitheswar, carried by ntgata1-dotcom |

From other forks (GPL-3.0-or-later, as VIctory):

| Change | From | Author |
|---|---|---|
| A wave64 lane mask copied a dword at a time through scalar moves is still its compare's mask, so the program structures | [DexNom/VIctory](https://github.com/DexNom/VIctory) `76749ce`, adapted to upstream | DexNom |

Looked at and not taken, so nobody has to look again:

- **In-place title memory** (Belobug and its descendants, avatarmanz's speedups): under Wine the world goes black with it.
- **DexNom's ray-structure building**: it rests on the in-place memory above and a rewrite of the GPU memory code, not a change on its own.
- **uiliannn's barrier change**: it drops the thread-group sync of every barrier after any loop, so compute programs race.
- **uiliannn's submission chunking**: the indirect budget it cuts by 8 drops real draws.

## Status

Measured on one machine: Arch Linux, RX 9070 XT (RDNA4), RADV / Mesa 26.3, Wine 11.22, vkd3d-proton and DXVK `dxgi` from GE-Proton11-14.

- **Menus** run at the title's 30 fps.
- **The world** draws with #1279, which #2913 carries. Without it the world is black under Wine's own compiler. The first mission's cutscene shows streets, buildings, lights, characters and a car. Surfaces are unlit, characters show broken geometry, and frames took 3.1 s on average. [Measurements](https://github.com/Marvisak/VIctory/pull/1279#issuecomment-7168463210)
- **Runs end** about 7½ minutes into the world on the title's own `0x80000003`. [#698](https://github.com/Marvisak/VIctory/issues/698) reports the same stop on Windows.
- **This exact tree in the world:** not run yet. #1279's result was measured on an older `main`.
- **Tests:** on Linux, `cargo test --workspace` passes (457 tests). The Windows build's tests run under Wine pass 9 that fail on upstream `main` there. The 28 that fail on both need things Wine lacks. One timing test (`frame::tests::waits_end_on_ticks_and_count_frames`) can fail on a busy machine, on upstream too.

## Build

Requirements: Rust (the toolchain in `rust-toolchain.toml` installs itself), [cargo-xwin](https://github.com/rust-cross/cargo-xwin) (`cargo install --locked cargo-xwin`), clang and llvm, Wine (tested with 11.22), and a [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom) release for vkd3d-proton and DXVK.

```sh
linux/build.sh            # target/x86_64-pc-windows-msvc/release/victory.exe
linux/build.sh diag       # the diagnostics build (VICTORY_LOG and friends)
```

cargo-xwin downloads Microsoft's CRT and Windows SDK on first use, which means accepting Microsoft's license for them.

For working on VIctory itself, the workspace also builds natively: `cargo clippy --workspace --all-targets` and `cargo test --workspace` run on Linux. `cargo xtask install-hooks` makes every commit run the asset-policy check.

## Run

```sh
cp linux/env.example.sh linux/env.sh     # then edit the paths in it
linux/setup-prefix.sh ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-14-x86_64
linux/run.sh 1800                        # 30 minutes at most; logs in linux/logs/
```

- A run that hangs the GPU can take the desktop with it. Save your work first.
- `run.sh` caps the title's memory (`VICTORY_MEMORY_MAX`, 24G by default) and watches the kernel log for GPU errors.
- Without a controller, the keyboard is a pad while the window has focus: WASD and IJKL are the sticks, arrows the D-pad, Enter and Backspace A and B, Esc Menu. The full table is in [README.md](README.md).

## Troubleshooting

- **The world is black, and the log says `no argument clamp`:** Wine's compiler refused the clamp. This tree's clamp avoids that. If you use another build, install Microsoft's `d3dcompiler_47.dll` in the prefix (the second argument of `setup-prefix.sh`) and add `;d3dcompiler_47=n` to `WINEDLLOVERRIDES`.
- **The wrong GPU is used** on a machine with an integrated one: uncomment `VKD3D_FILTER_DEVICE_NAME` and `DXVK_FILTER_DEVICE_NAME` in `linux/env.sh`, and set them to part of your GPU's name.
- **vkd3d-proton crashes at start:** keep `VK_LOADER_LAYERS_DISABLE='~implicit~'`. Overlay and capture layers are the usual cause.

## Keeping up with upstream

```sh
git remote add upstream https://github.com/Marvisak/VIctory.git   # once
git fetch upstream && git merge upstream/main
```

When upstream merges one of the PRs above, its merge here becomes a no-op and its row can go.

## Credits

VIctory is by Marvisak and its contributors. The merged pull requests are by the authors in the table above. GPL-3.0-or-later, as upstream ([LICENSE](LICENSE)).
