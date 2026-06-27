{
  description = "Halley – Spatial Wayland compositor built around infinite workspace navigation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    halley-stable-src = {
      url = "github:saltnpepper97/halley/v0.4.0";
      flake = false;
    };
    halley-unstable-src = {
      url = "github:binarylinuxx/halley/fix-drm-syncobj-blocker-wakeup";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, flake-utils, halley-stable-src, halley-unstable-src }:
    let
      nixosModule = { pkgs, lib, config, ... }: let
        halleyPkgs = self.packages.${pkgs.system};
      in {
        options.programs.halley = {
          enable = lib.mkEnableOption "Halley Wayland compositor";
          package = lib.mkOption {
            type = lib.types.package;
            default = halleyPkgs.halley-unstable;
            description = "Halley package to use";
          };
        };
        config = lib.mkIf config.programs.halley.enable {
          environment.systemPackages = [ config.programs.halley.package ];

          # Portal config: prefer Halley for ScreenCast/Screenshot, GTK for the rest
          environment.etc."xdg/xdg-desktop-portal/halley-portals.conf".source =
            "${config.programs.halley.package}/share/xdg-desktop-portal/halley-portals.conf";
        };
      };
    in flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        commonBuildInputs = with pkgs; [
          wayland
          libxkbcommon
          libdrm
          libgbm
          libglvnd
          libinput
          seatd
          systemd
          vulkan-loader
          libxcursor
          fontconfig
        ];

        commonNativeBuildInputs = with pkgs; [
          pkg-config
          wayland
          wayland-protocols
          clang
        ];

        mkHalley =
          { pname, version, src, cargoLock
          , extraBuildInputs ? [ ]
          , extraNativeBuildInputs ? [ ]
          , runtimeLibs ? [ ]
          , meta
          , doCheck ? true
          }:
          pkgs.rustPlatform.buildRustPackage {
            inherit pname version src cargoLock meta doCheck;

            nativeBuildInputs = commonNativeBuildInputs ++ extraNativeBuildInputs
              ++ [ pkgs.makeWrapper ];

            buildInputs = commonBuildInputs ++ extraBuildInputs;

            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

            postInstall = let
              runtimePath = pkgs.lib.makeLibraryPath runtimeLibs;
            in ''
              wrapProgram $out/bin/halley \
                --prefix LD_LIBRARY_PATH : ${runtimePath}
              wrapProgram $out/bin/halleyctl \
                --prefix LD_LIBRARY_PATH : ${runtimePath}

              if [ -f "$out/bin/xdg-desktop-portal-halley" ]; then
                wrapProgram $out/bin/xdg-desktop-portal-halley \
                  --prefix LD_LIBRARY_PATH : ${runtimePath}
              fi

              # Session files
              install -Dm755 $src/packaging/wayland-sessions/halley-session -t $out/bin
              install -Dm644 $src/packaging/wayland-sessions/halley.desktop \
                $out/share/wayland-sessions/halley.desktop

              # Patch hardcoded /usr/bin paths in session launcher
              substituteInPlace $out/bin/halley-session \
                --replace-fail '/usr/bin/halley' "$out/bin/halley"


              # Portal backend config
              if [ -d "$src/packaging/xdg-desktop-portal" ]; then
                mkdir -p $out/share/xdg-desktop-portal/portals
                cp -t $out/share/xdg-desktop-portal/portals \
                  $src/packaging/xdg-desktop-portal/portals/halley.portal 2>/dev/null || true
                cp -t $out/share/xdg-desktop-portal \
                  $src/packaging/xdg-desktop-portal/halley-portals.conf 2>/dev/null || true
              fi

              # D-Bus activation for portal
              if [ -d "$src/packaging/dbus-1/services" ]; then
                mkdir -p $out/share/dbus-1/services
                cp -t $out/share/dbus-1/services \
                  $src/packaging/dbus-1/services/*.service
                substituteInPlace $out/share/dbus-1/services/*.service \
                  --replace-fail '/usr/bin/' "$out/bin/"
              fi

              # systemd user units
              if [ -d "$src/packaging/systemd-user" ]; then
                mkdir -p $out/lib/systemd/user
                cp -t $out/lib/systemd/user \
                  $src/packaging/systemd-user/halley.service \
                  $src/packaging/systemd-user/halley-shutdown.target

                # Patch hardcoded /usr/bin paths in systemd units
                substituteInPlace $out/lib/systemd/user/halley.service \
                  --replace-fail '/usr/bin/halley' "$out/bin/halley"
              fi
            '';
          };
      in
      {
        packages = rec {
          halley-stable = mkHalley {
            pname = "halley";
            version = "0.4.0";
            src = halley-stable-src;
            cargoLock = {
              lockFile = halley-stable-src + "/Cargo.lock";
            };
            doCheck = false;
            runtimeLibs = with pkgs; [ libglvnd libgbm mesa ];
            meta = with pkgs.lib; {
              description =
                "Spatial Wayland compositor built around infinite workspace navigation";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              maintainers = [ ];
              mainProgram = "halley";
            };
          };

          halley-unstable = mkHalley {
            pname = "halley";
            version = "0.5.0";
            src = halley-unstable-src;
            cargoLock = {
              lockFile = halley-unstable-src + "/Cargo.lock";
              outputHashes = {
                "smithay-0.7.0" =
                  "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
              };
            };
            extraBuildInputs = with pkgs; [ pipewire dbus ];
            doCheck = false;
            runtimeLibs = with pkgs; [ libglvnd libgbm mesa pipewire dbus ];
            extraNativeBuildInputs = [ ];
            meta = with pkgs.lib; {
              description =
                "Spatial Wayland compositor (unstable/git) built around infinite workspace navigation";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              maintainers = [ ];
              mainProgram = "halley";
            };
          };

          default = halley-unstable;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = self.packages.${system}.default;
            name = "halley";
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.halley-unstable ];
          nativeBuildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
          ];
          shellHook = ''
            export RUST_LOG=info
          '';
        };
      }
    ) // {
      nixosModules.default = nixosModule;
    };
}
