# The facts of the forge machine, per ADR-0116. None is a secret. forge.nix, the hypervisor, and forge.sh read them.
{
  # The SSH public keys that log in as root on the forge and the runner. On the hypervisor, its own keys apply.
  adminKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithTheKeyOfTheOwner owner" ];
  # The private address of the machine. The deploy, the hypervisor, and the scripts reach it here.
  address = "10.0.10.30";
  # Null when a workstation reaches the forge directly. On a private network, the host that reaches it, as `user@host`.
  jump = "root@198.51.100.2";
  # The key for both hops. Null uses the SSH agent.
  sshKey = null;
  # A file of the jump host's SSH keys, verified out of band. Null accepts the key of a new host on first contact.
  knownHosts = null;

  # The public name of the forge. Its certificate comes from the own ACME client of Forgejo.
  domain = "forge.example.com";
  # The address that receives the ACME account mail.
  acmeEmail = "ops@example.com";
  enableAcme = true;
  # The organisation that owns the repository, so the repository URL names no person.
  org = "platform";
  # A push mirror of the repository, such as `ssh://git@github.com/acme/acmeplat.git`. Null means no mirror.
  mirrorUrl = null;

  # The public facts of the signing key that `just forge-signing` imports. A null key means the forge signs nothing.
  signing = {
    key = null;
    name = null;
    email = null;
  };
}
