{ lib, self, ... }:
{
  imports = [
    ./cell.nix
  ];
  name = lib.mkForce "cell-zfs";
  defaults = { config, nodes, ... }: {
    imports = [
      self.inputs.disko.nixosModules.disko
    ];
    # Create a 10G empty disk image
    virtualisation.emptyDiskImages = [ 10240 ];
    # Enable ZFS (only needed because tests override `fileSystems`)
    boot.supportedFilesystems.zfs = true;
    # ZFS requires a host ID
    networking.hostId = "00000000";
    # Enable scrub and snapshot services
    services.zfs = {
      autoScrub.enable = true;
      autoSnapshot.enable = true;
    };
    # Mount the disko-formatted disks at /
    disko.rootMountPoint = "/";
    # Define disks for disko to format and mount
    disko.devices = {
      disk.vicepa = {
        type = "disk";
        # The first empty disk image is at /dev/vdb (vda is mounted at /)
        device = "/dev/vdb";
        content = {
          type = "gpt";
          partitions.zfs = {
            content.type = "zfs";
            content.pool = "vicepa";
          };
        };
      };
      zpool.vicepa = {
        type = "zpool";
        rootFsOptions = {
          # TODO: Are these appropriate for AFS?
          xattr = "sa";
          compression = "lz4";
          acltype = "posixacl";
          dnodesize = "auto";
          relatime = "on";
          canmount = "off";
        };
        datasets.vicepa = {
          type = "zfs_fs";
          mountpoint = "/vicepa";
          options = {
            "com.sun:auto-snapshot" = "true";
          };
        };
      };
    };
    # At boot, before local-fs.target, format and mount /vicepa
    systemd.services.prepare-disks = {
      wants = [
        "systemd-udev-settle.service"
      ];
      after = [
        "systemd-udev-settle.service"
        "systemd-modules-load.service"
      ];
      requiredBy = [ "local-fs.target" ];
      before = [ "local-fs.target" ];
      unitConfig = {
        DefaultDependencies = "false";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe config.system.build.formatMount;
        RemainAfterExit = true;
      };
    };
  };
}
