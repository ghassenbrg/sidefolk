import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function configuration(base, env) {
  return { ...base, bundle: { ...base.bundle, createUpdaterArtifacts: true },
    plugins: { ...base.plugins, updater: { requireSignedVersion: true,
      pubkey: env.SIDEFOLK_UPDATER_PUBLIC_KEY || base.plugins?.updater?.pubkey || '',
      endpoints: env.SIDEFOLK_RELEASE_FEED ? [env.SIDEFOLK_RELEASE_FEED] : base.plugins?.updater?.endpoints || [],
    } } };
}
export function problems(config) {
  const errors = [];
  const updater = config.plugins?.updater;
  let decoded = '';
  try { decoded = Buffer.from(updater?.pubkey || '', 'base64').toString(); } catch {}
  if (!/^untrusted comment: .+\n[A-Za-z0-9+/=]+\s*$/.test(decoded) || Buffer.from(decoded.split('\n')[1] || '', 'base64').length !== 42) errors.push('Real Tauri updater public key is unconfigured');
  if (updater?.endpoints?.length !== 1 || !/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/releases\/latest\/download\/latest\.json$/.test(updater.endpoints[0])) errors.push('GitHub Releases latest.json endpoint is unconfigured');
  if (config.bundle?.macOS?.minimumSystemVersion !== '14.0' || !config.bundle.macOS.hardenedRuntime || config.bundle.macOS.entitlements !== 'Entitlements.plist') errors.push('macOS 14 hardened runtime / entitlements missing');
  if (!config.bundle?.createUpdaterArtifacts) errors.push('Updater artifacts are disabled');
  return errors;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const base = JSON.parse(readFileSync('src-tauri/tauri.conf.json', 'utf8'));
  const config = configuration(base, process.env);
  const errors = problems(config);
  const main = readFileSync('src-tauri/src/main.rs', 'utf8');
  if (!main.includes('mod release;') || !main.includes('tauri_plugin_updater::Builder')) errors.push('Lead must register release module and official updater plugin');
  if (process.env.SIDEFOLK_RELEASE_WIRING_REVIEWED !== '1') errors.push('Lead review of kill switch, consent and persistence is required (SIDEFOLK_RELEASE_WIRING_REVIEWED=1)');
  if (!process.env.APPLE_SIGNING_IDENTITY?.startsWith('Developer ID Application:')) errors.push('Developer ID signing identity is missing');
  if (!process.env.TAURI_SIGNING_PRIVATE_KEY) errors.push('Updater private key is missing');
  if (!process.env.SIDEFOLK_NOTARY_PROFILE && !(process.env.APPLE_API_KEY && process.env.APPLE_API_ISSUER && process.env.APPLE_API_KEY_PATH)) errors.push('Notarytool keychain profile or API key is missing');
  if (!/^\d+\.\d+\.\d+$/.test(process.env.SIDEFOLK_MIN_SAFE_VERSION || '')) errors.push('Stable SIDEFOLK_MIN_SAFE_VERSION required');
  const minimum = process.env.SIDEFOLK_MIN_SAFE_VERSION;
  if (/^\d+\.\d+\.\d+$/.test(minimum || '') && minimum.split('.').map(Number).reduce((r, n, i) => r || Math.sign(n - Number(config.version.split('.')[i])), 0) > 0) errors.push('Minimum safe version exceeds release version');
  const cargoVersion = readFileSync('src-tauri/Cargo.toml', 'utf8').match(/^version = "([^"]+)"/m)?.[1];
  if (cargoVersion !== config.version) errors.push('Cargo and Tauri versions differ');
  try { if (!readFileSync(process.env.SIDEFOLK_RELEASE_NOTES_FILE, 'utf8').trim()) throw Error(); }
  catch { errors.push('Nonempty SIDEFOLK_RELEASE_NOTES_FILE required'); }
  if (process.env.APPLE_PASSWORD || process.env.APPLE_ID) errors.push('Password-based notarization environment is forbidden; use notarytool profile/API key');
  if (errors.length) { console.error(errors.map(e => `BLOCKED: ${e}`).join('\n')); process.exitCode = 1; }
  else if (process.argv.includes('--config')) process.stdout.write(JSON.stringify(config));
  else console.log('Release configuration present; G1–G5 still require founder evidence on the signed build.');
}
