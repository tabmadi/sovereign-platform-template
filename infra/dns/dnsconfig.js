// Every record in every zone that this project owns, per ADR-0206 and ADR-0307.
//
// THIS FILE IS THE ZONE. `mise run dns:apply` deletes every record that the provider holds and this file does not declare.
// A record added in the provider's console lives until the next apply. To add one, open a pull request.

var REG = NewRegistrar("none");
var ZONE = NewDnsProvider("zone");

var APEX = "example.com";

// The addresses are placeholders from the documentation range of RFC 5737. Each environment has two.
// `edge` is the address that Traefik answers on. `mail` is the mail egress, whose `PTR` record resolves back to `mail.<env>`.
// `dkim` is the public half of the pair whose private half is that environment's `maddy-dkim` SopsSecret, per ADR-0307.
var ENVIRONMENTS = {
  dev: { edge: "192.0.2.10", mail: "192.0.2.11", dkim: "" },
  staging: { edge: "192.0.2.20", mail: "192.0.2.21", dkim: "" },
  prod: { edge: "192.0.2.30", mail: "192.0.2.31", dkim: "" },
};

// The product tier is the environment host, and the ops tier is one wildcard below `ops`, per ADR-0306.
// Two wildcards, because `*.<env>` does not match a name that is two labels deep. They cover every new service.
function platform(env, edge) {
  return [A(env, edge), A("*." + env, edge), A("*.ops." + env, edge)];
}

// Mail authentication for the sender of one environment, per ADR-0307. SPF authorises the one egress address.
// `-all` refuses every other sender. A soft fail asks receivers to accept mail that this platform did not send.
// The DKIM record waits for the key: an empty record fails authentication for every message.
function mail(env, ip, dkim) {
  var records = [
    A("mail." + env, ip),
    TXT("mail." + env, "v=spf1 ip4:" + ip + " -all"),
    TXT("_dmarc." + env, "v=DMARC1; p=none; sp=none; fo=1; rua=mailto:dmarc@" + env + "." + APEX),
  ];
  if (dkim) {
    records.push(TXT("default._domainkey.mail." + env, "v=DKIM1; k=rsa; p=" + dkim));
  }
  return records;
}

var records = [];
for (var env in ENVIRONMENTS) {
  var e = ENVIRONMENTS[env];
  records = records.concat(platform(env, e.edge), mail(env, e.mail, e.dkim));
}

// The organisation's own records go here too, such as the `MX` of human mail. The apply deletes what this file omits.
D(APEX, REG, DnsProvider(ZONE), records);
