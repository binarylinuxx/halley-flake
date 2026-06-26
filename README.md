# halley-flake

Nix flake for [Halley](https://github.com/saltnpepper97/halley) — spatial Wayland compositor.

## Usage

```nix
{
  inputs.halley.url = "github:your-user/halley-flake";
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
