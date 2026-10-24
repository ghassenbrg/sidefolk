import { AGENT_NAMES, folder } from "./agents";
import type { Companion } from "./companion";
import type { Reminders } from "./reminders";
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
 * Shows an agent's tool call on the companion and answers it.
 * Agent text is untrusted: it only ever lands in bubbles as text.
 */
export function handleToolCall(call: ToolCall, companion: Companion, reminders: Reminders, reply: (result: ToolResult) => void) {
  const pet = companion.pet;
  const agent = agentName(call.source);
  const who = `${pet.name} · ${folder(call.project || call.cwd)}`;
  switch (call.tool) {
    case "notify": {
      pet.bubble.say(call.args.text ?? "", 8);
      return reply({ text: `Shown on ${pet.name}'s speech bubble.`, isError: false });
    }
    case "ask": {
      const choices = call.args.choices?.length ? call.args.choices : ["Yes", "No"];
      const answer = (text: string) => reply({ text: `The user answered: ${text}`, isError: false });
      return companion.request({
        id: call.id,
        who,
        context: agent,
        title: call.args.question ?? "",
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
          pet.bubble.say(`${agent} set a reminder: ${describeDue(due)}, ${call.args.text}`, 6);
          reply({ text: `Reminder set for ${due.toString()}.`, isError: false });
        })
        .catch((error) => reply({ text: String(error), isError: true }));
    }
  }
}
