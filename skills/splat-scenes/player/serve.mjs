/* Serves the player page on this machine: the player folder, with /scene.bin and /still.png answered from the two files named.
   Usage: node player/serve.mjs <scene.bin> <still.png> [port] */
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.png': 'image/png'
};

const [sceneFile, stillFile, port = '4173'] = process.argv.slice(2);
if (!sceneFile || !stillFile) {
  console.error('usage: node player/serve.mjs <scene.bin> <still.png> [port]');
  process.exit(2);
}
const root = dirname(fileURLToPath(import.meta.url)),
  named = { '/scene.bin': resolve(sceneFile), '/still.png': resolve(stillFile) };
for (const file of Object.values(named)) statSync(file);

createServer((request, response) => {
  const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname),
    file = named[path] ?? join(root, normalize(path === '/' ? '/index.html' : path));
  if (!named[path] && !file.startsWith(root + sep)) {
    response.writeHead(404).end();
    return;
  }
  let size;
  try {
    const info = statSync(file);
    if (!info.isFile()) throw new Error('not a file');
    size = info.size;
  } catch {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', 'content-length': size, 'cache-control': 'no-store' });
  createReadStream(file).pipe(response);
}).listen(Number(port), '127.0.0.1', () => console.log(`open http://127.0.0.1:${port}/`));
