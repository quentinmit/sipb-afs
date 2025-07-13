{ config, lib, ... }:
let
  cfg = config.sipb.afs;
in {
  options = with lib; {
    sipb.afs = {
      enable = mkEnableOption "SIPB AFS server";
    };
  };
  config = lib.mkIf cfg.enable {
    networking.domain = "mit.edu";
    networking.firewall.enable = false;
    security.krb5 = {
      enable = true;
      settings = {
        libdefaults = {
          default_realm = "ATHENA.MIT.EDU";
        };
      };
    };
    services.openafsClient = {
      enable = true;
      cellName = "athena.mit.edu";
    };
    services.openafsServer = {
      enable = true;
      cellName = "sipb.mit.edu";
    };
    # Trust ATHENA.MIT.EDU as a local realm.
    environment.etc."openafs/server/krb.conf".text = ''
      ATHENA.MIT.EDU
    '';
  };
}
