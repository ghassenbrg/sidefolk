// Shared failure vocabulary (V1-C6). Keep raw diagnostics in the log; a person gets the next step.
export function problem(error: unknown, fallback = "That didn't work; try again."): string {
  const raw = typeof error === "string" ? error : error instanceof Error ? error.message : "";
  if (/rate.?limit|quota|usage limit/i.test(raw)) return "The tool reached its usage limit; try again later.";
  if (/permission denied|not permitted|EACCES|EPERM/i.test(raw)) return "Access was denied; check permissions and try again.";
  if (/disk full|ENOSPC/i.test(raw)) return "Your disk is full; free some space and try again.";
  if (/isn't waiting|already answered|expired/i.test(raw)) return "That request ended; open the session to continue.";
  if (/connection|timed? out|timeout|not running|socket|ECONN/i.test(raw)) return "I couldn't reach Sidefolk; open it and try again.";
  if (/changed on disk/i.test(raw)) return "Reopen this notebook before trying again.";
  if (/no such|not found|ENOENT|folder is gone/i.test(raw)) return "I couldn't find it; check its location and try again.";
  // An intentional, plain validation message from the app may already explain the fix.
  if (/^(Enter |Choose |That time |Please |This name |A notebook )/.test(raw)
    && raw.trim().split(/\s+/).length <= 12
    && !/Error:|[a-z]+_[a-z]+|[\n{}\/`]|\bat .*:\d/i.test(raw)) return raw;
  return fallback;
}

export function agentProblem(agent: string, reason: string, project: string): string {
  const where = project ? ` in ${project}` : "";
  if (/rate.?limit|quota|usage limit/i.test(reason)) return `${agent} hit its usage limit${where}.`;
  if (/auth|unauthori|login/i.test(reason)) return `${agent} needs you to sign in${where}.`;
  return `${agent} stopped${where}; open the session to check.`;
}
