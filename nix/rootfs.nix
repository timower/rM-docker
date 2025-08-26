{
  lib,
  fetchurl,
  runCommand,

  libguestfs-with-appliance,
  qemu,
  cpio,

  versions,
  extractor,
}:
{
  rootfs = builtins.mapAttrs (
    fw_version: info:
    let
      inherit (info) fileName fileHash;

      base_url = "https://updates-download.cloud.remarkable.engineering/build/reMarkable%20Device%20Beta/RM110"; # Default URL for v2 versions
      base_url_v3 = "https://updates-download.cloud.remarkable.engineering/build/reMarkable%20Device/reMarkable2";

      isNewFormat = (builtins.compareVersions fw_version "3.11.2.5") == 1;

      url =
        if isNewFormat then
          "https://storage.googleapis.com/remarkable-versions/${fileName}"
        else if (builtins.compareVersions fw_version "3.0.0.0") == 1 then
          "${base_url_v3}/${fw_version}/${fw_version}_reMarkable2-${fileName}.signed"
        else
          "${base_url}/${fw_version}/${fw_version}_reMarkable2-${fileName}.signed";

      updateArchive = fetchurl {
        inherit url;
        sha256 = fileHash;
      };

      rootfsImageOld = runCommand "rm-rootfs.ext4" { nativeBuildInputs = [ extractor ]; } ''
        extractor ${updateArchive} $out
      '';

      rootfsImageNew = runCommand "rm-rootfs.ext4" { nativeBuildInputs = [ cpio ]; } ''
        cpio -i --file ${updateArchive}
        gzip -dc ${lib.strings.removeSuffix ".swu" fileName}.ext4.gz > $out
      '';

      rootfsImage = if isNewFormat then rootfsImageNew else rootfsImageOld;

    in
    runCommand "rm-${fw_version}.qcow2"
      {
        nativeBuildInputs = [
          qemu
          libguestfs-with-appliance
        ];

        passthru.fw_version = fw_version;
      }
      ''
        ${../make_rootfs.sh} ${rootfsImage} ${fw_version}
        mv rootfs.qcow2 $out
      ''
  ) versions;
}
