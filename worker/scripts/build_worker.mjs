import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

function run(command, args, allowFailure = false) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    shell: false,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0 && !allowFailure) {
    process.exit(result.status ?? 1);
  }
  return result.status ?? 1;
}

function findWindowsEsbuild() {
  if (process.platform !== "win32" || !process.env.LOCALAPPDATA) {
    return null;
  }
  const cache = join(process.env.LOCALAPPDATA, "worker-build");
  if (!existsSync(cache)) return null;
  for (const entry of readdirSync(cache)) {
    if (!entry.startsWith("esbuild-win32-")) continue;
    const executable = join(cache, entry, "esbuild.exe");
    if (existsSync(executable)) return executable;
  }
  return null;
}

run("cargo", ["install", "-q", "worker-build", "--version", "^0.1"]);
const cachedEsbuild = findWindowsEsbuild();
if (cachedEsbuild) process.env.ESBUILD_BIN = cachedEsbuild;

const status = run("worker-build", ["--release"], process.platform === "win32");
if (status !== 0) {
  const downloadedEsbuild = findWindowsEsbuild();
  if (!downloadedEsbuild) process.exit(status);
  process.env.ESBUILD_BIN = downloadedEsbuild;
  console.error("Retrying worker-build with ESBUILD_BIN set for Windows.");
  run("worker-build", ["--release"]);
}
