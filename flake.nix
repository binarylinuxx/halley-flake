{
  description = "Halley – Spatial Wayland compositor built around infinite workspace navigation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    halley-stable-src = {
      url = "github:saltnpepper97/halley/v0.5.0";
      flake = false;
    };

    halley-unstable-src = {
      url = "github:saltnpepper97/halley/main";
      flake = false;
    };

    halley-unstable-dev-src = {
      url = "github:saltnpepper97/halley/dev";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      halley-stable-src,
      halley-unstable-src,
      halley-unstable-dev-src,
    }:
    let
      nixosModule =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          halleyPkgs = self.packages.${pkgs.system};
        in
        {
          options.programs.halley = {
            enable = lib.mkEnableOption "Halley Wayland compositor";

            package = lib.mkOption {
              type = lib.types.package;
              default = halleyPkgs.halley-unstable;
              description = "Halley package to use";
            };
          };

          config = lib.mkIf config.programs.halley.enable {
            environment.systemPackages = [
              config.programs.halley.package
            ];

            services.displayManager.sessionPackages = [
              config.programs.halley.package
            ];

            environment.etc."xdg/xdg-desktop-portal/halley-portals.conf".source =
              "${config.programs.halley.package}/share/xdg-desktop-portal/halley-portals.conf";
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (
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
          makeWrapper
        ];

        mkHalley =
          {
            pname,
            version,
            src,
            cargoLock,
            extraBuildInputs ? [ ],
            runtimeLibs,
            meta,
            doCheck ? false,
          }:
          pkgs.rustPlatform.buildRustPackage {
            inherit
              pname
              version
              src
              cargoLock
              meta
              doCheck
              ;

            nativeBuildInputs = commonNativeBuildInputs;
            buildInputs = commonBuildInputs ++ extraBuildInputs;

            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

            postInstall =
              let
                runtimePath = pkgs.lib.makeLibraryPath runtimeLibs;
              in
              ''
                wrapProgram "$out/bin/halley" \
                  --prefix LD_LIBRARY_PATH : "${runtimePath}"

                wrapProgram "$out/bin/halleyctl" \
                  --prefix LD_LIBRARY_PATH : "${runtimePath}"

                wrapProgram "$out/bin/xdg-desktop-portal-halley" \
                  --prefix LD_LIBRARY_PATH : "${runtimePath}"

                install -Dm755 \
                  "$src/packaging/wayland-sessions/halley-session" \
                  "$out/bin/halley-session"

                install -Dm644 \
                  "$src/packaging/wayland-sessions/halley.desktop" \
                  "$out/share/wayland-sessions/halley.desktop"

                substituteInPlace "$out/bin/halley-session" \
                  --replace-fail "/usr/bin/halley" "$out/bin/halley"

                substituteInPlace "$out/share/wayland-sessions/halley.desktop" \
                  --replace-fail "Exec=/usr/bin/halley-session" \
                    "Exec=$out/bin/halley-session"

                install -Dm644 \
                  "$src/packaging/xdg-desktop-portal/portals/halley.portal" \
                  "$out/share/xdg-desktop-portal/portals/halley.portal"

                install -Dm644 \
                  "$src/packaging/xdg-desktop-portal/halley-portals.conf" \
                  "$out/share/xdg-desktop-portal/halley-portals.conf"

                install -Dm644 \
                  "$src/packaging/dbus-1/services/"*.service \
                  -t "$out/share/dbus-1/services"

                substituteInPlace "$out/share/dbus-1/services/"*.service \
                  --replace-fail "/usr/bin/" "$out/bin/"

                install -Dm644 \
                  "$src/packaging/systemd-user/halley.service" \
                  "$out/lib/systemd/user/halley.service"

                install -Dm644 \
                  "$src/packaging/systemd-user/halley-shutdown.target" \
                  "$out/lib/systemd/user/halley-shutdown.target"

                substituteInPlace "$out/lib/systemd/user/halley.service" \
                  --replace-fail "/usr/bin/halley" "$out/bin/halley"
              '';

            passthru.providedSessions = [ "halley" ];
          };
      in
      {
        packages = rec {
          halley-stable = mkHalley {
            pname = "halley";
            version = "0.5.0";
            src = halley-stable-src;

            cargoLock.lockFile = halley-stable-src + "/Cargo.lock";

            runtimeLibs = with pkgs; [
              libglvnd
              libgbm
              mesa
            ];

            meta = with pkgs.lib; {
              description =
                "Spatial Wayland compositor built around infinite workspace navigation";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "halley";
            };
          };

          halley-unstable = mkHalley {
            pname = "halley";
            version = "0.5.0-unstable";
            src = halley-unstable-src;

            cargoLock = {
              lockFile = halley-unstable-src + "/Cargo.lock";

              outputHashes = {
                "smithay-0.7.0" =
                  "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
              };
            };

            extraBuildInputs = with pkgs; [
              pipewire
              dbus
            ];

            runtimeLibs = with pkgs; [
              libglvnd
              libgbm
              mesa
              wayland
              pipewire
              dbus
            ];

            meta = with pkgs.lib; {
              description =
                "Spatial Wayland compositor from the main branch";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "halley";
            };
          };

          halley-unstable-dev = mkHalley {
            pname = "halley";
            version = "0.5.0-dev";
            src = halley-unstable-dev-src;

            cargoLock = {
              lockFile = halley-unstable-dev-src + "/Cargo.lock";

              outputHashes = {
                "smithay-0.7.0" =
                  "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
              };
            };

            extraBuildInputs = with pkgs; [
              pipewire
              dbus
            ];

            runtimeLibs = with pkgs; [
              libglvnd
              libgbm
              mesa
              wayland
              pipewire
              dbus
            ];

            meta = with pkgs.lib; {
              description =
                "Spatial Wayland compositor from the development branch";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "halley";
            };
          };

          default = halley-unstable;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "halley";
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            self.packages.${system}.halley-unstable
          ];

          nativeBuildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
          ];

          RUST_LOG = "info";
        };
      }
    )
    // {
      nixosModules.default = nixosModule;
    };
}
