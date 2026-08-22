import { useEffect, useRef, useState } from "react";
import { useMsal, useIsAuthenticated } from "@azure/msal-react";
import { callApi } from "./apiClient";
import "./App.css";

function getInitials(name, username) {
  const source = (name || username || "?").trim();
  const parts = source.split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function UserMenu({ account, onSignOut }) {
  const [open, setOpen] = useState(false);
  const menuRef = useRef(null);

  useEffect(() => {
    function handleClickOutside(event) {
      if (menuRef.current && !menuRef.current.contains(event.target)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const name = account?.name || account?.username;
  const initials = getInitials(account?.name, account?.username);

  return (
    <div className="user-menu" ref={menuRef}>
      <button
        type="button"
        className="user-menu-trigger"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
      >
        <span className="user-avatar">{initials}</span>
        <span className="user-menu-name">
          <strong>{name}</strong>
          <small>Signed in</small>
        </span>
        <span className="user-menu-caret">&#9662;</span>
      </button>

      {open && (
        <div className="user-menu-dropdown">
          <div className="user-menu-dropdown-header">
            <span className="user-avatar">{initials}</span>
            <div>
              <strong>{account?.name}</strong>
              <span>{account?.username}</span>
            </div>
          </div>
          <button className="btn btn-danger-outline signout-btn" onClick={onSignOut}>
            Sign out
          </button>
        </div>
      )}
    </div>
  );
}

export default function App() {
  const { instance, accounts } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  const [profile, setProfile] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  const account = accounts[0];

  const login = () => instance.loginRedirect({ scopes: ["User.Read"] });
  const logout = () => instance.logoutRedirect();

  const callProfile = async () => {
    setError(null);
    setProfile(null);
    setLoading(true);
    try {
      const data = await callApi(instance, account, "/api/profile");
      setProfile(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-brand">
          <div className="app-brand-mark">CTC</div>
          <div className="app-brand-text">
            <h1>CTC SSO Sample</h1>
            <span>React (MSAL) → FastAPI, via Azure Entra ID</span>
          </div>
        </div>

        <div className="app-header-actions">
          {isAuthenticated ? (
            <UserMenu account={account} onSignOut={logout} />
          ) : (
            <button className="btn btn-primary app-signin-btn" onClick={login}>
              Sign in with Microsoft
            </button>
          )}
        </div>
      </header>

      <main className="app-main">
        <div className="app-main-inner">
          {!isAuthenticated && (
            <div className="hero-card">
              <div className="hero-icon">&#128274;</div>
              <h2>Secure single sign-on, end to end</h2>
              <p>
                Sign in with your Microsoft account to establish an Entra ID session
                in the browser, then call a JWT-protected FastAPI endpoint using the
                token MSAL acquires for you.
              </p>
              <button className="btn btn-primary" onClick={login}>
                Sign in with Microsoft
              </button>
            </div>
          )}

          {isAuthenticated && (
            <>
              <div className="panel">
                <div className="panel-header">
                  <div>
                    <h2>Account overview</h2>
                    <p>Session details from the active MSAL account</p>
                  </div>
                  <span className="badge">
                    <span className="badge-dot" />
                    Authenticated
                  </span>
                </div>
                <div className="panel-body">
                  <div className="info-grid">
                    <div className="info-item">
                      <span>Name</span>
                      <strong>{account?.name || "—"}</strong>
                    </div>
                    <div className="info-item">
                      <span>Username</span>
                      <strong>{account?.username || "—"}</strong>
                    </div>
                  </div>
                </div>
              </div>

              <div className="panel">
                <div className="panel-header">
                  <div>
                    <h2>Protected API</h2>
                    <p>Calls /api/profile with a bearer token acquired via MSAL</p>
                  </div>
                </div>
                <div className="panel-body">
                  <div className="action-row">
                    <button className="btn btn-primary" onClick={callProfile} disabled={loading}>
                      {loading ? "Calling…" : "Call protected API (/api/profile)"}
                    </button>
                  </div>

                  {profile && (
                    <div className="result-block">
                      <div className="result-block-label">Response</div>
                      <pre className="json-viewer">{JSON.stringify(profile, null, 2)}</pre>
                    </div>
                  )}

                  {error && (
                    <div className="error-banner">
                      <span>&#9888;</span>
                      <span>{error}</span>
                    </div>
                  )}
                </div>
              </div>
            </>
          )}
        </div>
      </main>

      <footer className="app-footer">
        <p>&copy; {new Date().getFullYear()} CTC SSO Sample. Internal demo — Azure Entra ID integration.</p>
      </footer>
    </div>
  );
}
