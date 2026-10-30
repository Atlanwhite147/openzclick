# Security policy

## Reporting a vulnerability

Do not open a public issue for a security problem. Write to the maintainer through the address on the GitHub profile, or open a draft security advisory on this repository.

Include the affected module, the version or commit, a description of the impact and, if possible, a minimal reproduction. Expect an answer within a week.

## Scope

- the binary protocol codec and the encrypted controller session (`core/`);
- the network responder and TCP server (`transports/`);
- the shipped Android and iOS packages.

## Design notes

- The OpenBikeControl link is unauthenticated and unencrypted, like every mDNS based local protocol: anyone on the same network can connect. Announcement is off by default and must be enabled explicitly, and the protocol carries no personal data beyond the controller button states.
- Controller sessions use ephemeral P-256 keys and are never stored. Keys live in memory for the duration of a connection.
- The Android package is signed with a public community key, documented in the README. That key exists only for continuous builds and must never be used for a store release.
