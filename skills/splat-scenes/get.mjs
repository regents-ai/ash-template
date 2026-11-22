/* Fetches this folder from GitHub over plain HTTPS: no git, no sign-in, no packages. It asks GitHub once for the repository's file
   list, keeps the files under skills/splat-scenes/ (the slash keeps out the sibling skills/splat-scenes-phoenix), downloads each and
   writes it under the folder named, as it sits here.

     curl -sLO https://raw.githubusercontent.com/regents-ai/ash-template/main/skills/splat-scenes/get.mjs
     node get.mjs /abs/path/splat-scenes            (Node 18 or later) */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const REPO = 'regents-ai/ash-template',
  BRANCH = 'main',
  FOLDER = 'skills/splat-scenes/';

const [to] = process.argv.slice(2);
if (!to) {
  console.error('usage: node get.mjs <folder to write>');
  process.exit(2);
}
const list = await fetch(`https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1`, {
  headers: { accept: 'application/vnd.github+json' }
});
if (!list.ok) throw new Error(`GitHub's file list answered ${list.status} ${list.statusText}`);
const { tree, truncated } = await list.json();
if (truncated) throw new Error("GitHub's file list came back cut short");
const files = tree.filter(entry => entry.type === 'blob' && entry.path.startsWith(FOLDER));
let bytes = 0;
for (const file of files) {
  const got = await fetch(`https://raw.githubusercontent.com/${REPO}/${BRANCH}/${file.path}`);
  if (!got.ok) throw new Error(`${file.path}: ${got.status} ${got.statusText}`);
  const body = Buffer.from(await got.arrayBuffer()),
    at = join(resolve(to), file.path.slice(FOLDER.length));
  mkdirSync(dirname(at), { recursive: true });
  writeFileSync(at, body);
  bytes += body.length;
}
console.log(`${files.length} files, ${(bytes / 1e6).toFixed(2)} MB, written to ${resolve(to)}`);
