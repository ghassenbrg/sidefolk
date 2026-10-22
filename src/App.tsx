import {
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowUp,
  Bell,
  Brain,
  Check,
  ChevronRight,
  Clock3,
  ExternalLink,
  FolderOpen,
  Home,
  Leaf,
  LoaderCircle,
  MessageCircle,
  Moon,
  Plus,
  Settings as SettingsIcon,
  Sparkles,
  Square,
  Terminal,
  Trash2,
  X,
  Zap,
  Pencil,
  BookOpen,
} from "lucide-react";
import type { Item, Memory, Settings, Skill, Snapshot } from "../shared/types";
import { api } from "./api";
import { visibleAgentText } from "../shared/protocol";
import Pet from "./components/Pet";

type Page = "home" | "memory" | "skills" | "workshop" | "settings";
const nav: { id: Page; label: string; icon: typeof Home }[] = [
  { id: "home", label: "Your companion", icon: Home },
  { id: "memory", label: "Memory", icon: Brain },
  { id: "skills", label: "Skills", icon: Sparkles },
  { id: "workshop", label: "Workshop", icon: Terminal },
];
const dateLabel = (time: number) =>
  new Date(time).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
const compact = (n: number) =>
  Intl.NumberFormat(undefined, {
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(n);

export default function App() {
  const [state, setState] = useState<Snapshot | null>(null);
  const [page, setPage] = useState<Page>("home");
  const [error, setError] = useState("");
  const floating = location.hash === "#pet";
  const act = async (fn: () => Promise<unknown>) => {
    try {
      await fn();
    } catch (e) {
      setError(
        (e as Error).message.replace(
          /^Error invoking remote method '[^']+': Error: /,
          "",
        ),
      );
    }
  };
  useEffect(() => {
    if (!api) return;
    let alive = true;
    const off = api.onState((s) => {
      if (alive) setState(s);
    });
    api
      .snapshot()
      .then((s) => {
        if (alive) setState(s);
      })
      .catch((e) => setError(e.message));
    return () => {
      alive = false;
      off();
    };
  }, []);
  useEffect(() => {
    if (!error) return;
    const id = setTimeout(() => setError(""), 7000);
    return () => clearTimeout(id);
  }, [error]);
  useEffect(() => {
    document.body.classList.toggle("pet-mode", floating);
    document.documentElement.classList.toggle("pet-mode", floating);
  }, [floating]);
  useEffect(() => {
    if (!floating || !api) return;
    let last = false;
    const hover = (event: MouseEvent) => {
      const target = event.target as Element;
      let interactive = !!target.closest("button, .pet-drag");
      const canvas = document.querySelector("canvas");
      if (canvas) {
        const r = canvas.getBoundingClientRect();
        const dx = (event.clientX - r.left - r.width * 0.5) / (r.width * 0.34);
        const dy =
          (event.clientY - r.top - r.height * 0.43) / (r.height * 0.46);
        interactive ||= dx * dx + dy * dy < 1;
      }
      if (interactive !== last) {
        last = interactive;
        void api.petInteractive(interactive);
      }
    };
    document.addEventListener("mousemove", hover);
    return () => document.removeEventListener("mousemove", hover);
  }, [floating]);
  if (!api)
    return (
      <div className="browser-notice">
        <Leaf size={36} />
        <h1>Sidefolk lives on your desktop.</h1>
        <p>Start the desktop app from the project folder:</p>
        <code>npm run dev</code>
        <p>
          The desktop app connects your pet to agents, memory, and native
          reminders.
        </p>
      </div>
    );
  if (!state)
    return (
      <div className="loading">
        <LoaderCircle className="spin" /> Waking up your companion… {error}
      </div>
    );
  const settings = state.settings;
  const due = state.items.filter((i) => i.status === "due");
  const mood = settings.focus
    ? "sleeping"
    : state.agent || state.job?.status === "running"
      ? "working"
      : due.length
        ? "reminder"
        : "idle";
  const update = (value: Partial<Settings>) =>
    act(() => api.settings({ ...settings, ...value }));
  if (floating)
    return (
      <div className="floating-pet">
        <div className="pet-drag" title="Drag to move">
          <span className="grip">⠿</span>
          <span>{settings.petName}</span>
        </div>
        <button
          className="pet-bubble"
          onClick={() => void act(() => api.openHome())}
        >
          {due.length
            ? `A little reminder: ${due[0].title}`
            : state.agent
              ? "On it! Come see what I’m doing."
              : settings.focus
                ? "A little quiet company."
                : "Got something on your mind?"}
          <ChevronRight size={14} />
        </button>
        <Pet
          color={settings.color}
          mood={mood}
          floating
          onPet={() => void act(() => api.openHome())}
        />
        <div className="floating-actions">
          <button onClick={() => void act(() => api.openHome())}>
            <MessageCircle size={13} /> Talk
          </button>
          <button
            aria-label="Hide desktop companion"
            onClick={() => void update({ petVisible: false })}
          >
            <X size={14} />
          </button>
        </div>
      </div>
    );
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="window-drag" />
        <a
          className="brand"
          href="#"
          onClick={(e) => {
            e.preventDefault();
            setPage("home");
          }}
        >
          <span className="brand-mark">
            <Leaf size={23} />
          </span>
          sidefolk<span className="brand-dot">.</span>
        </a>
        <div className="sidebar-label">A LITTLE COMPANY</div>
        <nav>
          {nav.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              className={`nav-item ${page === id ? "active" : ""}`}
              onClick={() => setPage(id)}
            >
              <Icon size={18} />
              {label}
              {id === "memory" &&
                state.memories.some((m) => m.source === "suggested") && (
                  <span className="nav-dot" />
                )}
            </button>
          ))}
        </nav>
        <div className="sidebar-label sessions-heading">
          CONVERSATIONS
          <button
            className="icon-button"
            aria-label="New conversation"
            disabled={!!state.agent}
            onClick={() => void act(() => api.newSession())}
          >
            <Plus size={15} />
          </button>
        </div>
        <div className="sessions">
          {state.sessions.slice(0, 7).map((session) => (
            <button
              key={session.id}
              disabled={!!state.agent}
              title={session.title}
              className={`session ${state.activeSessionId === session.id ? "selected" : ""}`}
              onClick={() => {
                setPage("home");
                void act(() => api.switchSession(session.id));
              }}
            >
              <MessageCircle size={14} />
              <span>{session.title}</span>
            </button>
          ))}
        </div>
        <div className="sidebar-bottom">
          <div className="economy-note">
            <span className="small-icon">
              <Zap size={15} />
            </span>
            <div>
              <strong>
                {settings.economy
                  ? "Small footprint. Big help."
                  : "Ready when you are."}
              </strong>
              <span>No AI calls while idle.</span>
            </div>
          </div>
          <button
            className={`nav-item ${page === "settings" ? "active" : ""}`}
            onClick={() => setPage("settings")}
          >
            <SettingsIcon size={18} />
            Settings<span className="version">v0.1</span>
          </button>
        </div>
      </aside>
      <main className="main">
        <header className="topbar">
          <span>
            <span className="status-dot" />
            Your little corner of the desktop
          </span>
          <span className="topbar-right">
            <span className="keycap">LOCAL MEMORY</span>
            <span className="divider" />
            <span>
              {new Intl.DateTimeFormat(undefined, {
                month: "short",
                day: "numeric",
              }).format(new Date())}
            </span>
          </span>
        </header>
        <div className="page-content">
          <div className="page-heading">
            <div>
              <div className="eyebrow">
                {page === "home"
                  ? "GOOD COMPANY. LESS ON YOUR MIND."
                  : "A COMPANION THAT GROWS WITH YOU"}
              </div>
              <h1>
                {page === "home" ? (
                  <>
                    Meet {settings.petName}
                    <span className="heading-spark">✳</span>
                  </>
                ) : page === "memory" ? (
                  "A little room for memory."
                ) : page === "skills" ? (
                  "A few useful superpowers."
                ) : page === "workshop" ? (
                  "Let’s make something."
                ) : (
                  "Make yourself at home."
                )}
              </h1>
              <p>
                {page === "home"
                  ? "A friend for the small things. An agent for the big ones."
                  : page === "memory"
                    ? "What your companion remembers, across conversations and agents."
                    : page === "skills"
                      ? "Teach your companion how you like things done."
                      : page === "workshop"
                        ? "Connect a project. Explore it, run it, and build together."
                        : "Your pet, your agent, your way of working."}
              </p>
            </div>
            {page === "home" && (
              <div className="heading-actions">
                <button
                  className={`button subtle ${settings.focus ? "is-on" : ""}`}
                  onClick={() => void update({ focus: !settings.focus })}
                  disabled={!!state.agent}
                >
                  <Moon size={15} />
                  {settings.focus ? "Quiet time on" : "Quiet time"}
                </button>
                <button
                  className="button"
                  onClick={() =>
                    void update({ petVisible: !settings.petVisible })
                  }
                  disabled={!!state.agent}
                >
                  <ExternalLink size={15} />
                  {settings.petVisible ? "Bring pet home" : "Let pet roam"}
                </button>
              </div>
            )}
          </div>
          {state.storageWarning && (
            <div className="notice">{state.storageWarning}</div>
          )}
          {page === "home" && (
            <div className="home-grid">
              <div className="companion-column">
                <section className="companion-card">
                  <div className="card-kicker">
                    <span>
                      <span className="status-dot" />
                      {mood === "working"
                        ? "A LITTLE BUSY"
                        : mood === "sleeping"
                          ? "QUIET COMPANY"
                          : "HAPPY TO BE HERE"}
                    </span>
                    <span className="pill">YOUR COMPANION</span>
                  </div>
                  <div className="pet-scene">
                    <span className="scene-doodle doodle-one">✧</span>
                    <span className="scene-doodle doodle-two">✳</span>
                    <span className="scene-doodle doodle-three">·</span>
                    <div className="scene-floor" />
                    <Pet color={settings.color} mood={mood} />
                  </div>
                  <div className="companion-intro">
                    <h2>
                      {settings.petName}
                      <span className="tiny-leaf">🌱</span>
                    </h2>
                    <p>
                      {mood === "working"
                        ? "Little paws. Working on big things."
                        : mood === "sleeping"
                          ? "I’ll keep things quiet for a while."
                          : due.length
                            ? "I have something for you to remember."
                            : "A little curious. Always on your side."}
                    </p>
                  </div>
                  <div className="companion-footer">
                    <span>
                      <Brain size={13} />
                      {
                        state.memories.filter((m) => m.source === "you").length
                      }{" "}
                      memories
                    </span>
                    <button onClick={() => setPage("settings")}>
                      <Pencil size={12} />
                      Make me yours
                    </button>
                  </div>
                </section>
                <TaskList items={state.items} act={act} />
              </div>
              <Chat
                state={state}
                act={act}
                openSettings={() => setPage("settings")}
              />
            </div>
          )}
          {page === "memory" && <MemoryPanel state={state} act={act} />}
          {page === "skills" && <SkillsPanel state={state} act={act} />}
          {page === "workshop" && <Workshop state={state} act={act} />}
          {page === "settings" && <SettingsPanel state={state} act={act} />}
          <footer className="page-footer">
            <Leaf size={12} />
            <span>A little company. A lot more possible.</span>
            <span className="footer-right">
              {settings.economy ? "Economy mode" : "Standard mode"}
              <span>·</span>
              {state.usage.turns} agent turns<span>·</span>
              {compact(state.usage.output)} output tokens
            </span>
          </footer>
        </div>
      </main>
      {error && (
        <div role="alert" className="toast">
          <span>{error}</span>
          <button aria-label="Dismiss error" onClick={() => setError("")}>
            <X size={16} />
          </button>
        </div>
      )}
    </div>
  );
}
type Act = (fn: () => Promise<unknown>) => Promise<void>;
function Chat({
  state,
  act,
  openSettings,
}: {
  state: Snapshot;
  act: Act;
  openSettings: () => void;
}) {
  const [text, setText] = useState(""),
    [sending, setSending] = useState(false);
  const scroll = useRef<HTMLDivElement>(null),
    input = useRef<HTMLTextAreaElement>(null);
  const session = state.sessions.find((s) => s.id === state.activeSessionId)!;
  const busy = sending || !!state.agent;
  useEffect(() => {
    scroll.current?.scrollTo({
      top: scroll.current.scrollHeight,
      behavior: "smooth",
    });
  }, [session.messages.length, state.agent?.text, state.agent?.activity]);
  const send = async (value = text) => {
    if (!value.trim() || busy) return;
    setSending(true);
    await act(() => api!.chat(value.trim()));
    setText("");
    setSending(false);
    input.current?.focus();
  };
  return (
    <section className="chat-card">
      <div className="chat-header">
        <div className="chat-title">
          <MessageCircle size={17} />
          <strong>A little conversation</strong>
        </div>
        <button className="provider-badge" onClick={openSettings}>
          <span className="status-dot" />
          {state.settings.provider === "local"
            ? "Local mode"
            : state.settings.provider === "codex"
              ? "Codex"
              : "Claude Code"}
          <ChevronRight size={12} />
        </button>
      </div>
      <div className="chat-scroll" ref={scroll} aria-live="polite">
        <div className="chat-date">THE START OF SOMETHING GOOD</div>
        {!session.messages.length && (
          <div className="chat-empty">
            <span>✳</span>
            <h3>A fresh little adventure.</h3>
            <p>What’s on your mind?</p>
          </div>
        )}
        {session.messages.map((message) => (
          <div className={`message ${message.role}`} key={message.id}>
            {message.role === "assistant" && (
              <span className="message-avatar">
                <Leaf size={15} />
              </span>
            )}
            <div>
              <span className="message-name">
                {message.role === "assistant" ? state.settings.petName : "You"}
                <time>
                  {new Date(message.createdAt).toLocaleTimeString([], {
                    hour: "numeric",
                    minute: "2-digit",
                  })}
                </time>
              </span>
              <div className="message-text">{message.text}</div>
            </div>
          </div>
        ))}
        {state.agent && (
          <div className="message assistant">
            <span className="message-avatar">
              <Leaf size={15} />
            </span>
            <div>
              <span className="message-name">
                {state.settings.petName}
                <span className="thinking-dots">•••</span>
              </span>
              <div className="agent-activity">
                <LoaderCircle size={13} className="spin" />
                {state.agent.activity}
              </div>
              {state.agent.text && (
                <div className="message-text">
                  {visibleAgentText(state.agent.text)}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
      {state.pendingReminder && !busy && (
        <div className="quick-replies">
          {["in an hour", "tomorrow at 9am", "next Friday at 3pm"].map(
            (label) => (
              <button key={label} onClick={() => void send(label)}>
                <Clock3 size={12} />
                {label}
              </button>
            ),
          )}
        </div>
      )}
      <div className="chat-bottom">
        <div className="suggestions">
          {[
            "Remind me to stretch in 1 hour",
            "Remember that I prefer short answers",
            "What can we build together?",
          ].map((prompt, i) => (
            <button
              key={prompt}
              disabled={busy}
              onClick={() => {
                setText(prompt);
                input.current?.focus();
              }}
            >
              {i === 0 ? (
                <Bell size={13} />
              ) : i === 1 ? (
                <Brain size={13} />
              ) : (
                <Sparkles size={13} />
              )}{" "}
              {
                ["Remember something", "Teach a preference", "Make something"][
                  i
                ]
              }
              <span>↗</span>
            </button>
          ))}
        </div>
        <form
          className="composer"
          onSubmit={(e) => {
            e.preventDefault();
            void send();
          }}
        >
          <textarea
            ref={input}
            aria-label="Message your companion"
            placeholder={`Tell ${state.settings.petName} what’s on your mind…`}
            value={text}
            rows={2}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (
                e.key === "Enter" &&
                !e.shiftKey &&
                !e.nativeEvent.isComposing
              ) {
                e.preventDefault();
                void send();
              }
            }}
          />
          <div className="composer-bottom">
            <span>
              <span className="mini-spark">✳</span>Big ideas. Small reminders.
              Anything.
            </span>
            {state.agent ? (
              <button
                type="button"
                className="send-button stop"
                aria-label="Stop agent"
                onClick={() => void act(() => api!.stopAgent())}
              >
                <Square size={16} />
              </button>
            ) : (
              <button
                className="send-button"
                aria-label="Send message"
                disabled={!text.trim() || sending}
              >
                {sending ? (
                  <LoaderCircle size={18} className="spin" />
                ) : (
                  <ArrowUp size={19} />
                )}
              </button>
            )}
          </div>
        </form>
        <div className="composer-note">
          <Zap size={11} />
          Reminders & todos stay local. AI only when it helps.
        </div>
      </div>
    </section>
  );
}
function TaskList({ items, act }: { items: Item[]; act: Act }) {
  const [showDone, setShowDone] = useState(false);
  const active = items.filter((i) => i.status !== "done"),
    done = items.filter((i) => i.status === "done");
  return (
    <section className="tasks-card">
      <div className="section-title">
        <h3>
          <Bell size={16} />
          On your mind
        </h3>
        <span className="count">{active.length}</span>
      </div>
      {!active.length && (
        <div className="empty-tasks">
          <span className="empty-sun">☀</span>
          <p>A little breathing room.</p>
          <span>Ask your companion to remember something.</span>
        </div>
      )}
      <div className="task-items">
        {(showDone ? items : active).map((item) => (
          <div key={item.id} className={`task-row ${item.status}`}>
            <button
              className="task-check"
              aria-label={`${item.status === "done" ? "Reopen" : "Complete"} ${item.title}`}
              onClick={() =>
                void act(() =>
                  api!.item(
                    item.id,
                    item.status === "done" ? "reopen" : "done",
                  ),
                )
              }
            >
              {item.status === "done" && <Check size={12} />}
            </button>
            <div className="task-info">
              <strong>{item.title}</strong>
              <span>
                {item.dueAt ? (
                  <>
                    <Clock3 size={10} />
                    {item.status === "due" ? "Ready now · " : ""}
                    {dateLabel(item.dueAt)}
                  </>
                ) : (
                  "A little to-do"
                )}
              </span>
            </div>
            <div className="task-actions">
              {item.kind === "reminder" && item.status !== "done" && (
                <button
                  aria-label={`Snooze ${item.title} for 30 minutes`}
                  title="Snooze 30 minutes"
                  onClick={() => void act(() => api!.item(item.id, "snooze"))}
                >
                  <Clock3 size={13} />
                </button>
              )}
              <button
                aria-label={`Delete ${item.title}`}
                onClick={() => void act(() => api!.item(item.id, "delete"))}
              >
                <X size={13} />
              </button>
            </div>
          </div>
        ))}
      </div>
      {done.length > 0 && (
        <button
          className="text-button completed-toggle"
          onClick={() => setShowDone(!showDone)}
        >
          {showDone ? "Hide" : "Show"} {done.length} completed
        </button>
      )}
      <div className="task-footnote">
        “Remind me to call Alex tomorrow at 3.”
      </div>
    </section>
  );
}
function MemoryPanel({ state, act }: { state: Snapshot; act: Act }) {
  const [text, setText] = useState("");
  const confirmed = state.memories.filter((m) => m.source === "you"),
    suggested = state.memories.filter((m) => m.source === "suggested");
  return (
    <div className="panel-stack">
      <div className="info-banner">
        <Brain size={23} />
        <div>
          <strong>Same friend. A different brain.</strong>
          <p>
            Confirmed memories follow your companion between Codex and Claude.
            Only a small, relevant selection is sent with each request.
          </p>
        </div>
      </div>
      <form
        className="inline-form"
        onSubmit={(e) => {
          e.preventDefault();
          if (text.trim())
            void act(async () => {
              await api!.addMemory(text);
              setText("");
            });
        }}
      >
        <input
          aria-label="New memory"
          placeholder="Something about you worth remembering…"
          value={text}
          onChange={(e) => setText(e.target.value)}
          maxLength={1200}
        />
        <button className="button primary" disabled={!text.trim()}>
          <Plus size={15} />
          Add memory
        </button>
      </form>
      {!!suggested.length && (
        <section>
          <h3 className="subheading">
            A little thing I noticed <span className="pill">YOUR SAY</span>
          </h3>
          <p className="muted">
            Suggestions are only used after you accept them.
          </p>
          <div className="memory-grid">
            {suggested.map((memory) => (
              <article className="note-card suggested" key={memory.id}>
                <span className="note-kicker">
                  <Sparkles size={13} />
                  SUGGESTED MEMORY
                </span>
                <p>{memory.text}</p>
                <div className="note-actions">
                  <button
                    className="button primary small"
                    onClick={() =>
                      void act(() => api!.memory(memory.id, "accept"))
                    }
                  >
                    <Check size={13} />
                    Remember this
                  </button>
                  <button
                    className="icon-button"
                    aria-label="Dismiss suggestion"
                    onClick={() =>
                      void act(() => api!.memory(memory.id, "delete"))
                    }
                  >
                    <X size={15} />
                  </button>
                </div>
              </article>
            ))}
          </div>
        </section>
      )}
      <section>
        <h3 className="subheading">
          Things I know about you{" "}
          <span className="count">{confirmed.length}</span>
        </h3>
        {!confirmed.length ? (
          <Empty
            icon={<Brain />}
            title="Every friendship starts somewhere."
            text="Try: “Remember that I prefer pnpm and TypeScript.”"
          />
        ) : (
          <div className="memory-grid">
            {confirmed.map((memory) => (
              <MemoryNote key={memory.id} memory={memory} act={act} />
            ))}
          </div>
        )}
      </section>
      <p className="panel-footnote">
        Memory is saved on this computer. Forget a note here to stop including
        it in future prompts. Past agent conversations may still contain it.
      </p>
    </div>
  );
}
function MemoryNote({ memory, act }: { memory: Memory; act: Act }) {
  const [editing, setEditing] = useState(false),
    [text, setText] = useState(memory.text);
  return (
    <article className="note-card">
      <span className="note-kicker">
        <Leaf size={13} />
        LEARNED FROM YOU
      </span>
      {editing ? (
        <textarea
          aria-label="Edit memory"
          value={text}
          maxLength={1200}
          rows={4}
          onChange={(e) => setText(e.target.value)}
          style={{ margin: "15px 0", width: "100%", fontSize: 11 }}
        />
      ) : (
        <p>{memory.text}</p>
      )}
      <div className="note-actions">
        {editing ? (
          <>
            <button
              className="button small primary"
              disabled={!text.trim()}
              onClick={() =>
                void act(async () => {
                  await api!.addMemory(text, memory.id);
                  setEditing(false);
                })
              }
            >
              Save memory
            </button>
            <button
              className="text-button"
              onClick={() => {
                setEditing(false);
                setText(memory.text);
              }}
            >
              Cancel
            </button>
          </>
        ) : (
          <>
            <span className="muted">
              {new Date(memory.createdAt).toLocaleDateString()}
            </span>
            <div>
              <button
                className="icon-button"
                aria-label={`Edit ${memory.text}`}
                onClick={() => setEditing(true)}
              >
                <Pencil size={14} />
              </button>
              <button
                className="icon-button"
                aria-label={`Forget ${memory.text}`}
                onClick={() => void act(() => api!.memory(memory.id, "delete"))}
              >
                <Trash2 size={14} />
              </button>
            </div>
          </>
        )}
      </div>
    </article>
  );
}
function SkillsPanel({ state, act }: { state: Snapshot; act: Act }) {
  const [editing, setEditing] = useState<Skill | null>(null);
  return (
    <div className="panel-stack">
      <div className="section-toolbar">
        <div>
          <h3 className="subheading">A toolkit with personality</h3>
          <p className="muted">
            Reusable instructions, shared across your agents.
          </p>
        </div>
        <button
          className="button primary"
          onClick={() =>
            setEditing({
              id: crypto.randomUUID(),
              name: "",
              instructions: "",
              enabled: true,
            })
          }
        >
          <Plus size={15} />
          Teach a skill
        </button>
      </div>
      <div className="skills-grid">
        {state.skills.map((skill) => (
          <article className="skill-card" key={skill.id}>
            <div className="skill-top">
              <span className="skill-icon">
                <Sparkles size={20} />
              </span>
              <button
                role="switch"
                aria-checked={skill.enabled}
                aria-label={`Enable ${skill.name}`}
                className={`toggle ${skill.enabled ? "on" : ""}`}
                onClick={() =>
                  void act(() =>
                    api!.saveSkill({ ...skill, enabled: !skill.enabled }),
                  )
                }
              >
                <span />
              </button>
            </div>
            <h3>{skill.name}</h3>
            <p>{skill.instructions}</p>
            <button className="text-button" onClick={() => setEditing(skill)}>
              Edit skill
              <ChevronRight size={13} />
            </button>
          </article>
        ))}
      </div>
      <div className="info-banner">
        <BookOpen size={23} />
        <div>
          <strong>Small instructions. Consistent behavior.</strong>
          <p>
            Sidefolk sends enabled skills on the first turn, then only when they
            change. Economy mode uses these shared skills and skips global
            provider catalogs. Standard mode also loads native customizations.
          </p>
        </div>
      </div>
      {editing && (
        <div className="modal-backdrop">
          <form
            className="modal"
            onSubmit={(e) => {
              e.preventDefault();
              void act(async () => {
                await api!.saveSkill(editing);
                setEditing(null);
              });
            }}
          >
            <div className="section-title">
              <h2>Teach a little superpower</h2>
              <button
                type="button"
                className="icon-button"
                aria-label="Close skill editor"
                onClick={() => setEditing(null)}
              >
                <X size={18} />
              </button>
            </div>
            <label>
              Skill name
              <input
                autoFocus
                required
                value={editing.name}
                maxLength={60}
                onChange={(e) =>
                  setEditing({ ...editing, name: e.target.value })
                }
                placeholder="e.g. My coding style"
              />
            </label>
            <label>
              How should your companion do it?
              <textarea
                required
                rows={6}
                maxLength={1500}
                value={editing.instructions}
                onChange={(e) =>
                  setEditing({ ...editing, instructions: e.target.value })
                }
                placeholder="Use TypeScript. Prefer small functions. Explain the tradeoffs before choosing a dependency."
              />
            </label>
            <div className="modal-actions">
              {state.skills.some((s) => s.id === editing.id) && (
                <button
                  type="button"
                  className="text-button danger"
                  onClick={() =>
                    void act(async () => {
                      await api!.deleteSkill(editing.id);
                      setEditing(null);
                    })
                  }
                >
                  Delete skill
                </button>
              )}
              <button className="button primary">Save skill</button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
function Workshop({ state, act }: { state: Snapshot; act: Act }) {
  const [confirm, setConfirm] = useState<string | null>(null);
  const output = useRef<HTMLPreElement>(null);
  useEffect(() => {
    if (output.current) output.current.scrollTop = output.current.scrollHeight;
  }, [state.job?.output]);
  return (
    <div className="panel-stack">
      <div className="project-banner">
        <span className="project-icon">
          <FolderOpen size={27} />
        </span>
        <div>
          <strong>{state.project?.name ?? "A place to make things"}</strong>
          <p>
            {state.project?.path ??
              "Choose a folder for your agent to explore and work in."}
          </p>
        </div>
        <button
          className="button"
          disabled={!!state.agent || state.job?.status === "running"}
          onClick={() => void act(() => api!.chooseProject())}
        >
          <FolderOpen size={15} />
          {state.project ? "Change folder" : "Choose project"}
        </button>
      </div>
      {state.project ? (
        <>
          <div className="section-toolbar">
            <h3 className="subheading">Project scripts</h3>
            <span className="muted">Review a script before running it.</span>
          </div>
          <div className="script-grid">
            {Object.entries(state.project.scripts).map(([name, command]) => (
              <article className="script-card" key={name}>
                <Terminal size={17} />
                <div>
                  <strong>{name}</strong>
                  <code>{command}</code>
                </div>
                <button
                  className="button small"
                  disabled={state.job?.status === "running"}
                  onClick={() => setConfirm(name)}
                >
                  Run
                  <ChevronRight size={13} />
                </button>
              </article>
            ))}
          </div>
          {!Object.keys(state.project.scripts).length && (
            <p className="muted">
              No npm scripts here. You can still ask your agent to explore this
              folder.
            </p>
          )}
        </>
      ) : (
        <Empty
          icon={<Terminal />}
          title="Little paws. Real tools."
          text="Your companion can inspect projects through Codex or Claude and run the scripts you choose."
        />
      )}
      {state.job && (
        <section className="terminal-card">
          <div className="terminal-header">
            <span>
              <Terminal size={14} />
              npm run {state.job.script}
              <span className={`job-status ${state.job.status}`}>
                {state.job.status}
              </span>
            </span>
            {state.job.status === "running" && (
              <button onClick={() => void act(() => api!.stopJob())}>
                <Square size={12} />
                Stop
              </button>
            )}
          </div>
          <pre ref={output}>
            {state.job.output.replace(/\x1b\[[0-9;]*m/g, "")}
          </pre>
        </section>
      )}
      <div className="info-banner">
        <Leaf size={23} />
        <div>
          <strong>Your agent is one conversation away.</strong>
          <p>
            After choosing a folder, ask “Explain this project” in chat.
            Workspace edits are off by default and can be enabled in Settings.
          </p>
        </div>
      </div>
      {confirm && state.project && (
        <div className="modal-backdrop">
          <div className="modal">
            <div className="section-title">
              <h2>Run this project script?</h2>
              <button
                className="icon-button"
                aria-label="Cancel script"
                onClick={() => setConfirm(null)}
              >
                <X size={18} />
              </button>
            </div>
            <p>
              This runs locally in <strong>{state.project.path}</strong>.
            </p>
            <pre className="script-preview">
              {["pre" + confirm, confirm, "post" + confirm]
                .filter((n) => Object.hasOwn(state.project!.scripts, n))
                .map((n) => `${n}: ${state.project!.scripts[n]}`)
                .join("\n")}
            </pre>
            <div className="modal-actions">
              <button className="button" onClick={() => setConfirm(null)}>
                Cancel
              </button>
              <button
                className="button primary"
                onClick={() =>
                  void act(async () => {
                    await api!.runScript(confirm);
                    setConfirm(null);
                  })
                }
              >
                Run script
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
function SettingsPanel({ state, act }: { state: Snapshot; act: Act }) {
  const [draft, setDraft] = useState(state.settings),
    [agents, setAgents] = useState<Record<string, string>>({}),
    [saved, setSaved] = useState(false);
  const submit = (e: FormEvent) => {
    e.preventDefault();
    void act(async () => {
      await api!.settings(draft);
      setSaved(true);
    });
  };
  useEffect(() => {
    void act(async () => setAgents(await api!.checkAgents()));
  }, []);
  return (
    <form className="settings-grid" onSubmit={submit}>
      <section className="settings-card">
        <span className="note-kicker">
          <Leaf size={14} />
          YOUR COMPANION
        </span>
        <h2>A name that feels like a friend.</h2>
        <label>
          What should we call your pet?
          <input
            value={draft.petName}
            required
            maxLength={24}
            onChange={(e) => {
              setSaved(false);
              setDraft({ ...draft, petName: e.target.value });
            }}
          />
        </label>
        <label>A little color</label>
        <div className="color-options">
          {(["sage", "peach", "lilac"] as const).map((color) => (
            <button
              key={color}
              type="button"
              aria-label={`Choose ${color}`}
              aria-pressed={draft.color === color}
              className={`color-option ${color} ${draft.color === color ? "selected" : ""}`}
              onClick={() => {
                setSaved(false);
                setDraft({ ...draft, color });
              }}
            >
              {draft.color === color && <Check size={17} />}
              <span>{color}</span>
            </button>
          ))}
        </div>
        <SettingSwitch
          title="Live on my desktop"
          text="A draggable, always-on-top companion."
          value={draft.petVisible}
          set={(petVisible) => setDraft({ ...draft, petVisible })}
        />
      </section>
      <section className="settings-card">
        <span className="note-kicker">
          <Brain size={14} />
          THE BRAIN BEHIND THE PAWS
        </span>
        <h2>Pick your agent.</h2>
        <div className="provider-options">
          {(["codex", "claude", "local"] as const).map((provider) => (
            <label
              className={`provider-option ${draft.provider === provider ? "selected" : ""}`}
              key={provider}
            >
              <input
                type="radio"
                name="provider"
                checked={draft.provider === provider}
                onChange={() => {
                  setSaved(false);
                  setDraft({ ...draft, provider });
                }}
              />
              <span>
                <strong>
                  {provider === "codex"
                    ? "Codex"
                    : provider === "claude"
                      ? "Claude Code"
                      : "Local only"}
                </strong>
                <small>
                  {provider === "local"
                    ? "Reminders, todos & memory. No model calls."
                    : agents[provider] === "Not installed"
                      ? "Install the CLI to connect"
                      : "Uses your existing CLI login & sessions"}
                </small>
              </span>
            </label>
          ))}
        </div>
        <SettingSwitch
          title="Allow workspace edits"
          text="Codex: workspace writes. Claude: file edits; no shell tools."
          value={draft.allowEdits}
          set={(allowEdits) => setDraft({ ...draft, allowEdits })}
        />
      </section>
      <section className="settings-card">
        <span className="note-kicker">
          <Zap size={14} />
          LIGHT ON YOUR COMPUTER
        </span>
        <h2>Useful doesn’t have to be noisy.</h2>
        <SettingSwitch
          title="Economy mode"
          text="Compact agent instructions, fewer catalogs, and bounded memory."
          value={draft.economy}
          set={(economy) => setDraft({ ...draft, economy })}
        />
        <SettingSwitch
          title="Quiet time"
          text="Hold reminder notifications until quiet time ends."
          value={draft.focus}
          set={(focus) => setDraft({ ...draft, focus })}
        />
        <p className="panel-footnote">
          No model calls while idle. Scheduling, reminders, and todos use local
          code. Existing agent sessions may retain their own longer context.
        </p>
      </section>
      <section className="settings-card">
        <span className="note-kicker">
          <Terminal size={14} />
          REPORTED AGENT USAGE
        </span>
        <h2>A little visibility.</h2>
        <div className="usage-grid">
          <div>
            <strong>{compact(state.usage.turns)}</strong>
            <span>Turns</span>
          </div>
          <div>
            <strong>{compact(state.usage.input)}</strong>
            <span>Input tokens</span>
          </div>
          <div>
            <strong>{compact(state.usage.cached)}</strong>
            <span>Cached tokens</span>
          </div>
          <div>
            <strong>{compact(state.usage.output)}</strong>
            <span>Output tokens</span>
          </div>
        </div>
        <p className="panel-footnote">
          Reported by your CLI. Cache accounting differs by provider; these
          aren’t a price estimate. Native agent instructions and tool results
          also use context.
        </p>
      </section>
      <div className="settings-save">
        <span>
          {saved ? (
            <>
              <Check size={15} />A little more you. Settings saved.
            </>
          ) : (
            "Your companion. Your rules."
          )}
        </span>
        <button className="button primary" disabled={!!state.agent}>
          Save changes
          <Check size={15} />
        </button>
      </div>
    </form>
  );
}
function SettingSwitch({
  title,
  text,
  value,
  set,
}: {
  title: string;
  text: string;
  value: boolean;
  set: (value: boolean) => void;
}) {
  return (
    <div className="setting-switch">
      <div>
        <strong>{title}</strong>
        <p>{text}</p>
      </div>
      <button
        className={`toggle ${value ? "on" : ""}`}
        type="button"
        role="switch"
        aria-label={title}
        aria-checked={value}
        onClick={() => set(!value)}
      >
        <span />
      </button>
    </div>
  );
}
function Empty({
  icon,
  title,
  text,
}: {
  icon: ReactNode;
  title: string;
  text: string;
}) {
  return (
    <div className="empty-panel">
      <span>{icon}</span>
      <h3>{title}</h3>
      <p>{text}</p>
    </div>
  );
}
