# Security and safety

Omarchy loads plugin code into the child's session with no sandbox, so anything this plugin does
wrong, a child's machine does wrong. That is why it has no network code, no processes, no free-text
entry and no stored dates, and why `npm run check:readme` asserts those four things against every
file on every push.

**Report privately** anything that would let this plugin, or a change to it, do more than the README
says it does: send data off the machine, run a process, read or write a file other than its own
save file, or accept text a child typed anywhere but the answer field.
[Open a security advisory](https://github.com/Dmcchesney/omarchy-kids-game-turbo-tables/security/advisories/new)
with the steps. We aim to acknowledge within seven days and agree a disclosure timeline with you.

A way for a child to get around a protection Omarchy Kids Mode designs is a security issue for the
hub, not this repository: see the hub's
[SECURITY.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/SECURITY.md).
Vulnerabilities in Omarchy itself go to security@omarchy.org.

Children who find something are welcome to report it, through a parent. Credit goes to the parent's
handle. Never include a child's name, photo, voice, username or exact age in a report.

Already-public or theoretical weaknesses can go straight to a normal issue.
