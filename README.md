# setup-nix

Install Nix and select a persistent cache for GitHub Actions. The action uses the NixOS installer on Linux, a prebuilt Nix store from [nix-quick-install-action](https://github.com/nixbuild/nix-quick-install-action) on macOS, and Hestia, with Blacksmith sticky disks on supported Linux runners. Setup uses Bash and the runner-provided Node 24 runtime. No additional script runtime is downloaded.

```yaml
permissions:
  contents: read
  actions: read

steps:
  - uses: actions/checkout@v7
  - uses: x-ryoppippi/setup-nix@<full-commit-sha>
  - run: nix flake check
```

Pin the action to a reviewed commit. On GitHub's cache service, `actions: read` lets Hestia detect evicted cache packs upfront; the cache itself uses the runner's cache token. Separate runtime cache proxies use Hestia's lazy pack lookup because GitHub's REST inventory cannot describe their contents. Hestia runs from the [x-ryoppippi/hestia](https://github.com/x-ryoppippi/hestia) fork, whose releases carry its own build attestations, until [Mic92/hestia#196](https://github.com/Mic92/hestia/issues/196) is fixed upstream. The Hestia release binary is kept in the Actions cache under a key naming its exact release, OS and architecture, and a restored copy passes the same build-attestation check as a download before it runs. Writable runs save it after a verified download; downloads retry transient failures.

| Runner | Automatic backend | Garbage collection |
|---|---|---|
| GitHub Linux | Hestia | Repository GC workflow |
| GitHub macOS | Hestia | Repository GC workflow |
| Blacksmith Linux with sticky disk support | Sticky `/nix` | Optional local store trimming |
| Blacksmith macOS | Hestia | Blacksmith cache eviction |

Automatic detection uses Linux plus `BLACKSMITH_STICKY_DISK_GRPC_PORT`, not runner names. Linux x64/ARM64 and macOS ARM64 are supported. Intel macOS and Windows are unsupported.

## Configuration

| Input | Default | Purpose |
|---|---|---|
| `cache` | `auto` | Select `auto`, `sticky`, `hestia` or `none`. Explicit `sticky` requires a supported runner. |
| `save` | `true` | Permit cache writes within the event's allowed scope. |
| `cache-scope` | empty | Separate sticky disks for matrix entries sharing one job ID. |
| `sticky-key` | repository, architecture, job and scope | Set a base key, for example when borrowing another job's disk. |
| `sticky-gc-threshold` | `0` | Opt into trimming a writable sticky store above this usage percentage. `0` disables trimming. |
| `extra-conf` | empty | Additional public Nix settings. |
| `github-token` | `github.token` | Configure authenticated Nix GitHub fetches. Empty disables this configuration. |
| `installer-version` | `2.35.4` | Pin the NixOS installer release on Linux. macOS ignores it and installs the Nix version pinned in `action.yaml`. |

Outputs are `backend`, `cache-writable` and `sticky-key` (the fully qualified disk key).

Both platforms set `max-jobs = auto`. No extra build or transfer concurrency settings are needed by default.

The Linux installer logs its `extra-conf` input. Pass credentials through `github-token`, which this action reads from the environment and writes silently into a private user configuration file. Access-token settings in `extra-conf` are rejected.

## macOS

macOS installs a single-user Nix owned by the runner user: no daemon, build users or launchd services. The user configuration repeats the Linux installer's defaults, including Nix's default of no build sandbox on macOS, and leaves `accept-flake-config` disabled.

## Sticky disks

Both backends write only on the default branch, excluding pull-request events, and only when `save` permits it. Other runs read the default branch's cache without writing: a sticky snapshot is not committed, and Hestia runs read-only. Other refs could only write to their own cache scope, which nothing else reads, so those writes would only consume the cache quota.

The disk key includes an installer-version and configuration suffix. Existing single-user Nix caches therefore remain untouched when migrating to this multi-user installer. Installer or public configuration changes select a fresh disk, which must warm again. A `sticky-key` override changes the base, not this suffix.

Only `/nix` persists. Installation is replayed on each host so build users and host configuration are recreated. Each runner user's Nix fetcher cache lives under `/nix/var/cache/nix/per-user/<uid>`, separate from the daemon's privileged cache and locks, avoiding repeated flake-input downloads.

The action owns daemon teardown: its post-job helper stops the daemon before Blacksmith unmounts and commits the disk. The helper uses GitHub's `$/` reference to run code from the same reviewed action commit.

Blacksmith store trimming is disabled by default. Opt in with `sticky-gc-threshold: '50'`, for example, to trim before builds only when the disk may be committed and exceeds 50% usage. It honours Nix GC roots. The action prepares `/nix/var/nix/gcroots/per-user/$(id -un)` for the runner. Put build artifacts that must survive trimming there; workspace out-links disappear between runs. Keep `keep-derivations` and `keep-outputs` enabled in `extra-conf` when build-time closures must survive. Opt-in trimming also clears the fetcher cache so the next invocation repopulates it.

## Hestia garbage collection

Add a daily caller workflow to each repository:

```yaml
name: Cache GC
on:
  schedule:
    - cron: '41 4 * * *'
  workflow_dispatch:
permissions: {}
jobs:
  gc:
    permissions:
      actions: write
      contents: read
    uses: x-ryoppippi/setup-nix/.github/workflows/gc.yaml@<full-commit-sha>
```

The reusable workflow runs only on the caller's default branch, serialises GC runs, and supports `with: { dry-run: true }`. One GitHub Linux GC job handles the repository's GitHub-hosted Hestia cache roots, including macOS builds. It runs on `ubuntu-slim` with its 15-minute limit. It does not mount, trim or delete Blacksmith sticky snapshots.

Blacksmith redirects runtime caches to its own service, so GitHub REST cannot safely enumerate or delete those Hestia packs. The GC workflow stays on GitHub's cache service. Blacksmith-backed Hestia caches rely on [Blacksmith's LRU eviction policy](https://docs.blacksmith.sh/blacksmith-caching/dependencies-actions); their Hestia metadata is not compacted by this workflow. Cache-service detection excludes Blacksmith environments and unrecognised runtime endpoints from REST-based eviction checks.

## Validation and releases

CI runs real installation and build jobs on GitHub and Blacksmith Linux/macOS runners, plus a no-init `ubuntu-slim` job. On `main`, a subsequent job verifies cache reuse on a fresh runner. Cache GC is exercised in dry-run mode. Runtime compatibility is established by those jobs, not simulated installer execution on a developer's machine.

tagpr maintains release pull requests and creates tags after they merge. Versions live in Git tags, without a separate version file.

## Licence

MIT.
