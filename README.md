# halley-flake

Nix flake for [Halley](https://github.com/saltnpepper97/halley) — spatial Wayland compositor.

## Usage

```nix
{
  inputs.halley.url = "github:binarylinuxx/halley-flake";
}
```

```bash
nix build .#halley-stable      # v0.4.0 release
nix build .#halley-unstable    # latest main branch
nix build .#default            # same as unstable
```

## Packages

| Package | Source | Extras |
|---|---|---|
| `halley-stable` | v0.4.0 tag | halley, halleyctl |
| `halley-unstable` | main branch | + xdg-desktop-portal-halley |

Both install session files, systemd units, portal config, and D-Bus services.

## Install

### NixOS (flake)

```nix
{
  inputs.halley.url = "github:binarylinuxx/halley-flake";

  outputs = { self, nixpkgs, halley, ... }: {
    nixosConfigurations.mybox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ config, pkgs, ... }: {
          environment.systemPackages = [
            halley.packages.${pkgs.system}.halley-unstable
          ];
        })
      ];
    };
  };
}
```

### User profile (non-NixOS)

```bash
nix profile install github:binarylinuxx/halley-flake#halley-unstable
```

After installation, select **Halley** from your display manager session list, or run `halley-session` from a TTY.
