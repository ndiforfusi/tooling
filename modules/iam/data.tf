data "aws_caller_identity" "current" {}

# If OIDC is enabled, fetch the IdP thumbprint automatically
data "tls_certificate" "oidc" {
  count = var.enable_oidc ? 1 : 0
  url   = var.oidc_issuer_url
}

locals {
  # sha1 thumbprint for the OIDC root CA (first cert typically suffices)
  oidc_thumbprint = var.enable_oidc ? data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint : null

  # Convenience strings
  issuer_host = var.enable_oidc ? replace(var.oidc_issuer_url, "https://", "") : null
}
