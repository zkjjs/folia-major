import fs from 'node:fs';
import path from 'node:path';
// Embed the upstream renderer bundle so the lyric page works without a server.
const root = path.resolve('ios/web-dist');
const script = fs.readFileSync(path.join(root, 'lyrics.js'), 'utf8').replaceAll('</script', '<\\/script');
const styles = fs.readdirSync(root).filter(name => name.endsWith('.css'))
    .map(name => fs.readFileSync(path.join(root, name), 'utf8')).join('\n').replaceAll('</style', '<\\/style');
fs.mkdirSync('ios/Resources', { recursive: true });
fs.writeFileSync('ios/Resources/lyrics.html',
    '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><style>'
    + styles + '</style></head><body><div id="root"></div><script>' + script + '</script></body></html>');
