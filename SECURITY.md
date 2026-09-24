# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub's private vulnerability
reporting for this repository: open the repository's **Security** tab and choose
**Report a vulnerability**. This creates a private advisory that only the
maintainers can see.

Do not open a public issue, discussion, or pull request for a security problem,
and do not include exploit details in commit messages or PR descriptions.

Useful details to include in a report:

- which component is affected (see scope below) and the file(s) involved;
- the version or commit you tested against;
- steps to reproduce, and what impact you believe the issue has.

## Scope

This policy covers the source code in this repository:

- the iOS app (SwiftUI, SwiftData local store, engine client);
- the deterministic outfit engine (`backend/outfit-engine/`);
- the Cloudflare Worker code (`backend/workers/`);
- the CI workflows, scripts, and fixtures kept here.

## Out of scope

- Any deployed service, environment, or account operated from this code. If you
  believe you have found a problem in a running deployment, please still report
  it privately through the channel above rather than testing against it further;
  the repository itself holds no credentials, secrets, or production configuration.
- Vulnerabilities in third-party dependencies that do not affect how this
  repository uses them. Reports that show a concrete impact here are welcome.
- Findings from automated scanners without a demonstrated impact.

## What to expect

- This is a small, source-available project maintained on a best-effort basis.
  There is **no bug bounty** and no guaranteed response time; reports are read
  and acknowledged as soon as reasonably possible.
- Confirmed issues are fixed through the normal pull-request process and land on
  `main` like any other change. Where it helps, the private advisory is published
  after the fix is available.
- Please give the maintainers a reasonable window to address a report before
  disclosing it publicly.

## Licensing note

The repository is source-available under the terms described in `NOTICE.md`.
Reporting a vulnerability does not change those terms, and security fixes are
published under the same terms as the rest of the code.
