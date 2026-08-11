# install-nix-darwin

A GitHub Action that **bootstraps and activates a [nix-darwin][nix-darwin]
configuration on macOS runners**, so you can test your macOS system config in
CI the same way you'd run `darwin-rebuild switch` locally.

There are plenty of actions that install *Nix* ([cachix/install-nix-action][cachix],
[DeterminateSystems/nix-installer-action][determinate]), but none that take the
next step and activate *nix-darwin*. Every project doing this today hand-rolls
the bootstrap steps. This action packages them.

## What it does

1. Obtains `darwin-rebuild` from a flake reference (it isn't on `PATH` before the
   first activation).
2. Runs `darwin-rebuild switch` against either a **flake** or a **channel-based
   `configuration.nix`**.

Runs on `macos-*` runners only.

## Prerequisite: install Nix first

**This action does not install Nix.** It requires `nix` to already be on `PATH`,
installed by an earlier step. Bring whichever installer you prefer. That keeps
its (many) configuration knobs on the installer action instead of duplicating
them here. Flakes must be enabled; the action also passes
`--extra-experimental-features "nix-command flakes"` as a safety net.

Any of these work:

```yaml
- uses: cachix/install-nix-action@v31
  with:
    extra_nix_config: |
      experimental-features = nix-command flakes
# or
- uses: DeterminateSystems/nix-installer-action@main
```

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
| `command`            | `switch`                                 | `darwin-rebuild` subcommand: `switch`, `build`, `check`, `activate`. |
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
[bundled default configuration](./modules/default.nix).

## Linux builder

The main reason to run this action in CI is `pkgs.testers` now works on
macOS, which means a NixOS VM test in your flake needs a
[Linux builder][linux-builder] to evaluate on a Darwin runner. Without one,
people typically gate those checks behind `lib.optionalAttrs (!stdenv.isDarwin)`
or similar so `nix flake check` doesn't fail on macOS. This action lets you
provision the builder in CI instead, so you accommodate the builder rather
than accommodating your expression around its absence. The bundled default
configuration enables it:

```nix
nix = {
  enable = true;
  settings.trusted-users = [ "root" "@admin" ];
  linux-builder.enable = true;
  linux-builder.ephemeral = true;
};
```

`nix.linux-builder.enable` requires `nix.enable`. nix-darwin recognizes
`/etc/nix/nix.conf` written by cachix/install-nix-action or the Determinate
installer, so it layers its own settings on top instead of fighting them.

This deliberately leaves the VM at `pkgs.darwin.linux-builder`'s own defaults
(1 core, 3 GB RAM, 20 GB disk) rather than sizing it up. GitHub's standard
macOS runners only have 3 vCPUs and 14 GB RAM, and historically as little as
~14-18 GB free disk, so there isn't much room to spare. If you're on a larger
runner or self-hosted hardware, raise `cores`/`memorySize`/`diskSize` under
`nix.linux-builder.config.virtualisation` to match. Also check that the
runner supports nested virtualization for the builder VM to boot at all;
GitHub's shared macOS runners may not.

## Notes for your nix-darwin config

GitHub's Apple-Silicon runners use the `runner` user, so
`system.primaryUser = "runner";` and `nixpkgs.hostPlatform = "aarch64-darwin";`.
See [`examples/`](./examples) for minimal flake and channel-based configs that
pass CI.

These settings, plus the Linux builder config above, live in
[`modules/default.nix`](./modules/default.nix), a plain nix-darwin module
(not tied to a flake) that the examples above import directly. Copy or import
it from a checkout of this repo if you want the same defaults in your own
config.

[nix-darwin]: https://github.com/nix-darwin/nix-darwin
[cachix]: https://github.com/cachix/install-nix-action
[determinate]: https://github.com/DeterminateSystems/nix-installer-action
[linux-builder]: https://github.com/nix-darwin/nix-darwin/blob/master/modules/nix/linux-builder.nix
