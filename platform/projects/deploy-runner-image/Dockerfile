# syntax=docker/dockerfile:1
#
# deploy-runner image. This file is generic: everything the image contains
# comes from the rendered manifest, .build/image.json, written by
# `renderer/render.py stage` from image.yaml + image.overrides.yaml.
#
# Install order follows the manifest sections: packages, binaries,
# terraform_providers, python_envs, scripts. Each has one step in steps/.
#
# BASE_IMAGE should be pinned by digest (image@sha256:...), so both stages use
# the same base. BASE_DIGEST is recorded in the image's manifest.

ARG BASE_IMAGE
ARG BASE_DIGEST=""

# ── fetch: download and verify binaries ─────────────────────────────────────
FROM ${BASE_IMAGE} AS fetch
ARG TARGETARCH
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN dnf install -y --setopt=install_weak_deps=False jq tar gzip unzip && dnf clean all
RUN --mount=type=bind,source=.build/image.json,target=/tmp/image.json \
    --mount=type=bind,source=steps,target=/tmp/steps \
    bash /tmp/steps/binaries.sh /tmp/image.json "$TARGETARCH" /out

# ── final: the runner image (build with --target final) ─────────────────────
FROM ${BASE_IMAGE} AS final
ARG TARGETARCH
ARG BASE_DIGEST
ARG PROPELLER_VERSION=dev
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# The image describes itself: steps add build facts to this file.
COPY .build/image.json /etc/propeller/image.json

RUN --mount=type=bind,source=steps,target=/tmp/steps \
    bash /tmp/steps/packages.sh /etc/propeller/image.json

COPY --from=fetch /out/bin/ /usr/local/bin/

RUN --mount=type=bind,source=steps,target=/tmp/steps \
    bash /tmp/steps/providers.sh /etc/propeller/image.json "$TARGETARCH"
ENV TF_CLI_CONFIG_FILE=/etc/terraformrc

# Envs use the image's interpreters only; never download one.
ENV UV_PYTHON_DOWNLOADS=never
RUN --mount=type=bind,source=steps,target=/tmp/steps \
    --mount=type=bind,source=.build/python,target=/tmp/python \
    bash /tmp/steps/python.sh /etc/propeller/image.json /tmp/python

RUN --mount=type=bind,source=steps,target=/tmp/steps \
    --mount=type=bind,source=.build/scripts,target=/tmp/scripts \
    bash /tmp/steps/scripts.sh /etc/propeller/image.json /tmp/scripts

RUN --mount=type=bind,source=steps,target=/tmp/steps \
    --mount=type=bind,from=fetch,source=/out/resolved.json,target=/tmp/fetch-resolved.json \
    bash /tmp/steps/finalize.sh /etc/propeller/image.json \
      "$PROPELLER_VERSION" "$TARGETARCH" "$BASE_DIGEST" /tmp/fetch-resolved.json

ENTRYPOINT []
CMD ["/bin/bash"]

# ── manifest: the final image's manifest, for `--output type=local` ─────────
# apply exports it after the push, to store what the image contains.
FROM scratch AS manifest
COPY --from=final /etc/propeller/image.json /image.json
