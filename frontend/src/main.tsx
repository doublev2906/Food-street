import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import "./index.css";
import App from "./App";
import { AuthProvider } from "./auth";
import { CursorEffects } from "./cursor-effects";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <CursorEffects />
    <BrowserRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>
);
