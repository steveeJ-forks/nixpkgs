{ config, lib, pkgs, utils, ... }:

with utils;
with lib;

let

  swapCfg = {config, options, ...}: {

    options = {

      device = mkOption {
        example = "/dev/sda3";
        type = types.str;
        description = "Path of the device.";
      };

      label = mkOption {
        example = "swap";
        type = types.str;
        description = ''
          Label of the device.  Can be used instead of <varname>device</varname>.
        '';
      };

      size = mkOption {
        default = null;
        example = 2048;
        type = types.nullOr types.int;
        description = ''
          If this option is set, ‘device’ is interpreted as the
          path of a swapfile that will be created automatically
          with the indicated size (in megabytes) if it doesn't
          exist.
        '';
      };

      priority = mkOption {
        default = null;
        example = 2048;
        type = types.nullOr types.int;
        description = ''
          Specify the priority of the swap device. Priority is a value between 0 and 32767.
          Higher numbers indicate higher priority.
          null lets the kernel choose a priority, which will show up as a negative value.
        '';
      };

      randomEncryption = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Encrypt swap device with a random key. This way you won't have a persistent swap device.

          WARNING: Don't try to hibernate when you have at least one swap partition with
          this option enabled! We have no way to set the partition into which hibernation image
          is saved, so if your image ends up on an encrypted one you would lose it!
        '';
      };

      deviceName = mkOption {
        type = types.str;
        internal = true;
      };

      realDevice = mkOption {
        type = types.path;
        internal = true;
      };

    };

    config = rec {
      device = mkIf options.label.isDefined
        "/dev/disk/by-label/${config.label}";
      deviceName = escapeSystemdPath config.device;
      realDevice = if config.randomEncryption then "/dev/mapper/${deviceName}" else config.device;
    };

  };

in

{

  ###### interface

  options = {

    swapDevices = mkOption {
      default = [];
      example = [
        { device = "/dev/hda7"; }
        { device = "/var/swapfile"; }
        { label = "bigswap"; }
      ];
      description = ''
        The swap devices and swap files.  These must have been
        initialised using <command>mkswap</command>.  Each element
        should be an attribute set specifying either the path of the
        swap device or file (<literal>device</literal>) or the label
        of the swap device (<literal>label</literal>, see
        <command>mkswap -L</command>).  Using a label is
        recommended.
      '';

      type = types.listOf (types.submodule swapCfg);
    };

  };

  config = mkIf ((length config.swapDevices) != 0) {

    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isYes "SWAP")
    ];

    # Create missing swapfiles.
    # FIXME: support changing the size of existing swapfiles.
    systemd.services =
      let

        createSwapDevice = sw:
          assert sw.device != "";
          let realDevice' = escapeSystemdPath sw.realDevice;
          in nameValuePair "mkswap-${sw.deviceName}"
          { description = "Initialisation of swap device ${sw.device}";
            wantedBy = [ "${realDevice'}.swap" ];
            before = [ "${realDevice'}.swap" ];
            path = [ pkgs.utillinux ] ++ optional sw.randomEncryption pkgs.cryptsetup;
            script =
              ''
                ${optionalString (sw.size != null) ''
                  if [ ! -e "${sw.device}" ]; then
                    fallocate -l ${toString sw.size}M "${sw.device}" ||
                      dd if=/dev/zero of="${sw.device}" bs=1M count=${toString sw.size}
                    chmod 0600 ${sw.device}
                    ${optionalString (!sw.randomEncryption) "mkswap ${sw.realDevice}"}
                  fi
                ''}
                ${optionalString sw.randomEncryption ''
                  echo "secretkey" | cryptsetup luksFormat --batch-mode ${sw.device}
                  echo "secretkey" | cryptsetup luksOpen ${sw.device} ${sw.deviceName}
                  cryptsetup luksErase --batch-mode ${sw.device}
                  mkswap ${sw.realDevice}
                ''}
              '';
            unitConfig.RequiresMountsFor = [ "${dirOf sw.device}" ];
            unitConfig.DefaultDependencies = false; # needed to prevent a cycle
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = sw.randomEncryption;
            serviceConfig.ExecStop = optionalString sw.randomEncryption "cryptsetup luksClose ${sw.deviceName}";
          };

      in listToAttrs (map createSwapDevice (filter (sw: sw.size != null || sw.randomEncryption) config.swapDevices));

  };

}
