import { useState } from "react";
import { useMsal, useIsAuthenticated } from "@azure/msal-react";
import { callApi } from "./apiClient";

/**
 * Minimal proof-of-life UI: login, show the signed-in user, call the
 * protected backend endpoint, show what it returned. Everything else in a
 * real app (routing, layout, design system) is irrelevant to the SSO wiring
 * this sample exists to demonstrate.
 */
export default function App() {
  const { instance, accounts } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState(null);

  const login = () => instance.loginPopup({ scopes: ["User.Read"] });
  const logout = () => instance.logoutPopup();

  const callProfile = async () => {
    setError(null);
    setProfile(null);
    try {
      const data = await callApi(instance, accounts[0], "/api/profile");
      setProfile(data);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div style={{ fontFamily: "sans-serif", maxWidth: 640, margin: "3rem auto" }}>
      <h1>CTC SSO Sample</h1>
      <p>React (MSAL) → FastAPI, via Azure Entra ID.</p>

      {!isAuthenticated && <button onClick={login}>Sign in with Microsoft</button>}

      {isAuthenticated && (
        <>
          <p>Signed in as <strong>{accounts[0]?.username}</strong></p>
          <button onClick={callProfile}>Call protected API (/api/profile)</button>
          <button onClick={logout} style={{ marginLeft: 8 }}>Sign out</button>

          {profile && (
            <pre style={{ background: "#f2f2f2", padding: "1rem", marginTop: "1rem" }}>
              {JSON.stringify(profile, null, 2)}
            </pre>
          )}
          {error && <p style={{ color: "crimson" }}>Error: {error}</p>}
        </>
      )}
    </div>
  );
}
