"""Settings for the sample backend.

Everything here is read from environment variables so the same code runs
locally (.env file) and in AKS/App Service (real env vars / Key Vault
references) without any code change - only configuration changes.
"""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # -- Azure AD (Entra ID) tenant + the BACKEND API's own App Registration --
    # This is the "audience" the backend expects on every token - i.e. the
    # Application ID URI or Client ID you set up in Step 2 of the setup guide
    # (the API app registration, not the SPA app registration).
    azure_tenant_id: str = "00000000-0000-0000-0000-000000000000"
    azure_api_client_id: str = "00000000-0000-0000-0000-000000000000"

    # The full expected "aud" claim value - i.e. the API App Registration's
    # actual Application ID URI (Azure Portal > App registrations > your API
    # app > Expose an API). Leave unset to use the "api://<client-id>"
    # default convention. Some orgs use a custom Application ID URI instead
    # (e.g. "https://<tenant>.onmicrosoft.com/<custom-spn-name>") - if so,
    # set AZURE_API_AUDIENCE to that exact string, or tokens will always
    # fail audience validation even though the client ID/tenant are correct.
    azure_api_audience: str | None = None

    # Set to True once APIM is in front of this API and its validate-jwt
    # policy is doing the token check - the backend then trusts APIM's
    # injected X-User-Id / X-User-Roles headers instead of re-parsing the
    # raw token itself. Set to False for local development (React calling
    # FastAPI directly, no APIM in the path) or if you want defense-in-depth
    # double validation even behind APIM.
    trust_apim_headers: bool = False

    # CORS - the origin(s) your React dev server / hosted SPA run on.
    allowed_origins: list[str] = ["http://localhost:5173"]

    @property
    def expected_audience(self) -> str:
        return self.azure_api_audience or f"api://{self.azure_api_client_id}"

    @property
    def valid_audiences(self) -> set[str]:
        # Mirrors the issuer situation: Azure AD v2.0 access tokens carry the
        # bare client-ID GUID as `aud`, while v1.0 tokens (and APIM's
        # validate-jwt policy, which expects the Application ID URI) use the
        # full "api://<client-id>" form. Accept either - both are legitimate
        # depending on which token version was actually issued.
        return {self.expected_audience, self.azure_api_client_id}

    @property
    def issuer(self) -> str:
        return f"https://login.microsoftonline.com/{self.azure_tenant_id}/v2.0"

    @property
    def issuer_v1(self) -> str:
        # Azure AD issues v1.0-format tokens (this issuer shape) when a
        # client requests a token for ITSELF - i.e. one combined app playing
        # both the SPA and API roles, as configured for this project. This
        # happens regardless of the API app's accessTokenAcceptedVersion
        # manifest setting, which only affects tokens requested by a
        # DIFFERENT client. Both this and `issuer` are legitimate tokens
        # from the same real tenant - just two different token versions.
        return f"https://sts.windows.net/{self.azure_tenant_id}/"

    @property
    def valid_issuers(self) -> set[str]:
        return {self.issuer, self.issuer_v1}

    @property
    def jwks_uri(self) -> str:
        return f"https://login.microsoftonline.com/{self.azure_tenant_id}/discovery/v2.0/keys"


settings = Settings()
