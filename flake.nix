{
  description = "Halley – Spatial Wayland compositor built around infinite workspace navigation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    halley-stable-src = {
      url = "github:saltnpepper97/halley/v0.7.0";
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
      schemas = rec {
        stable = import ./halley-schema-stable.nix;
        unstable = import ./halley-schema-unstable.nix;
        dev = import ./halley-schema-dev.nix;
        default = unstable;
      };

      escapeRuneString =
        value: nixpkgs.lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] value;

      isRawRune = value: builtins.isAttrs value && value ? __raw;

      serializeRuneValue =
        value:
        if builtins.isString value then
          "\"${escapeRuneString value}\""
        else if builtins.isBool value then
          if value then "true" else "false"
        else if isRawRune value then
          value.__raw
        else if builtins.isList value then
          "[${nixpkgs.lib.concatMapStringsSep ", " serializeRuneValue value}]"
        else
          toString value;

      serializeRuneName =
        name:
        if nixpkgs.lib.strings.match "[A-Za-z][A-Za-z0-9-]*" name != null then
          name
        else
          serializeRuneValue name;

      serializeRuneEntry =
        indent: path: name: value:
        let
          renderedName = serializeRuneName name;
          isRepeatedDirective =
            (
              path == [ "autostart" ]
              && builtins.elem name [
                "once"
                "on-reload"
              ]
            )
            || (path == [ ] && name == "gather")
            || path == [ "keybinds" ];
        in
        if isRepeatedDirective && builtins.isList value then
          nixpkgs.lib.concatMapStringsSep "\n" (
            command: "${indent}${renderedName} ${serializeRuneValue command}"
          ) value
        else if isRawRune value then
          "${indent}${renderedName} ${value.__raw}"
        else if builtins.isAttrs value then
          "${indent}${renderedName}:\n${
            serializeRuneAttrs "${indent}  " (path ++ [ name ]) value
          }\n${indent}end"
        else if builtins.isList value && value != [ ] && builtins.all builtins.isAttrs value then
          nixpkgs.lib.concatMapStringsSep "\n" (entry: serializeRuneEntry indent path name entry) value
        else
          "${indent}${renderedName} ${serializeRuneValue value}";

      serializeRuneAttrs =
        indent: path: attrs:
        nixpkgs.lib.concatMapStringsSep "\n" (name: serializeRuneEntry indent path name attrs.${name}) (
          builtins.attrNames attrs
        );

      renderRune = settings: "${serializeRuneAttrs "" [ ] settings}\n";

      unknownRunePaths =
        schema: settings:
        let
          dynamicPaths = [
            "autostart"
            "env"
            "gather"
            "gamescope"
            "gaming"
            "input.devices"
            "input.gestures"
            "input.mouse"
            "input.touchpad"
            "keybinds"
            "rules"
            "viewport"
          ];
          isDynamic =
            path:
            builtins.any (dynamic: path == dynamic || nixpkgs.lib.hasPrefix "${dynamic}." path) dynamicPaths;
          walk =
            path: value:
            let
              fullPath = nixpkgs.lib.concatStringsSep "." path;
              canonicalPath =
                if path != [ ] && builtins.head path == "node" then
                  nixpkgs.lib.concatStringsSep "." ([ "nodes" ] ++ builtins.tail path)
                else
                  fullPath;
              knownSection = builtins.elem canonicalPath schema.sections;
              knownScalar = builtins.elem canonicalPath schema.scalars;
            in
            if isRawRune value then
              [ ]
            else if builtins.isAttrs value then
              (nixpkgs.lib.optional (path != [ ] && !knownSection && !isDynamic fullPath) fullPath)
              ++ nixpkgs.lib.concatMap (name: walk (path ++ [ name ]) value.${name}) (builtins.attrNames value)
            else if builtins.isList value && value != [ ] && builtins.all builtins.isAttrs value then
              nixpkgs.lib.concatMap (entry: walk path entry) value
            else
              nixpkgs.lib.optional (!knownScalar && !isDynamic fullPath) fullPath;
        in
        walk [ ] settings;

      runeTestDocument = renderRune {
        autostart.once = [
          "blxshell"
          "waybar"
        ];
        gather = [
          "colors.rune"
          "machines.rune"
        ];
        input = {
          keyboard = {
            layout = "us,ru";
            options = "grp:alt_shift_toggle";
          };
          gestures = {
            enabled = true;
            modifier = "$mod";
            swipe-threshold-px = 120;
          };
        };
        keybinds = {
          mod = "super";
          "$var.mod+return" = [
            "open-terminal"
            "spawn alacritty"
          ];
        };
        rules.rule = [
          {
            app-id = "firefox";
            title.__raw = ''[r"File Upload.*", r"Open File.*"]'';
          }
        ];
      };

      runeTestExpected = ''
        autostart:
          once "blxshell"
          once "waybar"
        end
        gather "colors.rune"
        gather "machines.rune"
        input:
          gestures:
            enabled true
            modifier "$mod"
            swipe-threshold-px 120
          end
          keyboard:
            layout "us,ru"
            options "grp:alt_shift_toggle"
          end
        end
        keybinds:
          "$var.mod+return" "open-terminal"
          "$var.mod+return" "spawn alacritty"
          mod "super"
        end
        rules:
          rule:
            app-id "firefox"
            title [r"File Upload.*", r"Open File.*"]
          end
        end
      '';

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

      homeModule =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.halley;
          schema = schemas.${cfg.package.passthru.halleySchema or "unstable"};
        in
        {
          options.programs.halley = {
            enable = lib.mkEnableOption "Halley Wayland compositor";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.halley-unstable;
              description = "Halley package to install and use for the session.";
            };

            settings = lib.mkOption {
              type = lib.types.nullOr lib.types.attrs;
              default = null;
              description = "Nix attribute set used to generate Halley's Rune configuration.";
            };

            config = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = if cfg.settings == null then null else renderRune cfg.settings;
              defaultText = lib.literalExpression "null";
              description = "Raw Rune configuration. When set, this overrides `programs.halley.settings`.";
            };

            finalConfig = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              readOnly = true;
              default = cfg.config;
              description = "The generated Halley Rune configuration.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];

            assertions = lib.optional (cfg.settings != null) {
              assertion = unknownRunePaths schema cfg.settings == [ ];
              message = "programs.halley.settings contains unsupported Halley options: ${lib.concatStringsSep ", " (unknownRunePaths schema cfg.settings)}";
            };

            xdg.configFile."halley/halley.rune" = lib.mkIf (cfg.finalConfig != null) {
              text = cfg.finalConfig;
            };
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        libdisplay-info-0_3 = pkgs.libdisplay-info.overrideAttrs (old: {
          version = "0.3.0";
          src = pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "emersion";
            repo = "libdisplay-info";
            rev = "47a5590e9c4eb35d67651b8c05a55f1a48259329";
            hash = "sha256-nXf2KGovNKvcchlHlzKBkAOeySMJXgxMpbi5z9gLrdc=";
          };
          postFixup = "";
        });

        commonBuildInputs = with pkgs; [
          wayland
          libxkbcommon
          libdrm
          libgbm
          libglvnd
          libinput
          libdisplay-info-0_3
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
            schemaName,
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

            cargoBuildFlags = [
              "--package"
              "halley"
              "--package"
              "halley-cli"
              "--package"
              "halley-portal"
            ];

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

                if grep -q "Exec=/usr/bin/halley-session" "$out/share/wayland-sessions/halley.desktop"; then
                  substituteInPlace "$out/share/wayland-sessions/halley.desktop" \
                    --replace-fail "TryExec=/usr/bin/halley-session" "TryExec=$out/bin/halley-session" \
                    --replace-fail "Exec=/usr/bin/halley-session" "Exec=$out/bin/halley-session"
                else
                  substituteInPlace "$out/share/wayland-sessions/halley.desktop" \
                    --replace-fail "TryExec=halley-session" "TryExec=$out/bin/halley-session" \
                    --replace-fail "Exec=halley-session" "Exec=$out/bin/halley-session"
                fi

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

            passthru = {
              providedSessions = [ "halley" ];
              halleySchema = schemaName;
            };
          };
      in
      {
        packages = rec {
          extract-halley-schema = pkgs.writeShellApplication {
            name = "extract-halley-schema";
            runtimeInputs = [ pkgs.python3 ];
            text = ''
              exec python ${./scripts/extract-halley-schema.py} "$@"
            '';
          };

          halley-stable = mkHalley {
            pname = "halley";
            version = "0.7.0";
            src = halley-stable-src;

            cargoLock = {
              lockFile = halley-stable-src + "/Cargo.lock";

              outputHashes = {
                "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
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
              seatd
              libinput
              libxkbcommon
              systemd
            ];

            schemaName = "stable";

            meta = with pkgs.lib; {
              description = "Spatial Wayland compositor built around infinite workspace navigation";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "halley";
            };
          };

          halley-unstable = mkHalley {
            pname = "halley";
            version = "0.7.0-unstable";
            src = halley-unstable-src;

            cargoLock = {
              lockFile = halley-unstable-src + "/Cargo.lock";

              outputHashes = {
                "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
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
              seatd
              libinput
              libxkbcommon
              systemd
            ];

            schemaName = "unstable";

            meta = with pkgs.lib; {
              description = "Spatial Wayland compositor from the main branch";
              homepage = "https://github.com/saltnpepper97/halley";
              license = licenses.gpl3Only;
              platforms = platforms.linux;
              mainProgram = "halley";
            };
          };

          halley-unstable-dev = mkHalley {
            pname = "halley";
            version = "0.7.0-dev";
            src = halley-unstable-dev-src;

            cargoLock = {
              lockFile = halley-unstable-dev-src + "/Cargo.lock";

              outputHashes = {
                "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
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
              seatd
              libinput
              libxkbcommon
              systemd
            ];

            schemaName = "dev";

            meta = with pkgs.lib; {
              description = "Spatial Wayland compositor from the development branch";
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

        apps.extract-halley-schema = flake-utils.lib.mkApp {
          drv = self.packages.${system}.extract-halley-schema;
          name = "extract-halley-schema";
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

        checks.rune-renderer = pkgs.runCommand "halley-rune-renderer" { } ''
          diff -u \
            ${builtins.toFile "halley-rune-expected.rune" runeTestExpected} \
            ${builtins.toFile "halley-rune-generated.rune" runeTestDocument}
          touch "$out"
        '';
      }
    )
    // {
      nixosModules.default = nixosModule;
      homeModules = {
        default = homeModule;
        halley = homeModule;
      };
      lib.halley.schemas = schemas;
    };
}
