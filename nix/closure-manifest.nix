# ISO composition manifest.
#
# Publishes the exhaustive list of store paths baked into the image, with their
# hash. This is the piece that makes the promise "you can prove the contents"
# verifiable: anyone can compare this manifest against their own store, or
# against cache.nixos.org, without trusting whoever ran the build.
#
# Data source: Nix itself. `exportReferencesGraph` injects the complete graph as
# JSON into `$NIX_ATTRS_JSON_FILE` at instantiation time. We therefore do NOT
# call `nix path-info`: that one requires access to the store database, which
# the sandbox refuses ("Permission denied" on /nix/var/nix/profiles). This is
# the method `closureInfo` uses in nixpkgs, and the only one that works in CI.
#
# Every file name carries the flavour and the system, e.g.
# `closure-minimal-x86_64-linux.json`. Two architectures and two flavours all
# publish into the same release, and identical names meant the manifests
# silently overwrote each other: the published one described an unstated
# architecture and flavour, and did not necessarily match the ISO next to it.
{ pkgs, toplevel, flavour }:

let
  # The closure differs per flavour and per architecture, so the manifest does
  # too. Naming the files after both is what keeps them from colliding, and it
  # is what tells a reader which ISO they can verify with them.
  system = pkgs.stdenv.hostPlatform.system;
  suffix = "${flavour}-${system}";

  # The jq filters and the explanatory text live in separate files rather than
  # inline: inside a Nix `''` string every apostrophe would have to be written
  # `'''`, which makes the expression unreadable and fragile.
  jsonFilter = pkgs.writeText "depannix-closure.jq" ''
    .depannix
    | map({path, narHash, narSize, references})
    | sort_by(.path)
  '';

  pathsFilter = pkgs.writeText "depannix-paths.jq" ''
    .depannix[].path
  '';

  # Exact format expected by `nix-store --load-db`.
  registrationFilter = pkgs.writeText "depannix-registration.jq" ''
    .depannix
    | map([.path, .narHash, .narSize, "", (.references | length)] + .references)
    | add
    | map("\\(.)\n")
    | add
  '';

  sizeFilter = pkgs.writeText "depannix-total.jq" ''
    .depannix | map(.narSize) | add
  '';

  readme = pkgs.writeText "depannix-readme.txt" ''
    Verifying the Dépannix ${flavour} manifest for ${system}
    ==============================================================

    Every file name carries the flavour and the architecture, because the
    closure differs between both: this set describes the ${flavour} ISO for
    ${system}, and no other. The desktop image is a different, much larger
    closure, published under its own name.

    1. Hashes are provided in two encodings, so that no conversion is needed:

         - `closure-${suffix}.json` -> `.narHash`, in Nix base32 (`sha256:...`);
         - `closure-sri-${suffix}.tsv` -> column 2, in SRI/base64
           (`sha256-...=`), the format returned by narinfo files.

       Both denote the same value. The first is literally comparable to a
       narinfo, the second to the output of `nix path-info`.

    2. Verify the packages that came from nixpkgs, without Nix and without
       rebuilding anything - a plain GET, no trust required:

         awk '!/^#/ {print $1}' closure-sri-${suffix}.tsv | while read -r p; do
           h=$(basename "$p")
           curl -s "https://cache.nixos.org/''${h%%-*}.narinfo" \
             | sed -n 's/^NarHash: //p'
         done

       Compare each value against the matching `narHash` in
       `closure-${suffix}.json`.

       Coverage, measured on the minimal x86_64-linux image: 719 paths out of
       777. The rest are locally derived (the NixOS system itself, generated
       /etc files, systemd units): they exist in no binary cache, so no tool can
       confirm them. The count differs per architecture and per flavour - re-run
       the loop to measure yours.

    3. For those paths, only rebuilding is authoritative. Rebuilding the image
       from the same sources must reproduce the same `MANIFEST-${suffix}.sha256`,
       to the byte.

    4. Rebuild the local store database, then verify every hash:

         nix-store --load-db < nix-path-registration-${suffix}.txt

    5. Check the integrity of the manifest itself:

         sha256sum -c MANIFEST-${suffix}.sha256

    `total-nar-size-${suffix}.txt` gives the total weight of the closure in
    bytes.
  '';
in
pkgs.runCommand "depannix-closure-manifest-${flavour}"
  {
    # Required for `$NIX_ATTRS_JSON_FILE` to exist.
    __structuredAttrs = true;
    exportReferencesGraph.depannix = [ toplevel ];
    nativeBuildInputs = [ pkgs.jq pkgs.coreutils pkgs.nix ];
    preferLocalBuild = true;
  }
  ''
    mkdir -p $out
    attrs="$NIX_ATTRS_JSON_FILE"

    # Detailed, stable manifest: path, narHash, size, references.
    # `-S` sorts the keys and the filter sorts entries by path, so two builds of
    # the same system produce the same bytes.
    jq -S -f ${jsonFilter} < "$attrs" > $out/closure-${suffix}.json

    # Bare path list, for one-liner comparisons.
    jq -r -f ${pathsFilter} < "$attrs" | sort > $out/store-paths-${suffix}.txt

    # SRI form, directly comparable with a narinfo from cache.nixos.org:
    # `nix hash convert` is a pure computation, it does not touch the store
    # database and therefore passes the sandbox.
    {
      printf '# path\tnarHash (SRI)\tnarSize\n'
      paste \
        <(jq -r -f ${pathsFilter} < "$attrs") \
        <(jq -r '.depannix[].narHash' < "$attrs" \
          | xargs nix --extra-experimental-features nix-command \
                  hash convert --from nix32 --to sri) \
        <(jq -r '.depannix[].narSize' < "$attrs")
    } > $out/closure-sri-${suffix}.tsv

    # Registration in `nix-store --load-db` format: lets a third party rebuild
    # the store database and verify every hash locally.
    jq -r -f ${registrationFilter} < "$attrs" | head -n -1 \
      > $out/nix-path-registration-${suffix}.txt

    # Total weight of the closure, in bytes.
    jq -f ${sizeFilter} < "$attrs" > $out/total-nar-size-${suffix}.txt

    cp ${readme} $out/README-${suffix}.txt

    # Fingerprint of the manifest itself: the value to pin in a release, and the
    # one a third party compares after rebuilding the image.
    sha256sum $out/closure-${suffix}.json $out/store-paths-${suffix}.txt \
      $out/closure-sri-${suffix}.tsv \
      > $out/MANIFEST-${suffix}.sha256

    echo "flavour : ${flavour}"
    echo "system  : ${system}"
    echo "paths   : $(wc -l < $out/store-paths-${suffix}.txt)"
    echo "NAR size: $(cat $out/total-nar-size-${suffix}.txt) bytes"
    echo "manifest:"
    cat $out/MANIFEST-${suffix}.sha256
  ''
