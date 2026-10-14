{
  description = "Dépannix — environnement de rescue NixOS : ISO minimale, reproductible et vérifiable";

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

      # Version CalVer. Le bot mensuel la réécrit (voir .github/workflows/monthly.yml).
      version = "2026.10";

      mkIso = system: extra: (lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          { depannix.version = version; }
          extra
        ];
      }).config.system.build.isoImage;

      # Saveur de référence : la plus petite, sans interface graphique.
      # Compression zstd-19 : bon rapport taille/temps, contrairement à xz.
      isoMinimal = system: mkIso system {
        depannix.squashfsCompression = "zstd -Xcompression-level 19";
      };

      # Même contenu, compression rapide : pour itérer en local et pour le test
      # de boot en CI (on ne paie pas 10 min de compression pour vérifier un boot).
      isoMinimalFast = system: mkIso system {
        depannix.squashfsCompression = "zstd -Xcompression-level 3";
      };

      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Arguments QEMU communs, tirés du système cible.
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

      # Lance l'ISO dans QEMU, en interactif (`nix run`) ou en test (`MARKER=`).
      mkRunVm = system:
        let
          pkgs = pkgsFor system;
          iso = isoMinimalFast system;
          env = qemuEnv system;
        in
        pkgs.writeShellScriptBin "depannix-vm" ''
          set -euo pipefail
          # ISO= déjà fourni par l'appelant (ex. une release à tester) : on ne
          # l'écrase pas, sinon il est impossible de tester un ISO donné.
          export ISO="''${ISO:-$(find ${iso}/iso -name '*.iso' | head -1)}"
          export QEMU="${env.QEMU}"
          export MACHINE="${env.MACHINE}"
          export OVMF_FIRMWARE="${env.OVMF_FIRMWARE}"
          export MODE="''${MODE:-bios}"
          exec ${pkgs.bash}/bin/bash ${./nix/qemu-run.sh}
        '';

      # Test de boot : on attend un marqueur écrit sur la console série.
      mkBootTest = system: mode:
        let
          pkgs = pkgsFor system;
          iso = isoMinimalFast system;
          env = qemuEnv system;
        in
        pkgs.runCommand "depannix-boot-test-${mode}" {
          nativeBuildInputs = [ pkgs.qemu_kvm pkgs.bash ];
          # mode « test » : marqueur attendu et délai borné
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
          echo "mode=$MODE" > $out/result
        '';

      # Manifeste de composition : la liste exhaustive des chemins du store
      # présents dans l'ISO, avec leur hachage. C'est la preuve vérifiable.
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

      # Garde-fou : l'ISO ne doit pas dériver en taille sans qu'on le voie.
      # Budget 1800 MiB — la cible est ~1,3-1,5 GiB (firmware complet inclus).
      mkSizeBudget = system:
        let
          pkgs = pkgsFor system;
          iso = isoMinimal system;
        in
        pkgs.runCommand "depannix-size-budget" { } ''
          iso="$(find ${iso}/iso -name '*.iso' | head -1)"
          size=$(stat -c%s "$iso")
          budget=$((1800 * 1024 * 1024))
          printf 'taille=%s octets (%s MiB), budget=%s octets (%s MiB)\n' \
            "$size" "$((size / 1048576))" "$budget" "$((budget / 1048576))"
          if [ "$size" -gt "$budget" ]; then
            echo "ÉCHEC : l'ISO dépasse le budget de taille." >&2
            echo "Voir docs/budget.md — ajouter un outil sans mesurer sa closure est la cause habituelle." >&2
            exit 1
          fi
          echo "OK" > $out
        '';
    in
    {
      # Le module réutilisable : c'est lui qui permet d'ajouter plus tard une
      # entrée de boot « Dépannix » sur une machine installée.
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
        # Bios + EFI : les deux chemins de firmware sont couverts.
        # Attention : KVM est requis, sinon QEMU retombe en TCG et le test
        # mettra des dizaines de minutes. Le workflow CI vérifie /dev/kvm.
        boot-test-bios = mkBootTest system "bios";
        boot-test-efi = mkBootTest system "efi";
        size-budget = mkSizeBudget system;
      });

      formatter = lib.genAttrs systems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
