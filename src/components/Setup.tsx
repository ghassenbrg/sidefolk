import welcomeArt from "../assets/welcome-companion.png";
import { useEffect, useState } from "react";
import { ArrowRight, Check, ShieldCheck, RefreshCw } from "lucide-react";
import type { Snapshot } from "../../shared/types";
import { api } from "../api";
import { PetIllustration } from "./PetIllustration";
export function Setup({
  state,
  onFinish,
}: {
  state: Snapshot;
  onFinish?: () => void;
}) {
  const [name, setName] = useState(state.settings.petName),
    [provider, setProvider] = useState<"codex" | "claude" | "local">(
      state.setupComplete ? state.settings.provider : "local",
    ),
    [agents, setAgents] = useState<Record<string, string>>({}),
    [checking, setChecking] = useState(true),
    [error, setError] = useState(""),
    [saving, setSaving] = useState(false);
  const detect = async () => {
    setChecking(true);
    try {
      const found = await api.checkAgents();
      setAgents(found);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setChecking(false);
    }
  };
  useEffect(() => {
    void detect();
  }, []);
  return (
    <main className="setup-screen">
      <div className="setup-art">
        <div className="setup-brand">
          sidefolk<span>●</span>
        </div>
        <div className="setup-character">
          <img
            src={welcomeArt}
            alt="A thoughtful rabbit companion with glasses beside a laptop"
          />
        </div>
        <h1>
          A small companion.
          <br />A little less on your mind.
        </h1>
        <p>
          Capture a reminder. Think through an idea.
          <br />
          Get back to what you were doing.
        </p>
        <div className="setup-privacy">
          <ShieldCheck size={15} />
          Your data stays here until you ask an agent.
        </div>
      </div>
      <form
        className="setup-form"
        onSubmit={(e) => {
          e.preventDefault();
          setSaving(true);
          setError("");
          void api
            .finishSetup({ ...state.settings, petName: name, provider })
            .then(() => onFinish?.())
            .catch((e) => setError(e.message))
            .finally(() => setSaving(false));
        }}
      >
        {onFinish && (
          <button
            type="button"
            className="text-button setup-back"
            onClick={onFinish}
          >
            ← Back to workspace
          </button>
        )}
        <span className="eyebrow">WELCOME TO SIDEFOLK</span>
        <h2>Let’s make this useful.</h2>
        <p>Choose how you want to start. You can change everything later.</p>
        <label>
          Your companion’s name
          <input
            autoFocus
            required
            maxLength={24}
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <div className="setup-label">
          <strong>How should I help?</strong>
          <button
            type="button"
            className="text-button"
            onClick={() => void detect()}
            disabled={checking}
          >
            <RefreshCw size={12} />
            Check again
          </button>
        </div>
        <div className="provider-options">
          {(["local", "codex", "claude"] as const).map((p) => {
            const available =
              p === "local" || (!!agents[p] && agents[p] !== "Not installed");
            return (
              <label
                key={p}
                className={`provider-option ${provider === p ? "selected" : ""} ${!available ? "unavailable" : ""}`}
              >
                <input
                  type="radio"
                  name="setup-provider"
                  checked={provider === p}
                  disabled={!available}
                  onChange={() => setProvider(p)}
                />
                <span>
                  <strong>
                    {p === "local"
                      ? "Start without AI"
                      : p === "codex"
                        ? "Codex"
                        : "Claude Code"}
                  </strong>
                  <small>
                    {p === "local"
                      ? "Reminders, to-dos, and saved preferences. No account needed."
                      : checking
                        ? "Checking this computer…"
                        : available
                          ? "CLI found · uses your existing login"
                          : "CLI not found · install and sign in to enable"}
                  </small>
                </span>
              </label>
            );
          })}
        </div>
        <p className="setup-detail">
          {provider === "local"
            ? "Local mode handles clear reminder and task requests. Connect an agent later for open-ended conversation."
            : "CLI detection checks installation, not login or quota. Your first message verifies the connection."}
        </p>
        {error && (
          <div role="alert" className="notice">
            {error}
          </div>
        )}
        <button
          className="button primary setup-submit"
          disabled={saving || checking}
        >
          {saving ? "Setting up…" : "Start using Sidefolk"}
          <ArrowRight size={17} />
        </button>
        <span className="setup-footnote">
          <Check size={12} />
          No background AI calls. No account with Sidefolk.
        </span>
      </form>
    </main>
  );
}
export function ReliabilitySettings({ state }: { state: Snapshot }) {
  const [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<string>) => {
    setBusy(true);
    try {
      setNotice(await fn());
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <section className="settings-card reliability-card">
      <span className="note-kicker">EVERYDAY RELIABILITY</span>
      <h2>Ready when you need it.</h2>
      <div className="reliability-row">
        <div>
          <strong>Quick Ask</strong>
          <p>Open a focused conversation from any app.</p>
          <span className="muted">⌘⇧J on macOS · Ctrl+Shift+J elsewhere</span>
        </div>
        <button
          type="button"
          className="button"
          onClick={() => void api.openQuick()}
        >
          Try Quick Ask
        </button>
      </div>
      {!state.quickShortcutRegistered && (
        <p className="notice">
          Quick Ask shortcut is unavailable. Use the pet’s Talk button or menu
          bar.
        </p>
      )}
      <div className="reliability-row">
        <div>
          <strong>Reminder delivery</strong>
          <p>
            Sidefolk must stay running. Closing its window is fine; quitting
            stops reminders until you reopen it. Quiet time delays
            notifications.
          </p>
        </div>
        <button
          type="button"
          className="button"
          disabled={busy}
          onClick={() =>
            void run(async () => {
              await api.testNotification();
              return "Test sent. If it did not appear, enable Sidefolk in macOS System Settings → Notifications.";
            })
          }
        >
          Test notification
        </button>
      </div>
      <div className="reliability-row">
        <div>
          <strong>Your data, backed up</strong>
          <p>
            Export reminders, memory, settings, and conversations. The backup
            includes personal data and native session IDs.
          </p>
        </div>
        <button
          type="button"
          className="button"
          disabled={busy}
          onClick={() =>
            void run(async () => {
              const path = await api.exportBackup();
              return path ? `Backup saved to ${path}` : "Export cancelled.";
            })
          }
        >
          Export backup
        </button>
      </div>
      {notice && (
        <p role="status" className="notice">
          {notice}
        </p>
      )}
    </section>
  );
}
