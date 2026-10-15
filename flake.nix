{
  description = "Dépannix — NixOS rescue environment: a minimal, reproducible and verifiable ISO";

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

      mkIso = system: extra: (lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          { depannix.version = version; }
          extra
        ];
      }).config.system.build.isoImage;

      # Reference flavour: the smallest one, no graphical interface.
      # zstd-19 compression: a good size/time trade-off, unlike xz.
      isoMinimal = system: mkIso system {
        depannix.squashfsCompression = "zstd -Xcompression-level 19";
      };

      # Same content, fast compression: to iterate locally and for the CI boot
      # test (we do not pay 10 minutes of compression to check a boot).
      isoMinimalFast = system: mkIso system {
        depannix.squashfsCompression = "zstd -Xcompression-level 3";
      };

      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # QEMU arguments, derived from the target system.
      qemuEnv = system:
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

      # Boot the ISO in QEMU, interactively (`nix run`) or as a test (`MARKER=`).
      mkRunVm = system:
        let
          pkgs = pkgsFor system;
          iso = isoMinimalFast system;
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
      mkBootTest = system: mode:
        let
          pkgs = pkgsFor system;
          iso = isoMinimalFast system;
          env = qemuEnv system;
        in
        pkgs.runCommand "depannix-boot-test-${mode}" {
          nativeBuildInputs = [ pkgs.qemu_kvm pkgs.bash ];
          # test mode: expected marker and bounded timeout
          MARKER = "DEPANNIX_READY";
          TIMEOUT = "900";
          MODE = mode;
        } ''
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
          echo "mode=$MODE" > $out/result
        '';

      # Composition manifest: the exhaustive list of store paths present in the
      # ISO, with their hash. This is the verifiable proof.
      mkClosureManifest = system:
        let
          pkgs = pkgsFor system;
          toplevel = (lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              { depannix.version = version; }
            ];
          }).config.system.build.toplevel;
        in
        pkgs.callPackage ./nix/closure-manifest.nix { inherit toplevel; };

      # Guard rail: the ISO must not drift in size without anyone noticing.
      # Budget 1800 MiB — the target is ~1.3-1.5 GiB (full firmware included).
      mkSizeBudget = system:
        let
          pkgs = pkgsFor system;
          iso = isoMinimal system;
        in
        pkgs.runCommand "depannix-size-budget" { } ''
          iso="$(find ${iso}/iso -name '*.iso' | head -1)"
          size=$(stat -c%s "$iso")
          budget=$((1800 * 1024 * 1024))
          printf 'size=%s bytes (%s MiB), budget=%s bytes (%s MiB)\n' \
            "$size" "$((size / 1048576))" "$budget" "$((budget / 1048576))"
          if [ "$size" -gt "$budget" ]; then
            echo "FAIL: the ISO exceeds its size budget." >&2
            echo "See docs/budget.md — adding a tool without measuring its closure is the usual cause." >&2
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
        closure-manifest = mkClosureManifest system;
        size-budget = mkSizeBudget system;
      });

      apps = lib.genAttrs systems (system: {
        default = {
          type = "app";
          program = "${mkRunVm system}/bin/depannix-vm";
        };
        vm = {
          type = "app";
          program = "${mkRunVm system}/bin/depannix-vm";
        };
      });

      checks = lib.genAttrs systems (system: {
        # BIOS + EFI: both firmware paths are covered.
        # Careful: KVM is required, otherwise QEMU falls back to TCG and the
        # test takes tens of minutes. The CI workflow checks /dev/kvm.
        boot-test-bios = mkBootTest system "bios";
        boot-test-efi = mkBootTest system "efi";
        size-budget = mkSizeBudget system;
      });

      formatter = lib.genAttrs systems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
