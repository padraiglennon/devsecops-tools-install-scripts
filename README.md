# devsecops-tools-install-scripts

A collection of idempotent shell scripts for installing and upgrading the tools a
DevOps / DevSecOps engineer (or team) reaches for day to day. Each script resolves
the latest release, checks whether the installed version is already current, and
installs to `/usr/local/bin` (overridable). Most are driven by a shared library so
they behave consistently and take the same command-line flags.

> **Target environment: WSL 2 (Ubuntu/Debian).** These scripts are written for a
> WSL Ubuntu development setup on `x86_64`. They assume a Linux userland — kubectl
> and minikube hard-require it — and the apt-based installers (Azure CLI, Chrome,
> cloudflared, the deadsnakes Python builds) assume a Debian/Ubuntu host with
> `apt`. They work on native Ubuntu/Debian too; they are **not** intended for macOS
> or other distros without adjustment.

## Quick start

```bash
# Install or upgrade a single tool
./install_trivy.sh                 # latest
./install_trivy.sh --version v0.71.0
./install_trivy.sh --dry-run       # resolve + report, install nothing

# Install or upgrade everything in one pass (single sudo prompt)
./install_all.sh                   # all tools
./install_all.sh --only trivy,yq   # just these
./install_all.sh --skip chrome     # everything except these
./install_all.sh --list            # preview what would run
```

### Common flags (library-driven scripts)

| Flag | Effect |
| --- | --- |
| `-v, --version <ver\|latest>` | Version to install (default: `latest`) |
| `-d, --install-dir <path>` | Install directory (default: `/usr/local/bin`) |
| `-n, --dry-run` | Resolve and report, but don't install |
| `-f, --force` | Reinstall even if already up to date |
| `--no-verify` | Skip checksum/payload verification (where supported) |
| `--keep-tmp` | Keep the temp download dir |
| `-h, --help` | Show help |

Flags take precedence; existing environment variables (`<TOOL>_VERSION`,
`INSTALL_DIR`, `GH_TOKEN`, …) still work as fallback defaults.

---

## The tech stack

The tools below map onto a typical cloud-native delivery pipeline: write code →
lint and scan it → build and sign artifacts → ship to Kubernetes → operate the
cluster, all on top of the cloud providers and language runtimes underneath.

### Supply-chain security & artifact integrity

The heart of the "Sec" in DevSecOps — knowing what's in your artifacts and proving
they haven't been tampered with.

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[syft](https://github.com/anchore/syft#readme)** (`anchore/syft`) | Generates a Software Bill of Materials (SBOM) from images and filesystems | The starting point for supply-chain visibility — feeds grype and attestations |
| **[grype](https://github.com/anchore/grype#readme)** (`anchore/grype`) | Scans SBOMs / images for known CVEs | Pairs directly with syft (same vendor, consumes its SBOMs) |
| **[trivy](https://trivy.dev/latest/docs/)** (`aquasecurity/trivy`) | All-in-one scanner: vulnerabilities, misconfig, secrets, SBOM | The broadest scanner — covers images, filesystems, and IaC in one tool |
| **[cosign](https://docs.sigstore.dev/cosign/system_config/installation/)** (`sigstore/cosign`) | Signs and verifies container images and artifacts (keyless via Sigstore) | Closes the loop: prove an artifact's provenance, not just scan it |
| **[gitleaks](https://github.com/gitleaks/gitleaks#readme)** (`gitleaks/gitleaks`) | Detects committed secrets (keys, tokens, credentials) | Catches leaked credentials before they reach a remote or a build |

### Code quality & linting

Fast feedback that catches problems before CI does.

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[shellcheck](https://www.shellcheck.net/wiki/)** (`koalaman/shellcheck`) | Static analysis for shell scripts | These install scripts are themselves shellcheck-clean; essential for any bash-heavy repo |
| **[actionlint](https://github.com/rhysd/actionlint/blob/main/docs/usage.md)** (`rhysd/actionlint`) | Linter for GitHub Actions workflow files | Validates CI YAML locally before pushing |
| **[hadolint](https://github.com/hadolint/hadolint#readme)** (`hadolint/hadolint`) | Dockerfile linter / best-practice checker | Completes the lint trio with shellcheck + actionlint |

### Data wrangling on the CLI

The glue tools used in nearly every script and pipeline.

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[jq](https://jqlang.github.io/jq/manual/)** (`jqlang/jq`) | Query and transform JSON | Robust replacement for `grep`/`sed` when parsing API responses |
| **[yq](https://mikefarah.gitbook.io/yq/)** (`mikefarah/yq`) | Query and transform YAML | Indispensable with all the Kubernetes / Helm / Argo YAML |

### Kubernetes

Cluster interaction and day-to-day operations.

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[kubectl](https://kubernetes.io/docs/reference/kubectl/)** (`kubernetes/kubernetes`) | The Kubernetes CLI | The fundamental cluster client. Installed from `dl.k8s.io` with checksum verification + backup |
| **[minikube](https://minikube.sigs.k8s.io/docs/)** (`kubernetes/minikube`) | Local single-node Kubernetes | Local cluster for development and CI parity |
| **[kubectx + kubens](https://github.com/ahmetb/kubectx#readme)** (`ahmetb/kubectx`) | Fast context / namespace switching | Near-universal quality-of-life tooling alongside kubectl |
| **[stern](https://github.com/stern/stern#readme)** (`stern/stern`) | Multi-pod log tailing | Tails logs across pods/containers at once — a daily operational workhorse |
| **[k9s](https://k9scli.io/)** (`derailed/k9s`) | Terminal UI for managing clusters | Interactive cluster navigation without memorising kubectl flags |
| **[kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/)** (`kubernetes-sigs/kustomize`) | Template-free Kubernetes manifest customisation | Overlay-based config management for K8s resources |
| **[helm](https://helm.sh/docs/)** (`helm/helm`) | Kubernetes package manager | Installs and manages chart-based applications |
| **[argo](https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/)** (`argoproj/argo-workflows`) | CLI for Argo Workflows | Drives the workflow engine used for pipelines on Kubernetes |
| **[eksctl](https://eksctl.io/)** (`eksctl-io/eksctl`) | CLI for creating/managing Amazon EKS clusters | The standard way to provision EKS |

### Service mesh / networking

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[envoy](https://www.envoyproxy.io/docs)** | High-performance L7 proxy | The data plane behind most service meshes and API gateways |
| **[cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)** (`pkg.cloudflare.com`) | Cloudflare Tunnel daemon | Exposes local services securely without inbound firewall rules |

### Containers & build

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[docker](https://docs.docker.com/engine/)** (Docker CE) | Container engine + CLI (with buildx and compose plugins) | The foundational runtime — builds, runs, and packages the images everything else scans, signs, and ships |
| **[pack](https://buildpacks.io/docs/for-platform-operators/how-to/integrate-ci/pack/)** (`buildpacks/pack`) | Builds OCI images from source via Cloud Native Buildpacks | Produces container images without hand-written Dockerfiles |

### Infrastructure as Code (HashiCorp)

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[terraform](https://developer.hashicorp.com/terraform/docs)** | Declarative infrastructure provisioning | The IaC backbone for cloud resources |
| **[vault](https://developer.hashicorp.com/vault/docs)** | Secrets management and data protection | Centralised secret storage, dynamic credentials, encryption |
| **[consul](https://developer.hashicorp.com/consul/docs)** | Service discovery and service mesh | Service catalog and health checking for distributed systems |

### Cloud provider CLIs

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[aws](https://docs.aws.amazon.com/cli/)** (AWS CLI v2) | Command-line access to AWS | Provider CLI for everything AWS |
| **[az](https://learn.microsoft.com/en-us/cli/azure/)** (Azure CLI) | Command-line access to Azure | Provider CLI for everything Azure |
| **[gcloud](https://cloud.google.com/sdk/docs)** (Google Cloud CLI) | Command-line access to GCP | Provider CLI for everything GCP |

### Language runtimes & package managers

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[go](https://go.dev/doc/)** (`go.dev`) | Go toolchain | Most cloud-native tooling is written in Go; needed to build from source |
| **[uv](https://docs.astral.sh/uv/)** (`astral-sh/uv`) | Fast Python package / project manager | Modern, dramatically faster pip/venv replacement |
| **[python3](https://docs.python.org/3/)** (deadsnakes) | Specific Python versions + venvs | Pin and manage Python versions for tooling and scripts |

### Desktop / misc

| Tool | What it does | Why it's here |
| --- | --- | --- |
| **[google-chrome](https://support.google.com/chrome/answer/95346)** (`dl.google.com`) | Chrome browser | Headless browser for testing, scraping, and rendering |

---

## How it works

Most "install a GitHub-released binary" scripts are thin declarative wrappers over
[`lib/install_common.sh`](lib/install_common.sh), which provides shared logging,
OS/architecture detection, release resolution, download/extract/install, and the
standard CLI flag parser. A typical script is just a block of declarations:

```bash
IC_TOOL_NAME=syft
IC_REPO=anchore/syft
IC_ARCHIVE_TYPE=tar.gz
IC_ASSET_TMPL='syft_${VER}_${OS}_${ARCH}.tar.gz'
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 )
IC_LOCATOR='top:syft'
IC_VERSION_CMD='version'
ic_parse_args "$@"; gh_binary_install
```

Tools with bespoke needs (kubectl's checksum + backup, minikube's running-cluster
detection, the cloud CLIs' official installers, Go/Python's privilege handling)
source the library for plumbing but keep their own logic.

`install_all.sh` runs every script in one pass: it primes `sudo` once and keeps the
timestamp alive so each child script's internal `sudo` calls succeed unattended,
then prints a per-tool success/failure summary.
