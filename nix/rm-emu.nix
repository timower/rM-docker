{
  lib,
  # runCommand,
  makeWrapper,
  stdenvNoCC,

  qemu,
  openssh,
  netcat,
  gnugrep,
  coreutils,

  kernel,
  rootfs,

  # TODO: control ports
  sshPort ? 2222,
  httpPort ? 8080,

  # Commands to run in vm during build.
  nativeSetupCommands ? null,
  setupCommands ? null,
}:
let
  hasSetup = setupCommands != null || setupCommands != null;

  setupScript = lib.optionalString (hasSetup) ''
    export ROOT_IMAGE=$out/image.qcow2
    oldpath=$PATH
    export PATH=$out/bin:$PATH

    $out/bin/run_vm -daemonize
    $out/bin/wait_ssh
    ${lib.optionalString (nativeSetupCommands != null) nativeSetupCommands}
    ssh -p $SSH_PORT -o StrictHostKeyChecking=no root@localhost <<ENDSSH
      ${lib.optionalString (setupCommands != null) setupCommands}
    ENDSSH
    echo 'quit' | nc -N 127.0.0.1 5555

    export BACKING_IMAGE=$out/image.qcow2
    export PATH=$oldpath
  '';
in
stdenvNoCC.mkDerivation {
  pname = "rm-emu";
  version = rootfs.fw_version;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals (hasSetup) [
    qemu
    openssh
  ];

  src = ../bin;

  buildPhase = ''
    runHook preBuild

    mkdir -p $out/bin

    install -m 0555 ./run_vm $out/bin/run_vm
    install -m 0555 ./in_vm $out/bin/in_vm
    install -m 0555 ./wait_ssh $out/bin/wait_ssh
    install -m 0555 ./save_vm $out/bin/save_vm

    export KERNEL_PATH=${kernel}/zImage
    export DTB_PATH=${kernel}/dtbs/imx7d-rm.dtb
    export SSH_PORT=${toString sshPort}
    export BACKING_IMAGE=${rootfs}

    ${setupScript}
  '';

  installPhase = ''
    wrapProgram $out/bin/run_vm \
      --set BACKING_IMAGE $BACKING_IMAGE \
      --set KERNEL_PATH $KERNEL_PATH \
      --set DTB_PATH $DTB_PATH \
      --set SSH_PORT $SSH_PORT \
      --set PATH ${
        lib.makeBinPath [
          qemu
          gnugrep
        ]
      }

    wrapProgram $out/bin/in_vm \
      --set SSH_PORT ${toString sshPort} \
      --set PATH ${lib.makeBinPath [ openssh ]}

    wrapProgram $out/bin/wait_ssh --set PATH ${lib.makeBinPath [ coreutils ]}:$out/bin

    wrapProgram $out/bin/save_vm --set PATH ${lib.makeBinPath [ netcat ]}
  '';
}
