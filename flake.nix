{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ]
      (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          formatter = pkgs.nixpkgs-fmt;

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              bash
              bc
              binutils
              bison
              actionlint
              coreutils
              elfutils
              file
              findutils
              flex
              git
              gnumake
              jq
              libelf
              llvmPackages.bintools-unwrapped
              llvmPackages.clang-unwrapped
              llvmPackages.lld
              ncurses
              openssl
              pahole
              perl
              pkg-config
              python3
              rsync
              shellcheck
              which
              xz
              zlib.dev
              zstd
            ];

            hardeningDisable = [ "all" ];
          };
        });
}
