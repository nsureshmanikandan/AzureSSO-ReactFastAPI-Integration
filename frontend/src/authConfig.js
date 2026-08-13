/**
 * MSAL configuration - the values below come from the SPA App Registration
 * (Step 1 in the setup guide), NOT the API App Registration (Step 2).
 *
 * All three values are read from environment variables so this file never
 * has to change between dev/test/prod - only your .env file does.
 * Vite exposes anything prefixed VITE_ to import.meta.env at build time.
 */
export const msalConfig = {
  auth: {
    // App registrations > <your SPA app> > Overview > Application (client) ID
    clientId: import.meta.env.VITE_AZURE_CLIENT_ID || "00000000-0000-0000-0000-000000000000",

    // App registrations > <your SPA app> > Overview > Directory (tenant) ID
    authority: `https://login.microsoftonline.com/${import.meta.env.VITE_AZURE_TENANT_ID || "00000000-0000-0000-0000-000000000000"}`,

    // Must exactly match a Redirect URI configured on the SPA app registration
    // (Authentication blade > Single-page application platform).
    redirectUri: import.meta.env.VITE_REDIRECT_URI || "http://localhost:5173",
  },
  cache: {
    cacheLocation: "sessionStorage", // survives page refresh, cleared when the tab closes
    storeAuthStateInCookie: false,
  },
};

/**
 * The scope for YOUR backend API - this is what makes MSAL request a token
 * with the right "audience" (aud claim) for FastAPI to accept.
 *
 * Format: api://<API-app-client-id>/<scope-name>
 * <API-app-client-id> = the API App Registration's Application ID (Step 2).
 * <scope-name>        = whatever you named it under "Expose an API" (Step 2d)
 *                        - "access_as_user" is the convention used in this guide.
 */
export const apiScopes = [
  import.meta.env.VITE_API_SCOPE || "api://00000000-0000-0000-0000-000000000000/access_as_user",
];

export const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
