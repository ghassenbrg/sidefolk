export function externalWebUrl(value: string): string {
  const url = new URL(value);
  if (
    !["https:", "http:"].includes(url.protocol) ||
    url.username ||
    url.password
  )
    throw new Error("Only HTTP or HTTPS links can be opened.");
  return url.href;
}
export function projectToolsAllowed(
  projectPath: string | undefined,
  sessionPath: string,
): boolean {
  return !!projectPath && projectPath === sessionPath;
}

export function scriptReviewMatches(
  reviewed: Record<string, string>,
  current: Record<string, string>,
  name: string,
): boolean {
  return ["pre" + name, name, "post" + name].every(
    (key) => reviewed[key] === current[key],
  );
}
