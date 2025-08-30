{
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # System types to support.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"

        # guestfish doesn't support darwin
        # "x86_64-darwin"
        # "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages."${system}";

          kernel = pkgs.callPackage ./nix/kernel.nix { };

          versions = import ./nix/versions.nix { inherit (nixpkgs) lib; };

          extractor = pkgs.callPackage ./nix/extractor.nix { };

          allRootFs = (pkgs.callPackage ./nix/rootfs.nix { inherit versions extractor; }).rootfs;

          allRootFs' = nixpkgs.lib.mapAttrs' (
            version: rootfs: nixpkgs.lib.nameValuePair "rootfs-${version}" rootfs
          ) allRootFs;

          mkEmu = pkgs.callPackage ./nix/rm-emu.nix;
          allEmus = nixpkgs.lib.mapAttrs' (
            version: rootfs:
            nixpkgs.lib.nameValuePair "rm-emu-${version}" (mkEmu {
              inherit kernel rootfs;
            })
          ) allRootFs;

          dockerImages = nixpkgs.lib.mapAttrs' (
            _: pkg:
            nixpkgs.lib.nameValuePair "docker-${pkg.version}" (
              pkgs.dockerTools.streamLayeredImage {
                name = "rm-emu";
                tag = "${pkg.version}";
                contents = [
                  pkg
                  pkgs.dockerTools.binSh
                  pkgs.dockerTools.fakeNss
                ];

                config = {
                  Cmd = [ "${pkg}/bin/run_vm" ];
                };
              }
            )
          ) allEmus;
        in
        {
          inherit kernel extractor;
          default = allEmus."rm-emu-3.20.0.92";
        }
        // allEmus
        // allRootFs'
        // dockerImages
      );
    };
}
