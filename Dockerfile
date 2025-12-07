# syntax=docker/dockerfile:1

FROM docker.io/library/python:3.13-alpine3.21

ARG TARGETARCH
ARG WEBHOOK_VERSION=2.8.2
ARG KUBECTL_VERSION=1.31.4
ARG TALOSCTL_VERSION=1.9.1
ARG FLUX_VERSION=2.4.0

ENV \
    CRYPTOGRAPHY_DONT_BUILD_RUST=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_NO_CACHE=true \
    UV_SYSTEM_PYTHON=true \
    UV_EXTRA_INDEX_URL="https://wheel-index.linuxserver.io/alpine-3.21/"

ENV \
    WEBHOOK__PORT="9000" \
    WEBHOOK__URLPREFIX="hooks" \
    AUDIT_LOG="/tmp/kait-audit.log" \
    AUDIT_FORMAT="json"

USER root
WORKDIR /app

RUN \
    apk add --no-cache \
        bash \
        ca-certificates \
        catatonit \
        coreutils \
        curl \
        flock \
        jo \
        jq \
        trurl \
        tzdata \
    # Create directories
    && mkdir -p /app/bin /app/scripts /extras \
    # webhook
    && curl -fsSL "https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-${TARGETARCH}.tar.gz" \
        | tar xzf - -C /app/bin --strip-components=1 \
    # kubectl
    && curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
        -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl \
    # talosctl
    && curl -fsSL "https://github.com/siderolabs/talos/releases/download/v${TALOSCTL_VERSION}/talosctl-linux-${TARGETARCH}" \
        -o /usr/local/bin/talosctl && chmod +x /usr/local/bin/talosctl \
    # flux
    && curl -fsSL "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" \
        | tar xzf - -C /usr/local/bin flux \
    # apprise for notifications
    && pip install uv \
    && uv pip install "apprise>=1, <2" \
    && pip uninstall --yes uv \
    # Permissions
    && chown -R root:root /app && chmod -R 755 /app \
    && chown nobody:nogroup /extras \
    # Cleanup
    && rm -rf /tmp/* \
    # Verify installations
    && kubectl version --client \
    && talosctl version --client \
    && flux version --client

COPY entrypoint.sh /entrypoint.sh
COPY scripts/ /app/scripts/
RUN chmod +x /entrypoint.sh /app/scripts/*.sh

ENV PATH="/app/scripts:/extras:/usr/local/bin:${PATH}"

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]

ENTRYPOINT ["/usr/bin/catatonit", "--", "/entrypoint.sh"]
