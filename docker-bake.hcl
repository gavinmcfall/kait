target "docker-metadata-action" {}

variable "APP" {
  default = "kait"
}

// Tool versions - Renovate will update these automatically
variable "WEBHOOK_VERSION" {
  // renovate: datasource=github-releases depName=adnanh/webhook
  default = "2.8.2"
}

variable "KUBECTL_VERSION" {
  // renovate: datasource=github-releases depName=kubernetes/kubernetes
  default = "1.31.4"
}

variable "TALOSCTL_VERSION" {
  // renovate: datasource=github-releases depName=siderolabs/talos
  default = "1.9.1"
}

variable "FLUX_VERSION" {
  // renovate: datasource=github-releases depName=fluxcd/flux2
  default = "2.4.0"
}

variable "SOURCE" {
  default = "https://github.com/gavinmcfall/kait"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    WEBHOOK_VERSION  = "${WEBHOOK_VERSION}"
    KUBECTL_VERSION  = "${KUBECTL_VERSION}"
    TALOSCTL_VERSION = "${TALOSCTL_VERSION}"
    FLUX_VERSION     = "${FLUX_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:local"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
