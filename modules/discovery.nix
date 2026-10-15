# Making the medium describe itself: what it carries, what to do about a
# failure, and how to prove the content. See docs/discovery.md for the why.
{ config, lib, pkgs, ... }:

let
  cfg = config.depannix;

  discovery = import ../nix/discovery-bundle.nix {
    inherit pkgs;
    version = cfg.version;
    system = pkgs.stdenv.hostPlatform.system;
    label = config.system.nixos.label;
    enabledOptional = cfg.optionalTools;
  };
in
{
  config = {
    # The command, its data and its completion, as one package.
    environment.systemPackages = [ discovery.bundle ];

    # The greeting, once per interactive shell. Note: NixOS does not source
    # /etc/profile.d (verified on a running system, /etc/profile has no such
    # loop), so this is the hook that actually runs.
    programs.bash.interactiveShellInit = ''
      if [ -z "''${DEPANNIX_GREETED:-}" ] && [ -t 1 ]; then
        export DEPANNIX_GREETED=1
        cat ${discovery.greetingText}
      fi

      # A missing command is the most likely thing to be typed on this medium,
      # and plain "command not found" is a dead end when the catalogue can say
      # where the tool is and how to get it. NixOS's own command-not-found is
      # not in this image: its database would be the nixpkgs copy we do not ship.
      command_not_found_handle() {
        printf 'bash: %s: command not found\n' "$1" >&2
        ${discovery.bundle}/bin/depannix missing "$1" >&2 2>/dev/null || true
        return 127
      }
    '';

    # The same greeting on the serial console, and *before* the readiness
    # marker, so the boot test asserts it: what the operator sees on the
    # console is otherwise the one part of this image nothing verifies.
    systemd.services.depannix-greet = {
      description = "Announce what this medium is";
      wantedBy = [ "multi-user.target" ];
      before = [ "depannix-ready.service" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # The same files where the operator actually is. The shell lands in
        # /home/nixos, and a store path is not a place anyone browses.
        if [ -d /home/nixos ]; then
          ln -sf ${discovery.toolsText} /home/nixos/depannix-tools.txt
          ln -sf ${discovery.helpFull} /home/nixos/depannix-help.txt
          ln -sf ${discovery.versionText} /home/nixos/depannix-version
        fi

        cat ${discovery.greetingText} > /dev/ttyS0 || true
        cat ${discovery.greetingText} > /dev/console || true

        # A smoke test of the command surface, run inside the real image: the
        # boot test greps for this line, so a broken `depannix` fails CI rather
        # than the operator at 3 a.m. Every line is best-effort: a failed unit
        # here must not stop the medium from booting.
        tools=$(${discovery.bundle}/bin/depannix tools --json 2>/dev/null | jq -r '[.tools[] | select(.enabled)] | length' 2>/dev/null || echo 0)
        subjects=$(find ${discovery.data}/share/depannix/help -name '*.txt' ! -name index.txt 2>/dev/null | wc -l || echo 0)
        printf 'DEPANNIX_SELFTEST tools=%s subjects=%s\n' "$tools" "$subjects" > /dev/ttyS0 || true
        ${discovery.bundle}/bin/depannix missing phoronix-test-suite 2>&1 | head -2 > /dev/ttyS0 || true
      '';
    };

    # The same content as plain files on the medium, so a rescued machine can
    # read them without running anything: a store path is no help if the
    # machine you are rescuing cannot evaluate Nix.
    isoImage.contents = [
      {
        source = discovery.toolsText;
        target = "/depannix-tools.txt";
      }
      {
        source = discovery.helpFull;
        target = "/depannix-help.txt";
      }
    ];
  };
}
