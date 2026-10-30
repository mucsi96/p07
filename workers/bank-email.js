// Cloudflare Email Worker: target of the Email Routing rule for the bank
// notification address. Forwards received card notification emails to the
// expense tracker's REST API, authenticated with a bearer token.
//
// Only mail whose sender Cloudflare could authenticate (passing SPF and an
// aligned DKIM signature) is forwarded; everything else is dropped without
// bouncing, since bouncing spam sent to a published address only generates
// backscatter.
export default {
  async email(message, env) {
    const senderDomain = message.from.toLowerCase().split("@")[1];

    if (!passesAuthentication(message.headers, senderDomain)) {
      // Logged because a drop here is either a spoofing attempt or a bank
      // notification lost to a broken SPF/DKIM setup — both worth seeing in
      // the worker logs.
      console.log(
        `Dropping email from ${message.from}: no passing SPF and DKIM result`
      );
      return;
    }

    const raw = await new Response(message.raw).text();

    const response = await fetch(env.TARGET_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.API_TOKEN}`,
      },
      body: JSON.stringify({
        from: message.from,
        to: message.to,
        subject: message.headers.get("subject") ?? "",
        raw,
      }),
    });

    if (!response.ok) {
      // Failing the delivery makes the sending mail server retry later, so a
      // temporarily unreachable expense tracker doesn't silently drop the
      // notification.
      throw new Error(`Expense tracker responded with HTTP ${response.status}`);
    }
  },
};

// True when Cloudflare's own Authentication-Results header (authserv-id
// mx.cloudflare.net) reports spf=pass and a dkim=pass whose signing domain
// (header.d) aligns with the sender's domain — same domain, or a parent or
// subdomain of it, matching DMARC's relaxed alignment. Fails closed when the
// header is missing or from another authserv-id.
function passesAuthentication(headers, senderDomain) {
  if (!senderDomain) {
    return false;
  }

  // Headers.get joins duplicate headers with ", ". Keeping only the first one
  // ignores any forged Authentication-Results header the sender included:
  // Cloudflare prepends its own, and its clauses never contain a comma.
  const authResults = (headers.get("authentication-results") ?? "")
    .toLowerCase()
    .split(",")[0];
  const [authservId, ...clauses] = authResults
    .split(";")
    .map((clause) => clause.trim());

  if (authservId !== "mx.cloudflare.net") {
    return false;
  }

  const spfPass = clauses.some((clause) => clause.startsWith("spf=pass"));
  const dkimPass = clauses.some((clause) => {
    const parts = clause.split(/\s+/);
    const signingDomain = parts
      .find((part) => part.startsWith("header.d="))
      ?.slice("header.d=".length);
    return (
      parts[0] === "dkim=pass" &&
      signingDomain !== undefined &&
      (signingDomain === senderDomain ||
        senderDomain.endsWith(`.${signingDomain}`) ||
        signingDomain.endsWith(`.${senderDomain}`))
    );
  });

  return spfPass && dkimPass;
}
