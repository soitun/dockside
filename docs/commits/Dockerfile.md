# Dockerfile commit message draft

```
Dockerfile: Fix theia-build cache bust on every commit

DOCKSIDE_VERSION (derived from `git describe --tags`) was written into
/tmp/dockside/bash-env inside the `base` stage. Because `theia-build-env`
does a `COPY --from=base /tmp/dockside /tmp/dockside`, any commit that
changed the version string invalidated that COPY's cache, forcing a full
Theia rebuild on every push — even for Perl-only changes.

DOCKSIDE_VERSION and DS_PATH are only consumed by the `system` stage, not
by any Theia stage. Remove them from bash-env and instead set DS_PATH via
an ENV instruction in the `system` stage itself, derived from the ARG
DOCKSIDE_VERSION and ARG OPT_PATH already declared there.

bash-env content now depends only on TARGETPLATFORM, THEIA_VERSION,
OPENVSCODE_VERSION, and OPT_PATH — none of which change between commits —
so the theia-build cache survives Perl and other non-IDE changes.
```
