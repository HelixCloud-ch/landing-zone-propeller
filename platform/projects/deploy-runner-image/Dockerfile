# syntax=docker/dockerfile:1
#
# deploy-runner image: lean Amazon Linux 2023 base with the tools a propeller
# deploy needs, with an offline terraform provider mirror.
#
# Supports amd64 and arm64.
# Tools: bash, terraform, just, aws-cli, jq, python3, git, kubectl, helm.
ARG BASE_IMAGE=public.ecr.aws/amazonlinux/amazonlinux:2023

# =============================================================================
# -- fetch stage: download and checksum-verify tool binaries ------------------
# =============================================================================

FROM ${BASE_IMAGE} AS fetch

ARG TARGETARCH
ARG TERRAFORM_VERSION JUST_VERSION KUBECTL_VERSION HELM_VERSION
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN dnf install -y --setopt=install_weak_deps=False tar gzip unzip && dnf clean all

WORKDIR /tmp/fetch

RUN <<'EOF'
set -euo pipefail
mkdir -p /out

case "$TARGETARCH" in
  amd64) tf_arch=amd64; just_arch=x86_64; kube_arch=amd64; helm_arch=amd64 ;;
  arm64) tf_arch=arm64; just_arch=aarch64; kube_arch=arm64; helm_arch=arm64 ;;
  *) echo "unsupported arch: $TARGETARCH"; exit 1 ;;
esac

check_sha() { echo "$1  $2" | sha256sum -c -; }
hash_for() { grep "$1" "$2" | awk '{print $1}'; }

# terraform
curl -fsSL -o tf.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${tf_arch}.zip"
curl -fsSL -o tf.sums "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
check_sha "$(hash_for "linux_${tf_arch}.zip$" tf.sums)" tf.zip
unzip -o tf.zip terraform -d /out

# just
curl -fsSL -o just.tgz "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${just_arch}-unknown-linux-musl.tar.gz"
curl -fsSL -o just.sums "https://github.com/casey/just/releases/download/${JUST_VERSION}/SHA256SUMS"
check_sha "$(hash_for "${just_arch}-unknown-linux-musl.tar.gz$" just.sums)" just.tgz
tar -xzf just.tgz -C /out just

# kubectl
curl -fsSL -o /out/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${kube_arch}/kubectl"
curl -fsSL -o kubectl.sha "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${kube_arch}/kubectl.sha256"
check_sha "$(cat kubectl.sha)" /out/kubectl
chmod +x /out/kubectl

# helm
curl -fsSL -o helm.tgz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${helm_arch}.tar.gz"
curl -fsSL -o helm.sha "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${helm_arch}.tar.gz.sha256sum"
check_sha "$(hash_for "helm-v${HELM_VERSION}-linux-${helm_arch}.tar.gz$" helm.sha)" helm.tgz
tar -xzf helm.tgz --strip-components=1 -C /out "linux-${helm_arch}/helm"
EOF

# =============================================================================
# -- final stage: runtime with tools + provider mirror ------------------------
# =============================================================================

FROM ${BASE_IMAGE}

ARG TARGETARCH
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN dnf install -y --setopt=install_weak_deps=False \
      git jq python3 python3-pip tar gzip unzip ca-certificates awscli findutils which \
 && pip3 install --no-cache-dir boto3 botocore \
 && dnf clean all && rm -rf /var/cache/dnf

COPY --from=fetch /out/terraform /out/just /out/kubectl /out/helm /usr/local/bin/

# Provider mirror: terraform init resolves from here with no network access.
# providers.txt is the framework baseline (never overlaid by consumers).
# providers.extra.txt is the consumer-additive overlay (optional); it is placed
# here by the overlay mechanism at build time if the consumer defines one.
COPY providers.txt /tmp/providers.txt
COPY providers.extra.txt* /tmp/
RUN <<'EOF'
set -euo pipefail
mkdir -p /opt/tf-providers
tf_platform="linux_${TARGETARCH}"

mirror_providers() {
  local file="$1"
  [ -f "$file" ] || return 0
  while read -r src ver; do
    [ -z "${src:-}" ] && continue
    case "$src" in \#*) continue ;; esac

    name="${src##*/}"
    conf="$(mktemp -d)/main.tf"
    cat > "$conf" <<HCL
terraform {
  required_providers {
    $name = { source = "$src", version = "$ver" }
  }
}
HCL
    ( cd "$(dirname "$conf")" && terraform providers mirror -platform="$tf_platform" /opt/tf-providers )
    rm -rf "$(dirname "$conf")"
  done < "$file"
}

mirror_providers /tmp/providers.txt
mirror_providers /tmp/providers.extra.txt
rm -f /tmp/providers.txt /tmp/providers.extra.txt
EOF

RUN <<'EOF'
cat > /etc/terraformrc <<HCL
provider_installation {
  filesystem_mirror {
    path    = "/opt/tf-providers"
    include = ["*/*"]
  }
}
HCL
EOF
ENV TF_CLI_CONFIG_FILE=/etc/terraformrc

ENTRYPOINT []
CMD ["/bin/bash"]

RUN terraform version \
 && just --version \
 && kubectl version --client \
 && helm version --short \
 && aws --version \
 && git --version \
 && jq --version \
 && python3 --version \
 && python3 -c "import boto3, botocore; print(boto3.__version__, botocore.__version__)"
