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
    # /etc/profile.d (verified on a running system — /etc/profile has no such
    # loop), so this is the hook that actually runs.
    programs.bash.interactiveShellInit = ''
      if [ -z "''${DEPANNIX_GREETED:-}" ] && [ -t 1 ]; then
        export DEPANNIX_GREETED=1
        cat ${discovery.greetingText}
      fi
    '';

    # The same greeting on the serial console, and *before* the readiness
    # marker, so the boot test asserts it: what the operator sees on the
    # console is otherwise the one part of this image nothing verifies.
    systemd.services.depannix-greet = {
      description = "Announce what this medium is";
      wantedBy = [ "multi-user.target" ];
      before = [ "depannix-ready.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        cat ${discovery.greetingText} > /dev/ttyS0 || true
        cat ${discovery.greetingText} > /dev/console || true
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
