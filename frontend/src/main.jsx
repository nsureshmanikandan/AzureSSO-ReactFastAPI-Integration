import React from "react";
import ReactDOM from "react-dom/client";
import { PublicClientApplication, EventType } from "@azure/msal-browser";
import { MsalProvider } from "@azure/msal-react";
import { msalConfig } from "./authConfig";
import App from "./App.jsx";

const msalInstance = new PublicClientApplication(msalConfig);

// MSAL v3 requires initialize() to resolve before anything using useMsal()
// renders. Top-level `await` isn't supported by every build target, so this
// uses an async bootstrap function instead - the pattern MSAL's own React
// samples use.
async function bootstrap() {
  await msalInstance.initialize();

  // Keep the "active account" in sync so useMsal()/accounts[0] always
  // reflects whoever most recently signed in - matters once you support
  // multiple accounts.
  msalInstance.addEventCallback((event) => {
    if (event.eventType === EventType.LOGIN_SUCCESS && event.payload?.account) {
      msalInstance.setActiveAccount(event.payload.account);
    }
  });

  const existingAccounts = msalInstance.getAllAccounts();
  if (existingAccounts.length > 0) {
    msalInstance.setActiveAccount(existingAccounts[0]);
  }

  ReactDOM.createRoot(document.getElementById("root")).render(
    <React.StrictMode>
      <MsalProvider instance={msalInstance}>
        <App />
      </MsalProvider>
    </React.StrictMode>
  );
}

bootstrap();
