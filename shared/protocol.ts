// Hide action payloads while streaming as well as in saved conversation text.
export function visibleAgentText(text: string): string {
  return text
    .replace(
      /<SIDEFOLK_(?:ACTIONS|MEMORY)>[\s\S]*?(?:<\/SIDEFOLK_(?:ACTIONS|MEMORY)>|$)/g,
      "",
    )
    .trim();
}
