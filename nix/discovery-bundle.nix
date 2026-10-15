# What makes the medium describe itself. See docs/discovery.md.
#
# Three derivations, joined into one package:
#
#   data        the catalogue (text and JSON), the help, the greeting, the version
#   tool        the `depannix` command, with the data path baked in
#   completion  the bash completion, found through share/bash-completion
#
# Everything is generated from nix/tool-catalog.nix and help/help.txt, so the
# catalogue cannot drift from what ships: it *is* what ships.
{ pkgs, lib ? pkgs.lib, version, system, label, enabledOptional ? [ ] }:

let
  catalog = import ./tool-catalog.nix { inherit pkgs; };

  categoryTitles = {
    partitioning = "Partitioning and filesystems";
    recovery = "Data recovery and cloning";
    diagnostics = "Hardware diagnostics";
    benchmark = "Benchmarking";
    network = "Network";
    comfort = "Command-line comfort";
  };

  entries =
    map (e: e // { enabled = true; }) catalog.core
    ++ map (e: e // { enabled = builtins.elem e.name enabledOptional; }) catalog.optional;

  # Right-pad, so the generated text lines up in a terminal.
  pad =
    n: s:
    s
    + lib.concatStrings (
      lib.genList (_: " ") (if builtins.stringLength s < n then n - builtins.stringLength s else 0)
    );

  # ── The help: one authored file, split into subjects ──────────────────────
  # Separator: a line starting with "== ", then "slug | One-line title".
  helpRaw = builtins.readFile ../help/help.txt;

  subjects = map (
    block:
    let
      lines = lib.splitString "\n" block;
      parts = lib.splitString " | " (builtins.head lines);
    in
    {
      slug = builtins.head parts;
      title = lib.concatStringsSep " | " (builtins.tail parts);
      body = lib.removePrefix "\n" (lib.concatStringsSep "\n" (builtins.tail lines));
    }
  ) (builtins.filter (b: b != "") (lib.splitString "\n== " (lib.removePrefix "== " helpRaw)));

  helpIndexText =
    "Subjects covered. Each one is also a file, and the whole text is at\n"
    + "~/depannix-help.txt (or /iso/depannix-help.txt, from the stick itself).\n\n"
    + lib.concatMapStringsSep "\n" (s: "  ${pad 24 s.slug}${s.title}") subjects
    + "\n\n  depannix help <subject>     one of them, in full\n";

  helpFullText =
    "Dépannix ${version} - what to do about a failure (${system})\n\n"
    + helpIndexText
    + "\n"
    + lib.concatMapStringsSep "\n" (s: "== ${s.slug} | ${s.title}\n\n${s.body}\n") subjects;

  helpIndex = pkgs.writeText "depannix-help-index.txt" helpIndexText;
  helpFull = pkgs.writeText "depannix-help.txt" helpFullText;

  # ── The catalogue, as text and as JSON ────────────────────────────────────
  toolsText = pkgs.writeText "depannix-tools.txt" (
    "Dépannix ${version} - what this image carries (${system})\n\n"
    + "Grouped by capability, not by package. A tool marked \"not enabled here\"\n"
    + "is in the catalogue but costs more than the default build accepts;\n"
    + "`depannix missing <name>` says how to get it anyway.\n\n"
    + lib.concatMapStringsSep "\n\n" (
      cat:
      "${cat} - ${categoryTitles.${cat}}\n"
      + lib.concatMapStringsSep "\n" (
        e:
        "  ${e.name} - ${e.gesture}"
        + lib.optionalString (e ? figure) "  [${e.figure}]"
        + lib.optionalString (!e.enabled) "  (not enabled here)"
      ) (builtins.filter (e: e.category == cat) entries)
    ) catalog.categoryOrder
    + "\n"
  );

  toolsJson = pkgs.writeText "depannix-tools.json" (
    builtins.toJSON {
      inherit version system;
      nixpkgs = label;
      tools = map (
        e: { inherit (e) name category gesture enabled; } // lib.optionalAttrs (e ? figure) { inherit (e) figure; }
      ) entries;
    }
  );

  versionText = pkgs.writeText "depannix-version.txt" "Dépannix ${version} (${system}, nixpkgs ${label})\n";

  greetingText = pkgs.writeText "depannix-greeting.txt" ''
    Dépannix ${version} - minimal rescue image (${system})

    You are root on a live medium: nothing here survives a reboot.
      depannix tools        what this image carries
      depannix help         what to do about a failure (subjects, one per file)
      ~/depannix-help.txt   the same as a file, and on the stick at /iso
  '';

  # ── The package ───────────────────────────────────────────────────────────
  data = pkgs.runCommand "depannix-data-${version}" { } ''
    mkdir -p $out/share/depannix/help
    install -m444 ${toolsText} $out/share/depannix/tools.txt
    install -m444 ${toolsJson} $out/share/depannix/tools.json
    install -m444 ${versionText} $out/share/depannix/version.txt
    install -m444 ${greetingText} $out/share/depannix/greeting.txt
    install -m444 ${helpFull} $out/share/depannix/help.txt
    install -m444 ${helpIndex} $out/share/depannix/help/index.txt
    ${lib.concatMapStringsSep "\n" (
      s: "install -m444 ${pkgs.writeText "depannix-help-${s.slug}.txt" s.body} $out/share/depannix/help/${s.slug}.txt"
    ) subjects}
  '';

  tool = pkgs.runCommand "depannix-tool-${version}" { } ''
    mkdir -p $out/bin
    sed -e '1s|^#!/usr/bin/env bash$|#!${pkgs.bash}/bin/bash|' \
        -e 's|@DATA@|${data}/share/depannix|g' \
        ${./depannix.sh} > $out/bin/depannix
    chmod +x $out/bin/depannix
    # A build-time smoke test: a command that cannot even print its version
    # must not reach an ISO. Same rule as the boot test, at the smallest scale.
    $out/bin/depannix version > /dev/null
    $out/bin/depannix help > /dev/null
  '';

  completion = pkgs.runCommand "depannix-completion-${version}" { } ''
    mkdir -p $out/share/bash-completion/completions
    sed 's|@DATA@|${data}/share/depannix|g' ${./depannix.bash} > $out/share/bash-completion/completions/depannix
  '';
in
{
  # One package, so one entry in systemPackages carries the command, the data
  # and the completion together.
  bundle = pkgs.symlinkJoin {
    name = "depannix-discovery-${version}";
    paths = [
      tool
      data
      completion
    ];
  };

  inherit
    completion
    data
    greetingText
    helpFull
    helpIndex
    subjects
    tool
    toolsJson
    toolsText
    versionText
    ;
}
