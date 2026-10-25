// Read-only audit probes against the current source. Requires this audit host's Node 24.
// No shell command in the examples is executed; approval checks classify strings only.
// Run: TZ=Asia/Tokyo node docs/audit-2026-10-25/probes.mjs
import { stripTypeScriptTypes } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const generated = new URL('../../output/audit-2026-10-25/probe-modules/', import.meta.url);
await mkdir(generated, { recursive: true });
for (const name of ['when', 'commands', 'access']) {
  const source = await readFile(new URL(`../../src/${name}.ts`, import.meta.url), 'utf8');
  const javascript = stripTypeScriptTypes(source, { mode: 'transform' }).replaceAll('"./when"', '"./when.mjs"');
  await writeFile(new URL(`${name}.mjs`, generated), javascript);
}
const { parseReminder, parseWhen, nextDue } = await import(new URL('when.mjs', generated));
const { parse } = await import(new URL('commands.mjs', generated));
const { stillAsk } = await import(new URL('access.mjs', generated));
const now = new Date('2026-10-25T10:00:00+09:00');
const local = date => date ? date.toLocaleString('sv-SE', { timeZone: 'Asia/Tokyo' }) + ' JST' : null;
const longCommand = 'echo ' + 'a'.repeat(2050) + '; rm -rf /tmp/sidefolk-audit-only';
// Reproduce bus.rs:188's display algorithm for these ASCII fixtures, including ellipsis.
const clipForDisplay = (text, max) => {
  const normalized = text.trim().split(/\s+/).join(' ');
  const characters = Array.from(normalized);
  return characters.length <= max ? normalized : characters.slice(0, max - 1).join('').trimEnd() + '…';
};
const result = {
  auditedAt: '2026-10-25',
  timezone: 'Asia/Tokyo',
  fixedNow: local(now),
  observations: [
    { id: 'TIME-1', input: 'at 3 to call mum', expected: '2026-10-25 15:00:00 JST', actual: local(parseReminder('at 3 to call mum', now)?.due), parseWhen: local(parseWhen('at 3', now)) },
    { id: 'TIME-2', input: '2026-10-26T03:00 to check backup', expected: '2026-10-26 03:00:00 JST', actual: local(parseReminder('2026-10-26T03:00 to check backup', now)?.due), parseWhen: local(parseWhen('2026-10-26T03:00', now)) },
    { id: 'TIME-3', input: 'every Monday and Thursday at 9 to check reports', actual: parseReminder('every Monday and Thursday at 9 to check reports', now), note: 'Only one weekly occurrence is parsed; Thursday remains task text.' },
    { id: 'TIME-4', input: '2026-10-20 at 9 to call the bank', actual: local(parseReminder('2026-10-20 at 9 to call the bank', now)?.due), note: 'Still in the past; UI save guard prevents new reminders being saved at this date.' },
    { id: 'TIME-5', input: 'Monday weekly reminder snoozed to Tuesday, then completed', expectedIfSnoozePreservesSchedule: '2026-11-02 09:00:00 JST', actual: local(nextDue(new Date('2026-10-27T09:00:00+09:00'), { every: 'week', n: 1 }, new Date('2026-10-27T10:00:00+09:00'))) },
    ...['meeting at 3', 'I have a meeting at 3', 'remember I shipped the login migration', 'note for Ideas: try a quieter morning'].map(input => ({ id: 'LANGUAGE', input, actual: parse(input).kind })),
    ...['git -C /tmp push --force', 'git clean -fd', 'rm --recursive /tmp/sidefolk-audit-only', 'find /tmp/sidefolk-audit-only -delete'].map(input => ({ id: 'ACCESS', input, stillAsks: !!stillAsk('command', input) })),
    { id: 'ACCESS-CLIP', characters: longCommand.length, fullCommandStillAsks: !!stillAsk('command', longCommand), first2000CharactersStillAsk: !!stillAsk('command', longCommand.slice(0, 2000)), productionAlgorithmExcerptLength: clipForDisplay(longCommand, 2000).length, productionAlgorithmExcerptStillAsks: !!stillAsk('command', clipForDisplay(longCommand, 2000)) },
    { id: 'DISPLAY-WHITESPACE', input: 'echo "a  b"', displayed: clipForDisplay('echo "a  b"', 2000), note: 'Pure reproduction of bus.rs display algorithm changes quoted argument whitespace.' },
  ],
};
await writeFile(new URL('probe-results.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result, null, 2));
