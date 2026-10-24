import { AGENT_NAMES, folder } from "./agents";
import type { Crew } from "./crew";
import type { Reminders } from "./reminders";
import { privacy } from "./states";
import { describeDue, parseWhen } from "./when";

/** Mirrors the `mcp` event in src-tauri/src/mcp.rs: an agent called one of the pet's tools. */
export type ToolCall = {
  id: string;
  tool: "notify" | "ask" | "remind";
  args: { text?: string; question?: string; choices?: string[]; when?: string };
  project: string;
  cwd: string;
  source: "claude" | "codex" | "agent";
};
export type ToolResult = { text: string; isError: boolean };

const agentName = (source: ToolCall["source"]) => (source === "agent" ? "An AI tool" : AGENT_NAMES[source]);

/**
 * Shows an agent's tool call on the pet that looks after its project and answers it.
 * Agent text is untrusted: it only ever lands in bubbles as text.
 */
export function handleToolCall(call: ToolCall, crew: Crew, reminders: Reminders, reply: (result: ToolResult) => void) {
  const pet = crew.petFor(call.project);
  const agent = agentName(call.source);
  const named = privacy.detail !== "status";
  const who = named ? `${pet.name} · ${folder(call.project || call.cwd)}` : pet.name;
  switch (call.tool) {
    case "notify": {
      // With less card detail, the note waits behind a click instead of showing to the room.
      if (privacy.detail === "full") pet.bubble.say(call.args.text ?? "", 8);
      else
        pet.bubble.show({
          id: call.id,
          who,
          context: agent,
          title: `${agent} sent you a note.`,
          choices: [
            { label: "Dismiss", value: "ok" },
            { label: "Show", value: "show", primary: true },
          ],
          onChoose: (value) => value === "show" && pet.bubble.say(call.args.text ?? "", 10),
        });
      pet.holdUntil = Math.max(pet.holdUntil, Date.now() + 8_000);
      crew.tick();
      return reply({ text: `Shown on ${pet.name}'s speech bubble.`, isError: false });
    }
    case "ask": {
      const choices = call.args.choices?.length ? call.args.choices : ["Yes", "No"];
      const answer = (text: string) => reply({ text: `The user answered: ${text}`, isError: false });
      return crew.question(pet, {
        id: call.id,
        who,
        context: agent,
        title: named ? (call.args.question ?? "") : `${agent} has a question for you.`,
        lines: named ? [] : ["Open Sidefolk to read and answer it."],
        meta: {
          kind: "question",
          source: call.source,
          project: call.project,
          cwd: call.cwd,
          question: call.args.question ?? "",
          // Without fixed choices the user may write an answer (Reply… on the pet).
          free: String(!call.args.choices?.length),
        },
        choices: [
          ...choices.map((label, i) => ({ label, value: label, primary: i === 0 })),
          ...(call.args.choices?.length ? [] : [{ label: "Reply…", value: "\u0000reply" }]),
        ],
        onChoose: (value) => {
          if (value !== "\u0000reply") return answer(value);
          pet.bubble.prompt({
            who,
            placeholder: "Your answer",
            submit: async (text) => {
              answer(text);
              return `Sent to ${agentName(call.source)}.`;
            },
          });
        },
      });
    }
    case "remind": {
      const due = parseWhen(call.args.when ?? "");
      if (!due) return reply({ text: `I could not read "${call.args.when}" as a future time.`, isError: true });
      void reminders
        .fromAgent(call.args.text ?? "", due, call.project, call.source)
        .then(() => {
          pet.bubble.say(named ? `${agent} set a reminder: ${describeDue(due)}, ${call.args.text}` : `${agent} set a reminder for ${describeDue(due)}.`, 6);
          reply({ text: `Reminder set for ${due.toString()}.`, isError: false });
        })
        .catch((error) => reply({ text: String(error), isError: true }));
    }
  }
}
