import {
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowUp,
  ArrowDown,
  ArrowUpRight,
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
  Search,
  Command,
  ListTodo,
  GripHorizontal,
  Circle,
  WandSparkles,
  ShieldCheck,
} from "lucide-react";
import type { Item, Memory, Settings, Skill, Snapshot } from "../shared/types";
import { api } from "./api";
import { visibleAgentText } from "../shared/protocol";
import { shortcutLabel } from "../shared/desktop";
import Pet from "./components/Pet";
import { PetGallery } from "./components/PetGallery";
import { Modal, MarkdownMessage, CopyButton } from "./components/ui";
import { UpcomingTasks, TasksPanel, TaskComposer } from "./components/Tasks";

type Page =
  "home" | "pets" | "tasks" | "memory" | "skills" | "workshop" | "settings";
const nav: { id: Page; label: string; icon: typeof Home }[] = [
  { id: "pets", label: "Pet studio", icon: WandSparkles },
  { id: "home", label: "Companion", icon: MessageCircle },
  { id: "tasks", label: "Tasks", icon: ListTodo },
  { id: "memory", label: "Memory", icon: Brain },
  { id: "skills", label: "Skills", icon: Sparkles },
  { id: "workshop", label: "Workshop", icon: Terminal },
];
const titles: Record<Page, [string, string]> = {
  pets: [
    "Find your kind of company.",
    "Six little personalities. Two dimensions to explore. One companion that’s yours.",
  ],
  home: [
    "What’s on your mind?",
    "Ideas, reminders, or your next big thing. I’m here for it.",
  ],
  tasks: [
    "A little less to keep in your head.",
    "Your reminders and to-dos, all in one place.",
  ],
  memory: [
    "It’s the little things that make you, you.",
    "A shared memory that feels personal. Always yours to edit.",
  ],
  skills: [
    "Teach me your kind of magic.",
    "Small instructions. A companion that works your way.",
  ],
  workshop: [
    "Good things are made together.",
    "Connect a project and turn an idea into something real.",
  ],
  settings: [
    "Make this space your own.",
    "Your companion, your agent, your rhythm.",
  ],
};
const compact = (n: number) =>
  Intl.NumberFormat(undefined, {
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(n);
const isMac = navigator.userAgent.includes("Mac");
const providerName = (provider: string) =>
  provider === "codex"
    ? "Codex"
    : provider === "claude"
      ? "Claude Code"
      : "Local only";

type Act = (fn: () => Promise<unknown>) => Promise<void>;
export default function App() {
  const [state, setState] = useState<Snapshot | null>(null),
    [page, setPage] = useState<Page>("home"),
    [error, setError] = useState("");
  const [taskComposer, setTaskComposer] = useState(false),
    [palette, setPalette] = useState(false),
    [query, setQuery] = useState("");
  const floating = location.hash === "#pet";
  const act: Act = async (fn) => {
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
    if (floating) return;
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPalette((p) => !p);
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [floating]);
  useEffect(() => {
    if (!floating || !api) return;
    let last = false;
    const hover = (event: MouseEvent) => {
      const target = event.target as Element;
      let interactive = !!target.closest("button,.pet-drag");
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
        <span className="brand-mark">
          <Sparkles size={28} />
        </span>
        <h1>A little company for your desktop.</h1>
        <p>Sidefolk runs as a desktop app. Start your companion with:</p>
        <code>npm run dev</code>
      </div>
    );
  if (!state)
    return (
      <div className="loading">
        <span className="brand-mark">
          <Sparkles size={25} />
        </span>
        <LoaderCircle className="spin" />
        <p>Waking up your companion…</p>
        {error}
      </div>
    );
  const settings = state.settings,
    due = state.items.filter((i) => i.status === "due"),
    active = state.items.filter((i) => i.status !== "done");
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
      <div className={`floating-pet mood-${mood}`}>
        <div className="pet-drag" title="Drag to move">
          <GripHorizontal size={12} />
          <span>{settings.petName}</span>
          <span className="pet-presence" />
        </div>
        <button
          className={`pet-bubble ${due.length ? "has-reminder" : ""}`}
          onClick={() => void act(() => api.openHome())}
        >
          {due.length ? (
            <>
              <Bell size={13} />
              {due[0].title}
            </>
          ) : state.agent ? (
            "A little busy. Come see?"
          ) : settings.focus ? (
            "Quiet company. Always here."
          ) : (
            "Hey. What are we making?"
          )}
          <ArrowUpRight size={13} />
        </button>
        <Pet
          accessory={settings.petAccessory}
          species={settings.petSpecies}
          style={settings.petStyle}
          color={settings.color}
          mood={mood}
          floating
          onPet={() => void act(() => api.openHome())}
        />
        <div className="floating-actions">
          <button onClick={() => void act(() => api.openHome())}>
            <MessageCircle size={14} />
            Talk
          </button>
          <span />
          <button
            aria-label="Hide desktop companion"
            title={`Hide · ${shortcutLabel(settings.petShortcut, isMac)} to summon`}
            onClick={() => void act(() => api.petControl("hide"))}
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
            <Sparkles size={20} />
          </span>
          sidefolk<span className="brand-dot">✦</span>
        </a>
        <button
          className="quick-action-button"
          onClick={() => setPalette(true)}
        >
          <Search size={15} />
          <span>Quick actions</span>
          <kbd>{isMac ? "⌘" : "Ctrl"} K</kbd>
        </button>
        <div className="sidebar-label">YOUR SPACE</div>
        <nav aria-label="Main navigation">
          {nav.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              aria-label={id === "home" ? "Your companion" : label}
              aria-current={page === id ? "page" : undefined}
              className={`nav-item ${page === id ? "active" : ""}`}
              onClick={() => setPage(id)}
            >
              <Icon size={17} />
              {label}
              {id === "tasks" && active.length > 0 && (
                <span className="nav-count">{active.length}</span>
              )}
              {id === "memory" &&
                state.memories.some((m) => m.source === "suggested") && (
                  <span className="nav-dot" />
                )}
            </button>
          ))}
        </nav>
        <div className="sidebar-label sessions-heading">
          RECENT CONVERSATIONS
          <button
            className="icon-button"
            aria-label="New conversation"
            disabled={!!state.agent}
            onClick={() => {
              setPage("home");
              void act(() => api.newSession());
            }}
          >
            <Plus size={15} />
          </button>
        </div>
        <div className="sessions">
          {state.sessions.slice(0, 8).map((session) => (
            <button
              key={session.id}
              disabled={!!state.agent}
              title={session.title}
              className={`session ${state.activeSessionId === session.id && page === "home" ? "selected" : ""}`}
              onClick={() => {
                setPage("home");
                void act(() => api.switchSession(session.id));
              }}
            >
              <MessageCircle size={13} />
              <span>{session.title}</span>
            </button>
          ))}
        </div>
        <div className="sidebar-bottom">
          <div className="sidebar-pet-status">
            <span className="avatar-mini">
              <Sparkles size={16} />
            </span>
            <div>
              <strong>
                {settings.petName} is{" "}
                {mood === "working"
                  ? "working"
                  : mood === "sleeping"
                    ? "taking it easy"
                    : "here for you"}
              </strong>
              <span>
                <span className="status-dot" />
                {settings.economy ? "Economy mode" : "Ready when you are"}
              </span>
            </div>
          </div>
          <button
            className={`nav-item ${page === "settings" ? "active" : ""}`}
            onClick={() => setPage("settings")}
          >
            <SettingsIcon size={17} />
            Settings
          </button>
          <button
            className="desktop-shortcut"
            onClick={() => void act(() => api.petControl("toggle"))}
            title="Show or hide the desktop pet"
          >
            <ExternalLink size={14} />
            <span>Desktop pet</span>
            <kbd>{shortcutLabel(settings.petShortcut, isMac)}</kbd>
          </button>
        </div>
      </aside>
      <main className="main">
        <header className="topbar">
          <div className="breadcrumb">
            Your space
            <ChevronRight size={12} />
            <strong>
              {page === "home"
                ? "Companion"
                : page === "pets"
                  ? "Pet studio"
                  : page[0].toUpperCase() + page.slice(1)}
            </strong>
          </div>
          <div className="topbar-actions">
            <button
              className={`topbar-focus ${settings.focus ? "is-on" : ""}`}
              onClick={() => void update({ focus: !settings.focus })}
              disabled={!!state.agent}
            >
              <Moon size={14} />
              {settings.focus ? "Quiet time on" : "Quiet time"}
            </button>
            <span className="topbar-divider" />
            <button
              className="provider-badge"
              onClick={() => setPage("settings")}
            >
              <span className="status-dot" />
              {providerName(settings.provider)}
              <ChevronRight size={12} />
            </button>
          </div>
        </header>
        <div className={`page-content ${page === "home" ? "home-page" : ""}`}>
          <div className="page-heading">
            <div>
              <div className="eyebrow">
                {page === "pets"
                  ? "SMALL CHARACTERS. BIG PERSONALITIES."
                  : page === "home"
                    ? "A LITTLE COMPANY. A LOT MORE POSSIBLE."
                    : page === "tasks"
                      ? "MAKE SOME HEADSPACE"
                      : page === "memory"
                        ? "GETTING TO KNOW YOU"
                        : page === "skills"
                          ? "A TOOLKIT WITH PERSONALITY"
                          : page === "workshop"
                            ? "FROM IDEA TO SOMETHING REAL"
                            : "JUST THE WAY YOU LIKE IT"}
              </div>
              <h1>{titles[page][0]}</h1>
              <p>{titles[page][1]}</p>
            </div>
            {page === "home" && (
              <button
                className="button desktop-toggle"
                onClick={() => void act(() => api.petControl("toggle"))}
                title={shortcutLabel(settings.petShortcut, isMac)}
              >
                <ExternalLink size={14} />
                {settings.petVisible ? "Hide desktop pet" : "Show desktop pet"}
              </button>
            )}
          </div>
          {state.storageWarning && (
            <div className="notice">{state.storageWarning}</div>
          )}
          {state.shortcutError && (
            <div className="notice">{state.shortcutError}</div>
          )}
          {page === "home" ? (
            <div className="home-grid">
              <Chat
                state={state}
                act={act}
                openSettings={() => setPage("settings")}
                onReminder={() => setTaskComposer(true)}
              />
              <aside className="companion-column">
                <section
                  className={`companion-card pet-color-${settings.color}`}
                >
                  <div className="card-kicker">
                    <span>
                      <span className="status-dot" />
                      {mood === "working"
                        ? "ON A LITTLE MISSION"
                        : mood === "sleeping"
                          ? "QUIET COMPANY"
                          : "YOUR COMPANION"}
                    </span>
                    <button
                      className="icon-button"
                      aria-label="Customize companion"
                      title="Customize companion"
                      onClick={() => setPage("pets")}
                    >
                      <Pencil size={13} />
                    </button>
                  </div>
                  <div className="pet-scene">
                    <div className="scene-orbit orbit-one" />
                    <div className="scene-orbit orbit-two" />
                    <span className="scene-doodle doodle-one">✦</span>
                    <span className="scene-doodle doodle-two">+</span>
                    <div className="scene-floor" />
                    <Pet
                      accessory={settings.petAccessory}
                      species={settings.petSpecies}
                      style={settings.petStyle}
                      color={settings.color}
                      mood={mood}
                    />
                  </div>
                  <div className="companion-intro">
                    <h2 aria-label={`Meet ${settings.petName}`}>
                      {settings.petName}
                      <span className="companion-status">
                        {mood === "working"
                          ? "On it"
                          : mood === "sleeping"
                            ? "Resting"
                            : "Ready to help"}
                      </span>
                    </h2>
                    <p>
                      {mood === "working"
                        ? "Little paws. Big plans."
                        : mood === "sleeping"
                          ? "I’ll keep the distractions away."
                          : due.length
                            ? "I have a little reminder for you."
                            : "Curious mind. Always on your side."}
                    </p>
                  </div>
                  <div className="companion-footer">
                    <button
                      onClick={() => void act(() => api.petControl("summon"))}
                    >
                      <ExternalLink size={13} />
                      Call me here
                    </button>
                    <button onClick={() => setPage("memory")}>
                      <Brain size={13} />
                      {
                        state.memories.filter((m) => m.source === "you").length
                      }{" "}
                      memories
                      <ChevronRight size={12} />
                    </button>
                  </div>
                </section>
                <UpcomingTasks
                  items={state.items}
                  act={act}
                  onAdd={() => setTaskComposer(true)}
                  onView={() => setPage("tasks")}
                />
                <div className="rail-note">
                  <ShieldCheck size={12} />
                  <span>Your memories stay on this device.</span>
                </div>
              </aside>
            </div>
          ) : (
            <div className="page-body">
              {page === "pets" && <PetGallery state={state} act={act} />}{" "}
              {page === "tasks" && (
                <TasksPanel
                  items={state.items}
                  act={act}
                  onAdd={() => setTaskComposer(true)}
                />
              )}{" "}
              {page === "memory" && <MemoryPanel state={state} act={act} />}{" "}
              {page === "skills" && <SkillsPanel state={state} act={act} />}{" "}
              {page === "workshop" && <Workshop state={state} act={act} />}{" "}
              {page === "settings" && <SettingsPanel state={state} act={act} />}
            </div>
          )}
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
      {taskComposer && (
        <TaskComposer act={act} onClose={() => setTaskComposer(false)} />
      )}{" "}
      {palette && (
        <Modal
          title="Where would you like to go?"
          onClose={() => {
            setPalette(false);
            setQuery("");
          }}
          className="command-modal"
        >
          <div className="search-field">
            <Search size={17} />
            <input
              autoFocus
              aria-label="Search quick actions"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Find a page or action…"
            />
          </div>
          <div className="command-results">
            {[
              ...nav.map((n) => ({
                label: n.label,
                icon: n.icon,
                run: () => setPage(n.id),
              })),
              {
                label: "Create a reminder or to-do",
                icon: Bell,
                run: () => setTaskComposer(true),
              },
              {
                label: "Summon desktop pet",
                icon: ExternalLink,
                run: () => void act(() => api.petControl("summon")),
              },
              {
                label: "Settings",
                icon: SettingsIcon,
                run: () => setPage("settings"),
              },
            ]
              .filter((c) =>
                c.label.toLowerCase().includes(query.toLowerCase()),
              )
              .map((c) => (
                <button
                  key={c.label}
                  onClick={() => {
                    c.run();
                    setPalette(false);
                    setQuery("");
                  }}
                >
                  <c.icon size={16} />
                  {c.label}
                  <ArrowUpRight size={13} />
                </button>
              ))}
          </div>
          <div className="command-footer">
            <kbd>esc</kbd> to close<span>Less clicking. More doing.</span>
          </div>
        </Modal>
      )}
    </div>
  );
}

function Chat({
  state,
  act,
  openSettings,
  onReminder,
}: {
  state: Snapshot;
  act: Act;
  openSettings: () => void;
  onReminder: () => void;
}) {
  const [text, setText] = useState(""),
    [sending, setSending] = useState(false),
    [jump, setJump] = useState(false);
  const scroll = useRef<HTMLDivElement>(null),
    input = useRef<HTMLTextAreaElement>(null),
    nearBottom = useRef(true);
  const session = state.sessions.find((s) => s.id === state.activeSessionId)!;
  const busy = sending || !!state.agent;
  const fresh =
    session.messages.length === 0 ||
    (session.messages.length === 1 &&
      session.messages[0].role === "assistant" &&
      session.messages[0].text.startsWith("Hey, I’m Pip."));
  const toBottom = (smooth = true) => {
    scroll.current?.scrollTo({
      top: fresh ? 0 : scroll.current.scrollHeight,
      behavior: smooth ? "smooth" : "instant",
    });
    nearBottom.current = true;
    setJump(false);
  };
  useEffect(() => {
    nearBottom.current = true;
    toBottom(false);
  }, [session.id]);
  useEffect(() => {
    if (nearBottom.current || session.messages.at(-1)?.role === "user")
      toBottom(false);
    else setJump(true);
  }, [session.messages.length, state.agent?.text, state.agent?.activity]);
  useEffect(() => {
    const field = input.current;
    if (field) {
      field.style.height = "0px";
      field.style.height = `${Math.min(160, Math.max(46, field.scrollHeight))}px`;
    }
  }, [text]);
  const send = async (value = text) => {
    if (!value.trim() || busy) return;
    setSending(true);
    try {
      await api.chat(value.trim());
      setText("");
      nearBottom.current = true;
    } catch (error) {
      await act(() => Promise.reject(error));
    } finally {
      setSending(false);
      input.current?.focus();
    }
  };
  const draft = (value: string) => {
    setText(value);
    input.current?.focus();
  };
  return (
    <section className="chat-card">
      <div className="chat-header">
        <div className="chat-title">
          <span className="chat-symbol">
            <MessageCircle size={15} />
          </span>
          <strong>{fresh ? "A fresh conversation" : session.title}</strong>
        </div>
        <span className="chat-session-meta">
          {state.agent ? (
            <>
              <span className="status-dot pulse" />
              Working
            </>
          ) : (
            <>
              <span className="session-indicator" />
              Just you & {state.settings.petName}
            </>
          )}
        </span>
      </div>
      <div
        className="chat-scroll"
        ref={scroll}
        role="log"
        aria-label="Conversation"
        onScroll={() => {
          const el = scroll.current!;
          nearBottom.current =
            el.scrollHeight - el.scrollTop - el.clientHeight < 80;
          if (nearBottom.current) setJump(false);
        }}
      >
        {fresh ? (
          <div className="chat-empty">
            <div className="welcome-symbol">
              <Sparkles size={31} />
              <span className="welcome-star">✦</span>
            </div>
            <span className="eyebrow">YOUR EVERYDAY SIDEKICK</span>
            <h2>
              Hey, I’m {state.settings.petName}.<br />
              <span>Let’s make some headspace.</span>
            </h2>
            <p>
              Think out loud, hand me a reminder,
              <br />
              or let’s make something worth making.
            </p>
            <div className="starter-cards">
              <button onClick={onReminder}>
                <span className="starter-icon peach">
                  <Bell size={17} />
                </span>
                <div>
                  <strong>Remember a thing</strong>
                  <span>I’ll give you a nudge.</span>
                </div>
                <ArrowUpRight size={14} />
              </button>
              <button onClick={() => draft("Help me think through an idea: ")}>
                <span className="starter-icon lilac">
                  <Sparkles size={17} />
                </span>
                <div>
                  <strong>Think together</strong>
                  <span>A second brain, with ears.</span>
                </div>
                <ArrowUpRight size={14} />
              </button>
              <button onClick={() => draft("I want to build ")}>
                <span className="starter-icon mint">
                  <Terminal size={17} />
                </span>
                <div>
                  <strong>Make something</strong>
                  <span>Turn “what if” into “done.”</span>
                </div>
                <ArrowUpRight size={14} />
              </button>
            </div>
          </div>
        ) : (
          <>
            <div className="chat-date">
              <span />{" "}
              {new Date(session.createdAt).toLocaleDateString([], {
                month: "long",
                day: "numeric",
              })}{" "}
              <span />
            </div>
            {session.messages.map((message) => (
              <div className={`message ${message.role}`} key={message.id}>
                {message.role === "assistant" && (
                  <span className="message-avatar">
                    <Sparkles size={15} />
                  </span>
                )}
                <div className="message-content">
                  <span className="message-name">
                    {message.role === "assistant"
                      ? state.settings.petName
                      : "You"}
                    <time>
                      {new Date(message.createdAt).toLocaleTimeString([], {
                        hour: "numeric",
                        minute: "2-digit",
                      })}
                    </time>
                  </span>
                  <div className="message-text">
                    {message.role === "assistant" ? (
                      <MarkdownMessage
                        text={
                          message.text.startsWith(
                            "Hey, I’m Pip. Your little desktop companion",
                          )
                            ? `Hey, I’m ${state.settings.petName}. What can I help you with?`
                            : message.text
                        }
                      />
                    ) : (
                      message.text
                    )}
                  </div>
                  {message.role === "assistant" && (
                    <div className="message-tools">
                      <CopyButton text={message.text} />
                    </div>
                  )}
                </div>
              </div>
            ))}
          </>
        )}
        {state.agent && (
          <div className="message assistant">
            <span className="message-avatar">
              <Sparkles size={15} />
            </span>
            <div className="message-content">
              <span className="message-name">
                {state.settings.petName}
                <span className="thinking-dots">•••</span>
              </span>
              <div className="agent-activity" role="status">
                <LoaderCircle size={13} className="spin" />
                {state.agent.activity}
              </div>
              {state.agent.text && (
                <div className="message-text">
                  <MarkdownMessage text={visibleAgentText(state.agent.text)} />
                </div>
              )}
            </div>
          </div>
        )}
      </div>
      {jump && (
        <button className="jump-button" onClick={() => toBottom()}>
          <ArrowDown size={13} />
          Back to latest
        </button>
      )}
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
        {!fresh && (
          <div className="suggestions">
            <button disabled={busy} onClick={onReminder}>
              <Bell size={13} />
              Add a reminder
            </button>
            <button disabled={busy} onClick={() => draft("Remember that ")}>
              <Brain size={13} />
              Teach me something
            </button>
          </div>
        )}
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
            placeholder={`What’s on your mind? Tell ${state.settings.petName}…`}
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
            <button
              type="button"
              className="composer-provider"
              onClick={openSettings}
            >
              <span className="status-dot" />
              {providerName(state.settings.provider)}
              <ChevronRight size={11} />
            </button>
            <div className="composer-right">
              <span>
                <kbd>↵</kbd> send
              </span>
              {state.agent ? (
                <button
                  type="button"
                  className="send-button stop"
                  aria-label="Stop agent"
                  onClick={() => void act(() => api.stopAgent())}
                >
                  <Square size={15} />
                </button>
              ) : (
                <button
                  className="send-button"
                  aria-label="Send message"
                  disabled={!text.trim() || sending}
                >
                  {sending ? (
                    <LoaderCircle size={17} className="spin" />
                  ) : (
                    <ArrowUp size={19} />
                  )}
                </button>
              )}
            </div>
          </div>
        </form>
        <div className="composer-note">
          <Zap size={11} />
          {state.settings.economy
            ? "Light on tokens. Here when you need me."
            : "No background AI calls. You set the pace."}
          <span>Shift + Enter for a new line</span>
        </div>
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
          style={{ margin: "15px 0", width: "100%", fontSize: 14 }}
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
        <label>Moonbun’s coat color</label>
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
          text="Above other apps and across macOS desktops, even with this window closed."
          value={draft.petVisible}
          set={(petVisible) => setDraft({ ...draft, petVisible })}
        />
        <label>
          Show / hide shortcut
          <select
            className="shortcut-select"
            value={draft.petShortcut}
            onChange={(e) => {
              setSaved(false);
              setDraft({ ...draft, petShortcut: e.target.value });
            }}
          >
            {[
              "CommandOrControl+Shift+Space",
              "CommandOrControl+Shift+P",
              "Control+Alt+Space",
              ...(![
                "CommandOrControl+Shift+Space",
                "CommandOrControl+Shift+P",
                "Control+Alt+Space",
              ].includes(draft.petShortcut)
                ? [draft.petShortcut]
                : []),
            ].map((value) => (
              <option key={value} value={value}>
                {shortcutLabel(value, isMac)}
              </option>
            ))}
          </select>
        </label>
        <p className="panel-footnote" style={{ marginTop: 12 }}>
          {state.shortcutRegistered
            ? "Global shortcut active."
            : "Shortcut unavailable — choose another combination."}{" "}
          Hiding keeps the app and reminders running. Summoning brings the pet
          near your cursor.
        </p>
        <button
          className="button small"
          style={{ marginTop: 12 }}
          type="button"
          onClick={() => void act(() => api.petControl("summon"))}
        >
          Call pet here
          <ExternalLink size={13} />
        </button>
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
