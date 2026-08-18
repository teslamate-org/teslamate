{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Refreshes the fixed-output hashes pinned in the flake modules.
      #
      # A fixed-output derivation is addressed by its hash alone, so a stale
      # hash resolves to the store path that was fetched for it earlier: the
      # build succeeds, the fetcher never runs and nothing reports a mismatch,
      # while the old content is silently used. Building and waiting for an
      # error therefore finds nothing. Each pinned hash is instead invalidated
      # on purpose, one at a time, and the hash the fetcher then reports is
      # written back. Every run consequently re-fetches, which is the price of
      # an answer that does not depend on what happens to sit in the store.
      #
      # The files to patch are looked up by their pinned hashes rather than
      # named here, so neither renaming a module nor pinning a further
      # fixed-output derivation elsewhere needs a change to this script.
      packages.update-nix-hashes = pkgs.writeShellApplication {
        name = "update-nix-hashes";
        runtimeInputs = [
          pkgs.nix
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = ''
          # lib.fakeHash. Its output can never be a valid store path, so a
          # derivation pinned to it always runs and always reports what it got.
          # Assembled at run time rather than written out, so that the search
          # for pinned hashes below does not find this file's own placeholder.
          fake="sha256-$(printf 'A%.0s' {1..43})="

          # Anchored on the flake, because that is what the build resolves
          # against.
          if [ ! -f flake.nix ]; then
            echo "run this from the project root (no flake.nix here)" >&2
            exit 1
          fi

          log="$(mktemp)"
          patched="$(mktemp)"
          restore=1
          saved_files=()
          saved_copies=()

          save() {
            local file="$1" copy known
            for known in ''${saved_files[@]+"''${saved_files[@]}"}; do
              if [ "$known" = "$file" ]; then
                return 0
              fi
            done
            copy="$(mktemp)"
            cp "$file" "$copy"
            saved_files+=("$file")
            saved_copies+=("$copy")
          }

          cleanup() {
            local i
            if [ "$restore" -eq 1 ] && [ ''${#saved_files[@]} -gt 0 ]; then
              echo "restoring the hashes this run had replaced" >&2
              for i in "''${!saved_files[@]}"; do
                cat "''${saved_copies[$i]}" > "''${saved_files[$i]}"
              done
            fi
            rm -f "$log" "$patched" ''${saved_copies[@]+"''${saved_copies[@]}"}
          }
          trap cleanup EXIT

          # Writes through a temporary file rather than with sed -i, which is
          # not portable, and copies it back so the source file keeps its mode
          # instead of the one mktemp created.
          replace() {
            sed "s|$2|$3|" "$1" > "$patched"
            cat "$patched" > "$1"
          }

          mapfile -t pins < <(grep -rEo 'sha256-[A-Za-z0-9+/]{43}=' nix --include='*.nix' | sort -u)
          if [ ''${#pins[@]} -eq 0 ]; then
            echo "no pinned hashes found below nix/" >&2
            exit 1
          fi

          for pin in "''${pins[@]}"; do
            file="''${pin%%:*}"
            hash="''${pin#*:}"

            # Two pins sharing one file and hash cannot be told apart once both
            # carry the placeholder, so refuse instead of updating them wrongly.
            occurrences="$(grep -cF "$hash" "$file")"
            if [ "$occurrences" -ne 1 ]; then
              echo "$file pins $hash on $occurrences lines, which cannot be updated independently" >&2
              exit 1
            fi

            save "$file"
            replace "$file" "$hash" "$fake"

            # --keep-going so that this fetch still finishes and reports its
            # hash when another fixed-output derivation mismatches first. That
            # happens whenever a second pinned hash is stale as well and its
            # output is not in the store, which is the normal state on a fresh
            # machine after a mix dependency bump.
            if nix build .#default --no-link --keep-going > "$log" 2>&1; then
              echo "expected $file to report a hash mismatch, but the build succeeded" >&2
              exit 1
            fi

            # Nix reports the pair as "specified: <hash>" followed by
            # "got: <hash>". With several mismatches in one log, taking the
            # first "got:" can pick another derivation's hash, so read the one
            # that follows the placeholder this iteration put in place.
            got="$(awk -v fake="$fake" '
              index($0, "specified:") && index($0, fake) { pending = 1; next }
              pending && index($0, "got:") { print $NF; exit }
            ' "$log" || true)"

            if ! printf '%s' "$got" | grep -qE '^sha256-[A-Za-z0-9+/]{43}=$'; then
              cat "$log" >&2
              echo "the build reported no hash for the placeholder in $file" >&2
              exit 1
            fi

            replace "$file" "$fake" "$got"
            if [ "$got" = "$hash" ]; then
              echo "$file: $hash is unchanged"
            else
              echo "$file: $hash -> $got"
            fi
          done

          # Past this point every hash was produced by a fetch that just ran, so
          # a later failure is not one this script should undo.
          restore=0

          if ! nix build .#default --no-link > "$log" 2>&1; then
            cat "$log" >&2
            echo "the hashes are up to date, but the build fails for another reason" >&2
            exit 1
          fi

          echo "all hashes are up to date"
        '';
      };
    };
}
