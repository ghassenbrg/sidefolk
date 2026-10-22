import { spawn } from "node:child_process";
import electron from "electron";
const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;
if (process.argv.includes("--dev"))
  env.SIDEFOLK_DEV_URL = "http://127.0.0.1:5173";
const child = spawn(electron, ["."], { env, stdio: "inherit" });
child.on("exit", (code) => process.exit(code ?? 0));
child.on("error", (error) => {
  console.error(error.message);
  process.exit(1);
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => child.kill(signal));
