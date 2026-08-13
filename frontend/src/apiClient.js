import { InteractionRequiredAuthError } from "@azure/msal-browser";
import { apiBaseUrl, apiScopes } from "./authConfig";

/**
 * Acquires a token silently (from cache/refresh, no popup) and calls the
 * backend with it attached as a Bearer header. Falls back to an interactive
 * popup only if silent acquisition genuinely can't succeed (e.g. the user
 * needs to re-consent) - this is the standard MSAL pattern, not something
 * specific to this sample.
 */
export async function callApi(msalInstance, account, path) {
  let tokenResponse;
  try {
    tokenResponse = await msalInstance.acquireTokenSilent({
      scopes: apiScopes,
      account,
    });
  } catch (error) {
    if (error instanceof InteractionRequiredAuthError) {
      tokenResponse = await msalInstance.acquireTokenPopup({ scopes: apiScopes });
    } else {
      throw error;
    }
  }

  const response = await fetch(`${apiBaseUrl}${path}`, {
    headers: {
      Authorization: `Bearer ${tokenResponse.accessToken}`,
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`API call failed: ${response.status} ${body}`);
  }
  return response.json();
}
