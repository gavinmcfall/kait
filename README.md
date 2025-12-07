# KAIT - Kubernetes Automation & Integration Toolkit

A lightweight container image built on Alpine with Kubernetes CLI tools for webhook-driven automation tasks.

## Included Tools

**Base utilities:**
- [adnanh/webhook](https://github.com/adnanh/webhook) - Lightweight webhook server
- bash, curl, jq, jo, flock
- [apprise](https://github.com/caronc/apprise) - Push notifications

**Kubernetes tools:**
- `kubectl` - Kubernetes CLI
- `talosctl` - Talos Linux CLI
- `flux` - Flux CD CLI

## Usage

### As a webhook server

```yaml
# hooks.yaml
- id: my-automation
  execute-command: /scripts/handler.sh
  pass-arguments-to-command:
    - source: payload
      name: status
  http-methods: ["POST"]
```

```bash
docker run -d \
  -v ./hooks.yaml:/config/hooks.yaml \
  -v ./scripts:/scripts \
  -p 9000:9000 \
  ghcr.io/gavinmcfall/kait:rolling
```

### As a kubectl container

```bash
docker run --rm \
  -v ~/.kube/config:/home/nonroot/.kube/config:ro \
  ghcr.io/gavinmcfall/kait:rolling \
  kubectl get pods
```

## Health Probes

The webhook server exposes a health endpoint at `/` that returns HTTP 200 when healthy.

```yaml
# Kubernetes deployment
livenessProbe:
  httpGet:
    path: /
    port: 9000
  initialDelaySeconds: 5
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /
    port: 9000
  initialDelaySeconds: 3
  periodSeconds: 5
```

For app-template HelmRelease:
```yaml
controllers:
  main:
    containers:
      main:
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: 9000
              initialDelaySeconds: 5
              periodSeconds: 10
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: 9000
              initialDelaySeconds: 3
              periodSeconds: 5
```

## Audit Logging

KAIT includes a built-in audit wrapper that logs all command executions with timestamps, inputs, outputs, and exit codes.

### Using the Audit Wrapper

Wrap your handler scripts with `audit-wrapper.sh`:

```yaml
# hooks.yaml
- id: my-automation
  execute-command: /app/scripts/audit-wrapper.sh
  pass-arguments-to-command:
    - source: string
      name: /scripts/my-handler.sh  # First arg is the actual script
    - source: payload
      name: alertname
  http-methods: ["POST"]
```

### Audit Log Format

Logs are written to `/tmp/kait-audit.log` in JSON format by default:

```json
{"request_id":"a1b2c3d4","timestamp":"2024-12-07T12:00:00Z","event":"start","command":"/scripts/handler.sh","arguments":["arg1"],"stdin":null}
{"request_id":"a1b2c3d4","timestamp":"2024-12-07T12:00:01Z","event":"complete","exit_code":0,"duration_ms":1234,"output":"Success"}
```

### Persisting Audit Logs

Mount a persistent volume for audit logs:

```yaml
persistence:
  audit:
    type: emptyDir  # or PVC for persistence across restarts
    globalMounts:
      - path: /tmp

env:
  AUDIT_LOG: /tmp/kait-audit.log
  AUDIT_FORMAT: json  # or "text"
```

## Kubernetes Authentication

### kubectl / flux (In-Cluster)

When running inside Kubernetes, kubectl and flux automatically use the mounted ServiceAccount token. Just create appropriate RBAC:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kait
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kait
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "patch"]
  - apiGroups: ["kustomize.toolkit.fluxcd.io"]
    resources: ["kustomizations"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kait
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kait
subjects:
  - kind: ServiceAccount
    name: kait
    namespace: default
```

### talosctl (Requires Secret)

talosctl requires a talosconfig file with certificates. Unlike kubectl which can use ServiceAccount tokens, talosctl needs the actual config file.

#### Option 1: Create Secret directly

```bash
kubectl create secret generic talosconfig \
  --from-file=talosconfig=/path/to/talosconfig
```

#### Option 2: ExternalSecret from 1Password

Since 1Password can't store file attachments in a way ExternalSecrets can read, you need to base64 encode the talosconfig and store it in a password/text field:

**Step 1: Encode your talosconfig**
```bash
# Base64 encode the file (single line, no wrapping)
base64 -w0 < ~/.talos/config

# Copy the output to your clipboard
base64 -w0 < ~/.talos/config | xclip -selection clipboard
```

**Step 2: Store in 1Password**
- Create a new item (e.g., "talos-admin")
- Add a field called `talosconfig-b64`
- Paste the base64 string as the value

**Step 3: Create ExternalSecret with decoding**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: talosconfig
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: talosconfig
    template:
      engineVersion: v2
      data:
        # Decode the base64 string back to the original file
        talosconfig: "{{ .talosconfig_b64 | b64dec }}"
  data:
    - secretKey: talosconfig_b64
      remoteRef:
        key: talos-admin
        property: talosconfig-b64
```

#### Mount in your HelmRelease

```yaml
persistence:
  talosconfig:
    type: secret
    name: talosconfig
    globalMounts:
      - path: /var/run/secrets/talos.dev

env:
  TALOSCONFIG: /var/run/secrets/talos.dev/talosconfig
```

## Adding Extra Tools

Install additional CLI tools at container startup by mounting an `extras.txt` file:

```
# /config/extras.txt
# Format: name|url|version|extract_path(optional)

helm|https://get.helm.sh/helm-v{version}-linux-{arch}.tar.gz|3.16.3|linux-{arch}/helm
cmctl|https://github.com/cert-manager/cmctl/releases/download/v{version}/cmctl_linux_{arch}|2.1.1|
yq|https://github.com/mikefarah/yq/releases/download/v{version}/yq_linux_{arch}|4.44.3|
```

Variables:
- `{version}` - Replaced with the version from the config
- `{arch}` - Replaced with `amd64` or `arm64` based on platform

Mount the extras config:
```yaml
persistence:
  extras:
    type: configMap
    name: kait-extras
    globalMounts:
      - path: /config/extras.txt
        subPath: extras.txt
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WEBHOOK__PORT` | `9000` | Webhook server port |
| `WEBHOOK__URLPREFIX` | `hooks` | URL prefix for webhooks |
| `AUDIT_LOG` | `/tmp/kait-audit.log` | Path to audit log file |
| `AUDIT_FORMAT` | `json` | Audit log format (`json` or `text`) |
| `TALOSCONFIG` | - | Path to talosconfig file |
| `KUBECONFIG` | - | Path to kubeconfig (not needed in-cluster) |

## Building

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t kait:local .
```

## License

MIT
