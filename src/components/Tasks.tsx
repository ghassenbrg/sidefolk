import { useState } from "react";
import {
  Bell,
  Check,
  CheckCheck,
  Clock3,
  ListTodo,
  Plus,
  Search,
  Trash2,
  ArrowUpRight,
} from "lucide-react";
import type { Item } from "../../shared/types";
import { api } from "../api";
import { Modal, type Act } from "./ui";

const timeLabel = (time: number) =>
  new Date(time).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
const localInput = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}T${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
export function TaskRow({ item, act }: { item: Item; act: Act }) {
  return (
    <div className={`task-row ${item.status}`}>
      <button
        className="task-check"
        aria-label={`${item.status === "done" ? "Reopen" : "Complete"} ${item.title}`}
        onClick={() =>
          void act(() =>
            api.item(item.id, item.status === "done" ? "reopen" : "done"),
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
              <Clock3 size={11} />
              {item.status === "due" ? "Ready now · " : ""}
              {timeLabel(item.dueAt)}
            </>
          ) : (
            <>
              <ListTodo size={11} />
              To-do
            </>
          )}
        </span>
      </div>
      <div className="task-actions">
        {item.kind === "reminder" && item.status !== "done" && (
          <button
            className="icon-button"
            aria-label={`Snooze ${item.title} for 30 minutes`}
            title="Snooze 30 minutes"
            onClick={() => void act(() => api.item(item.id, "snooze"))}
          >
            <Clock3 size={14} />
          </button>
        )}
        <button
          className="icon-button"
          aria-label={`Delete ${item.title}`}
          title="Delete task"
          onClick={() => void act(() => api.item(item.id, "delete"))}
        >
          <Trash2 size={13} />
        </button>
      </div>
    </div>
  );
}
export function TaskComposer({
  act,
  onClose,
}: {
  act: Act;
  onClose: () => void;
}) {
  const [title, setTitle] = useState(""),
    [kind, setKind] = useState<"reminder" | "todo">("reminder"),
    [when, setWhen] = useState(localInput(new Date(Date.now() + 3600_000))),
    [saving, setSaving] = useState(false);
  const quick = (tomorrow: boolean) => {
    const date = new Date(Date.now() + (tomorrow ? 86400_000 : 1800_000));
    if (tomorrow) date.setHours(9, 0, 0, 0);
    setWhen(localInput(date));
  };
  return (
    <Modal title="One less thing to remember." onClose={onClose}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          setSaving(true);
          void act(async () => {
            await api.addItem({
              title,
              kind,
              dueAt: kind === "reminder" ? new Date(when).getTime() : null,
            });
            onClose();
          }).finally(() => setSaving(false));
        }}
      >
        <div className="segmented" role="group" aria-label="Task type">
          <button
            type="button"
            aria-pressed={kind === "reminder"}
            onClick={() => setKind("reminder")}
          >
            <Bell size={14} />
            Reminder
          </button>
          <button
            type="button"
            aria-pressed={kind === "todo"}
            onClick={() => setKind("todo")}
          >
            <ListTodo size={14} />
            To-do
          </button>
        </div>
        <label>
          What’s on your list?
          <input
            aria-label="Task title"
            autoFocus
            required
            maxLength={240}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. Send the prototype to Alex"
          />
        </label>
        {kind === "reminder" && (
          <>
            <label>
              When should I remind you?
              <input
                type="datetime-local"
                aria-label="Reminder time"
                required
                min={localInput(new Date())}
                value={when}
                onChange={(e) => setWhen(e.target.value)}
              />
            </label>
            <div className="quick-replies">
              <button type="button" onClick={() => quick(false)}>
                In 30 minutes
              </button>
              <button type="button" onClick={() => quick(true)}>
                Tomorrow at 9
              </button>
            </div>
            <p className="muted">
              Your local time ·{" "}
              {Intl.DateTimeFormat().resolvedOptions().timeZone}
            </p>
          </>
        )}
        <div className="modal-actions">
          <button className="button" type="button" onClick={onClose}>
            Cancel
          </button>
          <button className="button primary" disabled={!title.trim() || saving}>
            {saving
              ? "Saving…"
              : kind === "reminder"
                ? "Create reminder"
                : "Add to-do"}
            <Check size={14} />
          </button>
        </div>
      </form>
    </Modal>
  );
}
export function UpcomingTasks({
  items,
  act,
  onAdd,
  onView,
}: {
  items: Item[];
  act: Act;
  onAdd: () => void;
  onView: () => void;
}) {
  const active = items
    .filter((i) => i.status !== "done")
    .sort((a, b) => (a.dueAt ?? Infinity) - (b.dueAt ?? Infinity));
  return (
    <section className="tasks-card">
      <div className="section-title">
        <h3>
          <Bell size={15} />
          Up next <span className="count">{active.length}</span>
        </h3>
        <button
          className="icon-button"
          aria-label="Add a task"
          title="Add a task"
          onClick={onAdd}
        >
          <Plus size={17} />
        </button>
      </div>
      {!active.length ? (
        <div className="empty-tasks">
          <div className="empty-orbit">
            <CheckCheck size={23} />
          </div>
          <p>You’re all caught up.</p>
          <span>A little room for your next idea.</span>
          <button className="text-button" onClick={onAdd}>
            Add something
            <Plus size={12} />
          </button>
        </div>
      ) : (
        <div className="task-items">
          {active.slice(0, 4).map((item) => (
            <TaskRow key={item.id} item={item} act={act} />
          ))}
        </div>
      )}
      <button className="rail-link" onClick={onView}>
        View all tasks
        <ArrowUpRight size={13} />
      </button>
    </section>
  );
}
export function TasksPanel({
  items,
  act,
  onAdd,
}: {
  items: Item[];
  act: Act;
  onAdd: () => void;
}) {
  const [filter, setFilter] = useState<"all" | "reminders" | "todos" | "done">(
      "all",
    ),
    [search, setSearch] = useState("");
  const active = items.filter((i) => i.status !== "done"),
    done = items.filter((i) => i.status === "done");
  const shown = items
    .filter(
      (i) =>
        (filter === "done" ? i.status === "done" : i.status !== "done") &&
        (filter === "reminders"
          ? i.kind === "reminder"
          : filter === "todos"
            ? i.kind === "todo"
            : true) &&
        i.title.toLowerCase().includes(search.toLowerCase()),
    )
    .sort((a, b) => (a.dueAt ?? Infinity) - (b.dueAt ?? Infinity));
  return (
    <div className="panel-stack">
      <div className="task-summary">
        <div>
          <span className="summary-icon lilac">
            <ListTodo size={19} />
          </span>
          <strong>{active.length}</strong>
          <span>On your list</span>
        </div>
        <div>
          <span className="summary-icon peach">
            <Bell size={19} />
          </span>
          <strong>{active.filter((i) => i.kind === "reminder").length}</strong>
          <span>Reminders</span>
        </div>
        <div>
          <span className="summary-icon mint">
            <CheckCheck size={19} />
          </span>
          <strong>{done.length}</strong>
          <span>Completed</span>
        </div>
      </div>
      <div className="section-toolbar">
        <div className="filter-tabs" aria-label="Filter tasks">
          {(["all", "reminders", "todos", "done"] as const).map((f) => (
            <button
              key={f}
              aria-pressed={filter === f}
              onClick={() => setFilter(f)}
            >
              {
                {
                  all: "All tasks",
                  reminders: "Reminders",
                  todos: "To-dos",
                  done: "Completed",
                }[f]
              }
            </button>
          ))}
        </div>
        <button className="button primary" onClick={onAdd}>
          <Plus size={15} />
          Add task
        </button>
      </div>
      <div className="search-field">
        <Search size={15} />
        <input
          aria-label="Search tasks"
          placeholder="Find a task…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <div className="task-table">
        {shown.length ? (
          shown.map((item) => <TaskRow key={item.id} item={item} act={act} />)
        ) : (
          <div className="empty-panel">
            <span>
              <CheckCheck size={25} />
            </span>
            <h3>
              {search
                ? "No matching tasks."
                : "Nothing here. That’s a good thing."}
            </h3>
            <p>
              {search
                ? "Try a different word."
                : "Add a reminder or to-do, or just tell your companion what’s on your mind."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
