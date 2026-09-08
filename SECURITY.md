# Security Policy

## Supported versions

Only the newest published patch in the `0.1.x` series receives security fixes.
Unreleased revisions, superseded patch releases, and versions older than 0.1.0
are not supported. A security fix may require upgrading to the newest patch.

| Version | Supported |
| --- | --- |
| Latest `0.1.x` patch | Yes |
| Superseded `0.1.x` patches | No |
| `< 0.1.0` | No |

## Report a vulnerability privately

Email **pcharbon70@gmail.com** with the subject `SimdJson security report`.
Do not open a public issue, pull request, discussion, or test fixture for a
suspected vulnerability.

Include the affected SimdJson version and commit when known, the qualified or
experimental target, reproduction steps, impact, and any suggested mitigation.
Remove credentials, private JSON payloads, personal information, and production
data. A minimal synthetic reproducer is preferred.

Receipt should be acknowledged within seven calendar days. The maintainer will
coordinate validation, disclosure timing, a patched release or other
mitigation, and credit if requested. Do not publish details until coordinated
disclosure is complete.

For ordinary bugs and feature requests that have no security impact, use the
[public issue tracker](https://github.com/pcharbon70/simd_json/issues).
