# install-nix-darwin

A GitHub Action that **bootstraps and activates a [nix-darwin][nix-darwin]
configuration on macOS runners**, so you can test your macOS system config in
CI the same way you'd run `darwin-rebuild switch` locally.

There are plenty of actions that install *Nix* (e.g. [cachix/install-nix-action][cachix]),
but none that take the next step and activate *nix-darwin*. Every project
doing this today hand-rolls the bootstrap steps. This action packages them.

## What it does

1. Obtains `darwin-rebuild` from a flake reference (it isn't on `PATH` before the
   first activation).
2. Backs up `/etc/nix/nix.conf`, `/etc/bashrc`, `/etc/zshrc`, `/etc/zprofile`, and
   `/etc/zshenv` (as `<file>.before-nix-darwin`) if they exist and aren't already
   managed by nix-darwin. nix-darwin refuses to overwrite these unless their
   content matches one of its known installer hashes, which a fresh runner's Nix
   install often won't. See [Notes for your nix-darwin config](#notes-for-your-nix-darwin-config).
3. Runs `darwin-rebuild switch` against either a **flake** or a **channel-based
   `configuration.nix`**.

Runs on `macos-*` runners only.

## Prerequisite: install Nix first

**This action does not install Nix.** It requires `nix` to already be on `PATH`,
installed by an earlier step. Bring whichever installer you prefer. That keeps
its (many) configuration knobs on the installer action instead of duplicating
them here. Flakes don't need to be enabled, but the action passes
`--extra-experimental-features "nix-command flakes"` for bootstrapping nix-darwin.

For example:

```yaml
- uses: cachix/install-nix-action@v31
```

See [Determinate Nix](#determinate-nix) below if you're using
DeterminateSystems/nix-installer-action instead.

## Usage

### Flake-based config

```yaml
jobs:
  darwin:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v7
      - uses: cachix/install-nix-action@v31 # install Nix first (prerequisite)
      - uses: eureka-cpu/nix-darwin-installer@v1
        with:
          flake: .#ci # <flake-ref>#<darwinConfigurations attr>
      - run: hello # a package your config installed
```

### Channel-based config

```yaml
      - uses: cachix/install-nix-action@v31
      - uses: eureka-cpu/nix-darwin-installer@v1
        with:
          config-file: ./machines/ci/configuration.nix
```

## Inputs

| Input                | Default                                  | Description |
| -------------------- | ---------------------------------------- | ----------- |
| `flake`              | `''`                                     | Flake ref to activate, e.g. `.#hostname`. Mutually exclusive with `config-file`. |
| `config-file`        | `''`                                     | Path to a channel-based `configuration.nix`. Mutually exclusive with `flake`. |
| `command`            | `switch`                                 | `darwin-rebuild` subcommand: `switch`, `build`, or `check`. |
| `nix-darwin-ref`     | `github:nix-darwin/nix-darwin`           | Flake ref used to fetch the `darwin-rebuild` bootstrap binary. |
| `nixpkgs-channel`    | `nixpkgs-unstable`                       | nixpkgs channel for channel-based installs. |
| `nix-darwin-channel` | `.../nix-darwin/archive/master.tar.gz`   | nix-darwin channel tarball for channel-based installs. |
| `extra-args`         | `''`                                     | Extra args appended to the `darwin-rebuild` call. |
| `github-token`       | `${{ github.token }}`                    | Token for `github.com` access-tokens (avoids API rate limits). |
| `use-sudo`           | `true`                                   | Run `darwin-rebuild` under `sudo` (required to activate a system). |

## Outputs

| Output   | Description |
| -------- | ----------- |
| `system` | Path the activated `/run/current-system` points to. |

## Zero-config default

If you provide neither `flake` nor `config-file`, the action activates its own
bundled default configuration: `system.primaryUser = "runner"`,
`nixpkgs.hostPlatform = "aarch64-darwin"`, `nix.enable = false`, and a pinned
`system.stateVersion`. This is useful as a bare smoke test of the action
itself, without writing any Nix. See
[`modules/default.nix`](./modules/default.nix).

## Linux builder

nix-darwin can provision a [Linux builder][linux-builder] VM
(`nix.linux-builder`), which is what lets `pkgs.testers`/NixOS VM tests
evaluate on a Darwin host instead of being gated behind
`lib.optionalAttrs (!stdenv.isDarwin)`. **This doesn't work on GitHub-hosted
runners, shared or the paid larger tiers.** The builder boots its own VM via
Apple's Virtualization framework, which is also what virtualizes the runner
itself, and per [GitHub's own docs][github-hosted-runners], nested
virtualization isn't supported there. It'll likely fail to start
without erroring loudly, since the launchd job that boots it starts async in
the background. It does work on a self-hosted runner on real Apple Silicon
hardware you control, since nothing's nested there. Because of that, the
bundled default configuration doesn't enable it.

If you're on hardware where it applies, this is what enabling it looks like:

```nix
nix = {
  enable = true;
  settings.trusted-users = [ "root" "@admin" ];
  linux-builder.enable = true;
  linux-builder.ephemeral = true;
};
```

`nix.linux-builder.enable` requires `nix.enable`. nix-darwin recognizes
`/etc/nix/nix.conf` written by cachix/install-nix-action, so it layers its
own settings on top instead of fighting it. This does not work with the
Determinate installer either, see [Determinate Nix](#determinate-nix) below.

This leaves the VM at `pkgs.darwin.linux-builder`'s own defaults (1 core,
3 GB RAM, 20 GB disk), raise `cores`/`memorySize`/`diskSize` under
`nix.linux-builder.config.virtualisation` to match your hardware.

## Determinate Nix

This repo doesn't test against, or specifically support, the Determinate
installer. Per [Determinate's own docs][determinate-nix-darwin], nix-darwin
doesn't work correctly under Determinate unless you import their nix-darwin
module and configure nix-darwin through it, since Determinate's own daemon
manages the Nix install and conflicts with nix-darwin doing the same. That
only matters if you set `nix.enable = true` yourself, e.g. for
[Linux builder](#linux-builder) support. The bundled default configuration
sets `nix.enable = false` and doesn't hit this. Either way, getting
Determinate working correctly with nix-darwin is out of scope here, better
left to Determinate's own docs than half-supported by this action.

If you want to use the Determinate installer with nix-darwin, follow their
docs exactly for your own flake or config-file. This action just activates
whatever you give it.

## Notes for your nix-darwin config

Because Nix is managed by the installer, set `nix.enable = false;` so
nix-darwin doesn't fight the daemon config, unless you need `nix.linux-builder`
(see [Linux builder](#linux-builder) above), which requires the opposite.
GitHub's Apple-Silicon runners use the `runner` user, so
`system.primaryUser = "runner";` and `nixpkgs.hostPlatform = "aarch64-darwin";`.
See [`examples/`](./examples) for minimal flake and channel-based configs that
pass CI.

These settings live in [`modules/default.nix`](./modules/default.nix), a
plain nix-darwin module (not tied to a flake) that the examples above import
directly. Copy or import it from a checkout of this repo if you want the same
defaults in your own config.

[nix-darwin]: https://github.com/nix-darwin/nix-darwin
[cachix]: https://github.com/cachix/install-nix-action
[linux-builder]: https://github.com/nix-darwin/nix-darwin/blob/master/modules/nix/linux-builder.nix
[github-hosted-runners]: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
[determinate-nix-darwin]: https://docs.determinate.systems/guides/nix-darwin/
