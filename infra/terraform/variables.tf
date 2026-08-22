variable "tenant_id" {
  description = "Your Entra ID tenant ID (Azure Portal > Microsoft Entra ID > Overview)"
  type        = string
}

variable "environment" {
  description = "Environment short name, used in the app registration's enterprise-standard display name: corpapps-<environment>-itp-backend-apim-spn"
  type        = string
  default     = "dev"
}

variable "redirect_uris" {
  description = "SPA redirect URIs - must match VITE_REDIRECT_URI in frontend/.env.local. Azure AD requires a trailing slash on any URI with no path segment."
  type        = list(string)
  default = [
    "http://localhost:5173/",
    "http://localhost:5173/auth/callback/",
    "https://corpapps-itp-dev.corp.ad.ctc/",
    "https://proud-ground-00667a40f.7.azurestaticapps.net/",
  ]
}

variable "identifier_uri_override" {
  description = "Set this to use a custom Application ID URI (e.g. \"https://<tenant>.onmicrosoft.com/<custom-spn-name>\") matching your org's real APIM-fronted apps, instead of the default api://<client_id>. Leave blank for the default."
  type        = string
  default     = ""
}

variable "create_ad_groups" {
  description = "If true, create the demo AD groups below. If false, look them up (they must already exist)."
  type        = bool
  default     = true
}

variable "ad_groups" {
  description = "Role key -> AD group display name. Each group (except generate_token, which has no group - it's an Application-only role) gets assigned to the matching app role."
  type        = map(string)
  default = {
    tax_admin           = "ITP-Demo-TaxAdmin"
    ig_admin             = "ITP-Demo-IGAdmin"
    tax_member           = "ITP-Demo-TaxMember"
    ig_member            = "ITP-Demo-IGMember"
    business_requestor   = "ITP-Demo-BusinessRequestor"
    technical_user       = "ITP-Demo-TechnicalUser"
    devops_team          = "ITP-Demo-DevOpsTeam"
  }
}

variable "grant_admin_consent" {
  description = "Grant admin consent automatically. Only works if the identity running Terraform is an admin on this tenant - true is fine for a personal/sandbox tenant."
  type        = bool
  default     = true
}
