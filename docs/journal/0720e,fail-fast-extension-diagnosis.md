# 0720e — Make blocked extension requests fail fast, then diagnose

2026-07-20 (NY)

Context: the Python and Pylance extensions are still absent, leaving Python
outlines and F12 dead. The retained VS Code server log shows a batch of VSIX
signature checks taking about 90.5 seconds before succeeding, while the Python
extensions remained unfinished when the client disconnected. Blocked
certificate-revocation or other signature-verification traffic is the leading
explanation, but the exact required endpoint has not been established.

The immediate plan is to add a terminal rule at the end of the firewall's
`OUTPUT` chain, after every intended `ACCEPT` rule:

```bash
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
```

This does not allow any additional traffic. It changes the behavior of traffic
that is already blocked: instead of being silently dropped until the caller's
network timeout expires, the kernel rejects it immediately.

## What this step does and does not promise

The `REJECT` rule is guaranteed to make blocked calls fail quickly and become
easier to diagnose. It is not guaranteed by itself to make the extensions
install.

There are two useful outcomes:

1. If signature verification treats an unreachable revocation service as a
   soft failure, it should finish promptly and extension installation should
   proceed. In that case the rule fixes the practical stall without weakening
   signature verification.
2. If verification requires the blocked service, installation should fail
   promptly with a useful error. That identifies what must be evaluated for a
   narrow allowlist exception.

## Decision sequence

1. Add the terminal `OUTPUT REJECT` after the allowlisted-ipset `ACCEPT` rule in
   `init-firewall.sh` and rebuild the devcontainer.
2. Retry extension installation with `extensions.verifySignature` left at its
   default, enabled value.
3. Inspect the server log and installed-extension list.
4. If verification now fails, identify the exact rejected destination before
   changing the allowlist.
5. Prefer a narrow allowlist addition if its security and CDN behavior are
   acceptable. Use `"extensions.verifySignature": false` only as a fallback,
   because egress filtering and package-signature verification protect against
   different threats.

Separately, the static one-shot DNS-to-ipset design remains vulnerable to CDN
address rotation. That is a broader firewall-design issue and should not be
mixed into this first diagnostic change.

## Result

Successful on 2026-07-20. After rebuilding the devcontainer with the terminal
`OUTPUT REJECT` rule, both extensions installed with signature verification
still enabled:

```text
ms-python.python@2026.4.0
ms-python.vscode-pylance@2026.2.1
```

The new server log records `donotVerifySignature:false`. Blocked requests now
failed quickly with errors such as `EHOSTUNREACH`; Pylance installed in about
four seconds and Python in about one second. Pylance then activated and started
its language server. Python symbols appeared in the Outline, and F12 / Go to
Definition worked.

This is outcome 1 above: changing silent drops into immediate rejections
removed the practical installation stall without disabling signature
verification or adding another allowlist exception. The exact blocked
revocation or verification endpoint remains unidentified. Extension downloads
from inside the container still failed and VS Code used its host-side extension
relay, but the relayed installs were able to finish promptly.

## New unresolved failure

After this success, VS Code displayed the following popup:

> Cannot activate the 'Python Debugger' extension because it depends on the
> 'Python' extension which is disabled.

This failure has only been recorded here; it has not been investigated or
changed.
