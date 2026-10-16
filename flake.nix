{
  description = "Dépannix - NixOS rescue environment: a minimal, reproducible and verifiable ISO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # CalVer version. The monthly bot rewrites it (see .github/workflows/monthly.yml).
      version = "2026.10";

      # Two flavours, one flake. `minimal` is the reference: a console, with a
      # bare Wayland session available on demand. `desktop` adds GNOME and
      # Firefox, which is what makes it several times bigger. The tool catalogue
      # reads the flavour too, so neither image claims the other's contents.
      flavours = [
        "minimal"
        "desktop"
      ];

      mkSystem = system: flavour: extra: (lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          {
            depannix.version = version;
            depannix.flavour = flavour;
          }
          extra
        ];
      });

      mkIso =
        system: flavour: compression:
        (mkSystem system flavour { depannix.squashfsCompression = compression; }).config.system.build.isoImage;

      # Release flavours: zstd-19, a good size/time trade-off, unlike xz.
      isoMinimal = system: mkIso system "minimal" "zstd -Xcompression-level 19";
      isoDesktop = system: mkIso system "desktop" "zstd -Xcompression-level 19";

      # Same content, fast compression: to iterate locally and for the CI boot
      # test (we do not pay 10 minutes of compression to check a boot).
      isoMinimalFast = system: mkIso system "minimal" "zstd -Xcompression-level 3";
      isoDesktopFast = system: mkIso system "desktop" "zstd -Xcompression-level 3";

      isoRelease = system: flavour: if flavour == "minimal" then isoMinimal system else isoDesktop system;
      isoFast = system: flavour: if flavour == "minimal" then isoMinimalFast system else isoDesktopFast system;

      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # QEMU arguments, derived from the target system.
      qemuEnv =
        system:
        let
          pkgs = pkgsFor system;
        in
        if pkgs.stdenv.hostPlatform.isx86_64 then {
          QEMU = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
          MACHINE = "q35";
          OVMF_FIRMWARE = "${pkgs.OVMF.firmware}";
        } else {
          QEMU = "${pkgs.qemu_kvm}/bin/qemu-system-aarch64";
          MACHINE = "virt";
          OVMF_FIRMWARE = "${pkgs.AAVMF.firmware}";
        };

      # Boot the ISO in QEMU, interactively (`nix run`). GUI=1 gives it a VNC
      # display, which is the only way to watch a graphical session: the serial
      # console stays readable at the same time.
      mkRunVm =
        system: flavour:
        let
          pkgs = pkgsFor system;
          iso = isoFast system flavour;
          env = qemuEnv system;
        in
        pkgs.writeShellScriptBin "depannix-vm" ''
          set -euo pipefail
          # ISO= already supplied by the caller (e.g. a release to test): we do
          # not overwrite it, otherwise it is impossible to test a given ISO.
          export ISO="''${ISO:-$(find ${iso}/iso -name '*.iso' | head -1)}"
          export QEMU="${env.QEMU}"
          export MACHINE="${env.MACHINE}"
          export OVMF_FIRMWARE="${env.OVMF_FIRMWARE}"
          export MODE="''${MODE:-bios}"
          exec ${pkgs.bash}/bin/bash ${./nix/qemu-run.sh}
        '';

      # Boot test: we wait for a marker written to the serial console.
      #
      # GUI=1 additionally asserts that a Wayland session came up and that the
      # screen is not blank, by capturing the guest's framebuffer. That needs
      # KVM: software emulation of a desktop session is not worth waiting for.
      mkBootTest =
        system: flavour: mode: gui:
        let
          pkgs = pkgsFor system;
          iso = isoFast system flavour;
          env = qemuEnv system;
          # The minimal image has no display manager: the session starts when an
          # operator asks for it, so the test asks for it too, by typing the
          # command on the console. The desktop image logs itself in.
          guiCommand = if gui && flavour == "minimal" then "depannix gui" else "";
        in
        pkgs.runCommand "depannix-boot-test-${flavour}-${mode}${lib.optionalString gui "-gui"}"
          {
            nativeBuildInputs = [
              pkgs.qemu_kvm
              pkgs.bash
              # Only for the graphical test, and none of this reaches the ISO:
              # socat drives the QEMU monitor (keystrokes, screendump),
              # imagemagick checks that the captured screen is not blank.
              pkgs.socat
              pkgs.imagemagick
            ];
            # test mode: expected marker and bounded timeout
            MARKER = "DEPANNIX_READY";
            # A desktop session under software rendering takes its time; a
            # console boot does not.
            TIMEOUT = if gui then "1800" else "900";
            MODE = mode;
            GUI = if gui then "1" else "";
            GUI_COMMAND = guiCommand;
          }
          ''
            mkdir -p $out
            export ISO="$(find ${iso}/iso -name '*.iso' | head -1)"
            export QEMU="${env.QEMU}"
            export MACHINE="${env.MACHINE}"
            export OVMF_FIRMWARE="${env.OVMF_FIRMWARE}"
            cd $TMPDIR
            ${pkgs.bash}/bin/bash ${./nix/qemu-run.sh}
            cp serial.log $out/serial.log
            # The greeting is part of what this medium claims to be. Booting is
            # not enough: the boot test asserts what the console actually shows,
            # otherwise the one thing the operator reads is the one thing nothing
            # verifies.
            if ! grep -q 'depannix tools' $out/serial.log; then
              echo "FAIL: the greeting never reached the serial console." >&2
              exit 1
            fi
            # The greeting proves the banner rendered. This proves the command
            # inside the image actually ran, which is a different claim, and the
            # one that catches a broken script before a user does.
            if ! grep -q 'DEPANNIX_SELFTEST tools=' $out/serial.log; then
              echo "FAIL: the in-image self-test did not report on the serial console." >&2
              exit 1
            fi
            # And the readable copies have to be where the shell lands, not only
            # where the package lives: the self-test reports that too.
            if ! grep -q 'DEPANNIX_SELFTEST helpfiles readable' $out/serial.log; then
              echo "FAIL: the help files are not readable from the user's home." >&2
              exit 1
            fi
            # The image must say which flavour it is, and whether it carries a
            # session: that line is the difference between two builds that
            # otherwise look identical on the console.
            if ! grep -q "DEPANNIX_SELFTEST session=.* flavour=${flavour}" $out/serial.log; then
              echo "FAIL: the self-test did not report the flavour, or reported another one." >&2
              exit 1
            fi
            ${lib.optionalString gui ''
              # A session that announces itself: the marker is written by a
              # Wayland client that connected to the compositor, so it proves
              # more than a process having been started.
              if ! grep -q 'DEPANNIX_SESSION type=wayland' $out/serial.log; then
                echo "FAIL: no Wayland session reported itself on the serial console." >&2
                echo "--- what the session did report ---" >&2
                grep 'DEPANNIX_SESSION' $out/serial.log >&2 || echo "(nothing at all)" >&2
                echo "--- last 30 lines of the console ---" >&2
                tail -30 $out/serial.log >&2
                exit 1
              fi
            ''
            }
            ${lib.optionalString (gui && flavour == "desktop") ''
              # The desktop image makes exactly one promise about the disks: it
              # will not mount one. That is a setting, and a setting asserted in
              # a document is a hope; the session reads it back from the running
              # GNOME and this is where it is checked.
              if ! grep -q 'automount=false' $out/serial.log; then
                echo "FAIL: GNOME reports automount as something other than false." >&2
                grep -o 'DEPANNIX_SESSION.*' $out/serial.log >&2 || echo "(nothing at all)" >&2
                exit 1
              fi
            ''
            }
            ${lib.optionalString gui ''
              # And the session has to have drawn something. The marker above is
              # the real evidence - the session announced itself from inside, and
              # it only gets that far by talking to the compositor - so this is
              # the second question, and a weaker one: a session that started and
              # painted nothing leaves a screen as black as a machine that never
              # booted. The mean is over a Q16 quantum, so it is 0 exactly when
              # every pixel is 0.
              #
              # Know what this cannot catch: a session that failed and left the
              # console on screen still has a mean above zero, because the console
              # is not black, it is nearly black. The marker is what the check
              # rests on; this is what makes a black screen loud.
              if [ ! -f session.png ]; then
                echo "FAIL: the session screenshot is missing." >&2
                exit 1
              fi
              cp session.png $out/session.png
              cp session.ppm $out/session.ppm
              mean=$(identify -format '%[mean]' session.png 2>/dev/null || echo 0)
              echo "screenshot mean: $mean" > $out/screenshot-mean.txt
              if [ "''${mean%%.*}" -le 0 ]; then
                echo "FAIL: the session screenshot is entirely black (mean $mean)." >&2
                exit 1
              fi
            ''
            }
            echo "mode=$MODE flavour=${flavour} gui=''${GUI:-0}" > $out/result
          '';

      # Composition manifest: the exhaustive list of store paths present in the
      # ISO, with their hash. This is the verifiable proof, and it is per flavour
      # because the two images share almost nothing.
      mkClosureManifest =
        system: flavour:
        let
          pkgs = pkgsFor system;
          toplevel = (mkSystem system flavour { }).config.system.build.toplevel;
        in
        pkgs.callPackage ./nix/closure-manifest.nix { inherit toplevel flavour; };

      # Guard rail: an ISO must not drift in size without anyone noticing.
      #
      # Measured, not hoped for. The minimal image carried 1517 MiB as a console
      # image and carries 1721 MiB on x86_64, 1739 MiB on aarch64, now that it can
      # start a Wayland session: 79 and 61 MiB of margin, which is the price of
      # that decision quoted in the currency the guard below uses. The desktop
      # image carries a browser and a desktop environment, and needs its own,
      # much higher ceiling. See docs/budget.md.
      budgets = {
        minimal = 1800;
        desktop = 3800;
      };

      mkSizeBudget =
        system: flavour:
        let
          pkgs = pkgsFor system;
          iso = isoRelease system flavour;
        in
        pkgs.runCommand "depannix-size-budget-${flavour}" { } ''
          iso="$(find ${iso}/iso -name '*.iso' | head -1)"
          size=$(stat -c%s "$iso")
          budget=$(( ${toString budgets.${flavour}} * 1024 * 1024 ))
          printf 'flavour=%s size=%s bytes (%s MiB), budget=%s bytes (%s MiB)\n' \
            "${flavour}" "$size" "$((size / 1048576))" "$budget" "$((budget / 1048576))"
          if [ "$size" -gt "$budget" ]; then
            echo "FAIL: the ${flavour} ISO exceeds its size budget." >&2
            echo "See docs/budget.md - adding a tool without measuring its closure is the usual cause." >&2
            exit 1
          fi
          echo "OK" > $out
        '';
    in
    {
      # The reusable module: it is what will later allow adding a "Dépannix"
      # boot entry to an installed machine.
      nixosModules.default = ./modules/default.nix;
      nixosModules.depannix = self.nixosModules.default;

      packages = lib.genAttrs systems (system: {
        default = isoMinimal system;
        minimal = isoMinimal system;
        minimal-fast = isoMinimalFast system;
        desktop = isoDesktop system;
        desktop-fast = isoDesktopFast system;

        # One manifest and one guard per flavour, written out rather than
        # generated: `lib.genAttrs` produces one attribute per name, which nests
        # here instead of merging, and the nesting was silently dropped by the
        # merge below. Two flavours do not need a combinator.
        closure-manifest-minimal = mkClosureManifest system "minimal";
        closure-manifest-desktop = mkClosureManifest system "desktop";
        size-budget-minimal = mkSizeBudget system "minimal";
        size-budget-desktop = mkSizeBudget system "desktop";
      });

      apps = lib.genAttrs systems (system: {
        default = {
          type = "app";
          program = "${mkRunVm system "minimal"}/bin/depannix-vm";
        };
        vm = {
          type = "app";
          program = "${mkRunVm system "minimal"}/bin/depannix-vm";
        };
        vm-desktop = {
          type = "app";
          program = "${mkRunVm system "desktop"}/bin/depannix-vm";
        };
      });

      checks = lib.genAttrs systems (system: {
        # BIOS + EFI on the reference flavour: both firmware paths covered.
        # Careful: KVM is required, otherwise QEMU falls back to TCG and the
        # test takes tens of minutes. The CI workflow checks /dev/kvm.
        boot-test-minimal-bios = mkBootTest system "minimal" "bios" false;
        boot-test-minimal-efi = mkBootTest system "minimal" "efi" false;

        # The graphical tests. The desktop flavour is tested in BIOS mode only:
        # it is the firmware path the graphical stack changes least, and the EFI
        # path is covered by the minimal flavour. Said plainly in docs/design.md
        # rather than left to be discovered.
        session-minimal-bios = mkBootTest system "minimal" "bios" true;
        boot-test-desktop-bios = mkBootTest system "desktop" "bios" true;

        size-budget-minimal = mkSizeBudget system "minimal";
        size-budget-desktop = mkSizeBudget system "desktop";
      });

      formatter = lib.genAttrs systems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
