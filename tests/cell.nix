{ lib, ... }:
{
  name = "cell";
  defaults = { config, nodes, ... }: let
    cellServDB = {
      "sipb.mit.edu" = lib.mapAttrsToList (_: config: {
        ip = config.networking.primaryIPAddress;
        dnsname = "${config.networking.hostName}.${config.networking.domain}";
      }) nodes;
    };
  in {
    config = {
      sipb.afs.enable = true;
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false; # Disable external connectivity
      services.openafsClient.cellServDB = cellServDB;
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
        "kadmin.local add_principal -randkey admin",
        "rm -f /tmp/shared/admin.keytab",
        "kadmin.local ktadd -k /tmp/shared/admin.keytab admin",
        "kadmin.local add_principal -randkey -e aes256-cts-hmac-sha1-96:normal,aes128-cts-hmac-sha1-96:normal afs/sipb.mit.edu",
      )
      # Generate a keytab for afs/
      out = machine.succeed(
        "rm -f /tmp/shared/rxkad.keytab",
        "kadmin.local ktadd -k /tmp/shared/rxkad.keytab -e aes256-cts-hmac-sha1-96:normal,aes128-cts-hmac-sha1-96:normal afs/sipb.mit.edu",
      )
      m = re.search(r"kvno (\d+)", out)
      assert m
      kvno = m.group(1)
      return kvno
    def setup_afs_daemons(machine, kvno):
      machine.succeed(
        "mkdir -p /vicepa",
        "touch /vicepa/AlwaysAttach",
      )
      machine.succeed(*(
        f"asetkey add rxkad_krb5 {kvno} {enctype} /tmp/shared/rxkad.keytab afs/sipb.mit.edu"
        for enctype in (18, 17)
      ))
      machine.start_job("openafs-server")

    start_all()
    kvno = setup_kdc(ra)
    setup_afs_daemons(ra, kvno)
    setup_afs_daemons(rb, kvno)
    # Wait for pts quorum (takes ~60s)
    ra.wait_until_succeeds("udebug localhost 7002 | grep 'Recovery state 1f'")
    # Create initial 'admin' user
    # N.B. pts takes a few more seconds after it claims to be ready before we can actually create, so try a few times until it succeeds
    ra.wait_until_succeeds("pts createuser -name admin -localauth -cell sipb.mit.edu")
    ra.succeed(
      "bos adduser localhost admin -localauth",
      "pts adduser admin system:administrators -localauth -cell sipb.mit.edu",
    )
    # Create initial volumes
    ra.wait_until_succeeds("vos listvol localhost -localauth -cell sipb.mit.edu")
    ra.succeed(
      "vos create localhost vicepa root.afs -localauth -cell sipb.mit.edu",
      "vos create localhost vicepa root.cell -localauth -cell sipb.mit.edu",
    )
    # Authenticate and add a file
    ra.succeed(
      "kinit -k -t /tmp/shared/admin.keytab admin",
      "aklog sipb.mit.edu",
      "echo pass > /afs/sipb.mit.edu/test.txt",
    )
    # Authenticate and read a file
    rb.succeed(
      "kinit -k -t /tmp/shared/admin.keytab admin",
      "aklog sipb.mit.edu",
    )
    assert rb.succeed("cat /afs/sipb.mit.edu/test.txt").strip() == "pass"
  '';
}
