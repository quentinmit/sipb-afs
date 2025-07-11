{ lib, ... }:
{
  name = "cell";
  defaults = { config, nodes, ... }: let
    cellServDB = lib.mapAttrsToList (_: config: {
      ip = config.networking.primaryIPAddress;
      dnsname = "${config.networking.hostName}.${config.networking.domain}";
    }) nodes;
  in {
    config = {
      sipb.afs.enable = true;
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false; # Disable external connectivity
      services.openafsClient.cellServDB = lib.imap0 (i: entry: if i == 0 then {
        # Hack to set both athena and sipb in the CellServDB
        ip = ">sipb.mit.edu\n${entry.ip}";
        inherit (entry) dnsname;
      } else entry) cellServDB;
      services.openafsServer.cellServDB = cellServDB;
      security.krb5.settings.realms."ATHENA.MIT.EDU" = {
        admin_server = nodes.ra.networking.primaryIPAddress;
        kdc = [nodes.ra.networking.primaryIPAddress];
      };
    };
  };
  nodes = {
    ra = { config, pkgs, ... }: {
      services.kerberos_server = {
        enable = true;
        settings.realms."ATHENA.MIT.EDU".acl = [{
          principal = "admin";
          access = [
            "add"
            "cpw"
          ];
        }];
      };
    };
    rb = { config, pkgs, ... }: {
    };
  };
  testScript = ''
    import re

    def setup_kdc(machine):
      # Set up realm
      machine.succeed(
        "kdb5_util create -s -r ATHENA.MIT.EDU -P master_key",
        "systemctl restart kadmind.service kdc.service",
      )
      for unit in ["kadmind", "kdc"]:
        machine.wait_for_unit(f"{unit}.service")
      # Create admin and afs/ principals
      machine.succeed(
        "kadmin.local add_principal -pw admin_pw admin",
        "kadmin.local add_principal -randkey -e aes256-cts-hmac-sha1-96:normal,aes128-cts-hmac-sha1-96:normal afs/sipb.mit.edu",
      )
      # Generate a keytab for afs/
      out = ra.succeed("kadmin.local ktadd -k /tmp/shared/rxkad.keytab -e aes256-cts-hmac-sha1-96:normal,aes128-cts-hmac-sha1-96:normal afs/sipb.mit.edu")
      m = re.search(r"kvno (\d+)", out)
      assert m
      kvno = m.group(1)
      return kvno
    def install_afs_keytab(machine, kvno):
      machine.succeed(*(
        f"asetkey add rxkad_krb5 {kvno} {enctype} /tmp/shared/rxkad.keytab afs/sipb.mit.edu"
        for enctype in (18, 17)
      ))
      machine.start_job("openafs-server")

    start_all()
    kvno = setup_kdc(ra)
    install_afs_keytab(ra, kvno)
    install_afs_keytab(rb, kvno)
    # Wait for pts quorum (takes ~60s)
    ra.wait_until_succeeds("udebug localhost 7002 | grep 'Recovery state 1f'")
    # Wait until rb also thinks it has quorum
    rb.wait_until_succeeds("udebug rb 7002 | grep 'Sync host 192'")
    # Create initial 'admin' user
    ra.succeed(
      "bos adduser localhost admin -localauth",
      "pts createuser -name admin -localauth -cell sipb.mit.edu",
      "pts adduser admin system:administrators -localauth -cell sipb.mit.edu",
    )
  '';
}
