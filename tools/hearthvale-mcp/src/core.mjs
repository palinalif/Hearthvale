import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs/promises";
import path from "node:path";

const exec = promisify(execFile);
const MAX_LOG = 12000;
export class SafeError extends Error {}
export const tail = (s = "") => s.length > MAX_LOG ? s.slice(-MAX_LOG) : s;
export async function run(command, args, { cwd, timeout = 120000 } = {}) {
  try { const r = await exec(command, args, { cwd, timeout, windowsHide: true, maxBuffer: 8 * 1024 * 1024 }); return { exit_code: 0, stdout_tail: tail(r.stdout), stderr_tail: tail(r.stderr) }; }
  catch (e) { return { exit_code: e.code ?? 1, stdout_tail: tail(e.stdout), stderr_tail: tail(e.stderr || e.message) }; }
}
export function assertName(value, label = "name") {
  if (typeof value !== "string" || !value || value.startsWith("-") || /[\0\r\n]/.test(value)) throw new SafeError("Invalid " + label);
  return value;
}
export function assertBranch(value) {
  assertName(value, "branch");
  if (value.includes("..") || value.startsWith("/") || value.endsWith("/") || /[\s~^:?*\[\]\\]/.test(value)) throw new SafeError("Invalid branch name");
  return value;
}
export async function repoRoot(start = process.env.HEARTHVALE_REPO_ROOT || process.cwd()) {
  const r = await run("git", ["rev-parse", "--show-toplevel"], { cwd: start });
  if (r.exit_code) throw new SafeError("HEARTHVALE_REPO_ROOT must be a Git checkout");
  return path.resolve(r.stdout_tail.trim());
}
export async function safePath(root, relative, { allowMissing = false } = {}) {
  if (typeof relative !== "string" || !relative || path.isAbsolute(relative) || /^[A-Za-z]:/.test(relative) || /^\\\\/.test(relative) || relative.includes("\0")) throw new SafeError("Path must be a non-empty repository-relative path");
  const candidate = path.resolve(root, relative);
  const prefix = root.endsWith(path.sep) ? root : root + path.sep;
  if (!candidate.startsWith(prefix)) throw new SafeError("Path escapes repository root");
  let resolved;
  try { resolved = await fs.realpath(candidate); } catch (e) { if (!allowMissing || e.code !== "ENOENT") throw e; resolved = candidate; }
  if (!(resolved === root || resolved.startsWith(prefix))) throw new SafeError("Path resolves outside repository root");
  return { absolute: candidate, relative: path.relative(root, candidate).replaceAll("\\", "/") };
}
export async function git(root, args, opts = {}) { return run("git", args, { cwd: root, ...opts }); }
async function out(root, args) { const r = await git(root, args); return r.exit_code ? "" : r.stdout_tail.trimEnd(); }
export async function defaultBranch(root, remote = "origin") {
  assertName(remote, "remote");
  const sym = await out(root, ["symbolic-ref", "--quiet", "refs/remotes/" + remote + "/HEAD"]);
  if (sym) return sym.split("/").at(-1);
  const remoteHead = await out(root, ["ls-remote", "--symref", remote, "HEAD"]);
  const m = remoteHead.match(/ref: refs\/heads\/([^\s]+)\s+HEAD/); if (m) return m[1];
  return (await out(root, ["config", "init.defaultBranch"])) || "main";
}
export async function status(root) {
  const branch = await out(root, ["branch", "--show-current"]); const head = await out(root, ["rev-parse", "HEAD"]);
  const upstream = await out(root, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]);
  let ahead = null, behind = null;
  if (upstream) { const n = (await out(root, ["rev-list", "--left-right", "--count", "HEAD..." + upstream])).split(/\s+/).map(Number); [ahead, behind] = n; }
  const porcelain = await out(root, ["status", "--porcelain=v1"]);
  const files = porcelain ? porcelain.split("\n").map(x => ({ code: x.slice(0,2), path: x.slice(3) })) : [];
  return { branch, head, upstream: upstream || null, ahead, behind, diverged: ahead !== null && ahead > 0 && behind > 0, staged: files.filter(x => x.code[0] !== " " && x.code[0] !== "?"), modified: files.filter(x => x.code[1] !== " " && x.code[1] !== "?"), untracked: files.filter(x => x.code === "??") };
}
export async function requireClean(root) { const s = await status(root); if (s.staged.length || s.modified.length || s.untracked.length) throw new SafeError("Working tree is dirty; operation refused"); return s; }
export async function godot(root, script, timeout = 120000, checkOnly = false) {
  const target = await safePath(root, script); if (!target.relative.endsWith(".gd")) throw new SafeError("Godot target must be a .gd file");
  const editor = path.join(root, ".tools", "godot-4.7.2", "Godot_v4.7.2-stable_win64_console.exe");
  try { await fs.access(editor); } catch { throw new SafeError("Pinned Godot editor is missing; run tools/bootstrap.ps1 first"); }
  const args = checkOnly ? ["--headless", "--path", root, "--check-only", target.relative] : ["--headless", "--path", root, "--script", target.relative];
  const started = Date.now(); const result = await run(editor, args, { cwd: root, timeout }); const combined = result.stderr_tail + "\n" + result.stdout_tail;
  return { ...result, script: target.relative, duration_ms: Date.now() - started, first_error: combined.split("\n").find(x => /Parse Error|ERROR:|FAIL:|assert/i.test(x)) || null };
}
export function diffStat(text) { const files = [...text.matchAll(/^diff --git a\/(.+?) b\/(.+)$/gm)].map(m => m[2]); return { changed_files: files, files_changed: files.length }; }
