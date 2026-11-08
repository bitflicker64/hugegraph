/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Record index.html frame by frame with headless Chromium and encode it.
//
//   node render.cjs index.html out.mp4 --audio mix.wav [--fps 30] [--workers 4] [--format jpeg|png]
//   node render.cjs index.html stills/ --stills 5,15,25
//
// Each frame calls renderAt(t), so frames do not depend on machine speed and
// can be rendered in parallel: every worker records a contiguous slice of
// frames into its own H.264 segment, and the segments are joined without
// re-encoding. PW_MODULE points at the playwright package when it is not
// installed next to this file.

const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : def;
}
const X264 = ['-c:v', 'libx264', '-preset', 'slow', '-crf', '22', '-tune', 'animation', '-pix_fmt', 'yuv420p'];

function run(cmd, args, opts = {}) {
  const p = spawn(cmd, args, { stdio: ['pipe', 'inherit', 'inherit'], ...opts });
  p.done = new Promise((res, rej) => p.on('exit', c => (c === 0 ? res() : rej(new Error(`${cmd} exited ${c}`)))));
  return p;
}

async function openPage(file) {
  const { chromium } = require(process.env.PW_MODULE || 'playwright');
  const browser = await chromium.launch({
    args: ['--force-color-profile=srgb', '--font-render-hinting=none', '--hide-scrollbars'],
  });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto('file://' + path.resolve(file));
  await page.waitForFunction(() => window.READY === true, null, { timeout: 60000 });
  const fontsOk = await page.evaluate(() => document.fonts.check('800 100px Inter') &&
    document.fonts.check("600 20px 'JetBrains Mono'"));
  if (!fontsOk) throw new Error('web fonts did not load');
  return { browser, page, errors };
}

// Record frames [a, b) into a video-only segment.
async function segment(file, a, b, fps, format, out) {
  const { browser, page, errors } = await openPage(file);
  const ff = run('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-c:v', format === 'jpeg' ? 'mjpeg' : 'png',
    '-framerate', String(fps), '-i', '-', ...X264, '-r', String(fps), out]);
  for (let i = a; i < b; i++) {
    await page.evaluate(t => window.renderAt(t), i / fps);
    const img = await page.screenshot(format === 'jpeg' ? { type: 'jpeg', quality: 95 } : { type: 'png' });
    if (!ff.stdin.write(img)) await new Promise(r => ff.stdin.once('drain', r));
  }
  ff.stdin.end();
  await ff.done;
  await browser.close();
  if (errors.length) throw new Error('page errors:\n' + errors.join('\n'));
}

(async () => {
  const [file, out] = process.argv.slice(2, 4);
  const fps = Number(arg('--fps', 30));
  const format = arg('--format', 'jpeg');

  if (arg('--range')) {                       // worker mode
    const [a, b] = arg('--range').split(':').map(Number);
    await segment(file, a, b, fps, format, out);
    return;
  }

  if (arg('--stills')) {
    const { browser, page, errors } = await openPage(file);
    fs.mkdirSync(out, { recursive: true });
    for (const s of arg('--stills').split(',').map(Number)) {
      await page.evaluate(t => window.renderAt(t), s);
      await page.screenshot({ path: path.join(out, `t${s.toFixed(2).padStart(6, '0')}.png`) });
    }
    await browser.close();
    if (errors.length) throw new Error('page errors:\n' + errors.join('\n'));
    return;
  }

  const t0 = Date.now();
  const { browser, page } = await openPage(file);
  const total = await page.evaluate(() => window.TL.total);
  await browser.close();
  const n = Math.round(total * fps);
  const workers = Number(arg('--workers', Math.max(1, Math.min(8, os.cpus().length - 1))));
  const tmp = fs.mkdtempSync(path.join(path.dirname(path.resolve(out)), '.render-'));
  const segs = [];
  const jobs = [];
  for (let w = 0; w < workers; w++) {
    const a = Math.floor(n * w / workers), b = Math.floor(n * (w + 1) / workers);
    const seg = path.join(tmp, `seg${w}.mp4`);
    segs.push(seg);
    jobs.push(run(process.execPath, [__filename, file, seg, '--range', `${a}:${b}`,
      '--fps', String(fps), '--format', format], { stdio: ['ignore', 'inherit', 'inherit'] }).done);
  }
  console.log(`${n} frames, ${workers} workers, ${format} frames`);
  await Promise.all(jobs);
  const tFrames = (Date.now() - t0) / 1000;
  fs.writeFileSync(path.join(tmp, 'list.txt'), segs.map(s => `file '${s}'`).join('\n') + '\n');
  const audio = arg('--audio');
  await run('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(tmp, 'list.txt'),
    ...(audio ? ['-i', audio, '-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', '128k', '-shortest'] : []),
    '-c:v', 'copy', '-movflags', '+faststart', out], { stdio: ['ignore', 'inherit', 'inherit'] }).done;
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`frames+encode ${tFrames.toFixed(1)}s, total ${((Date.now() - t0) / 1000).toFixed(1)}s, ` +
    `${(fs.statSync(out).size / 1e6).toFixed(2)} MB`);
})().catch(e => { console.error(e); process.exit(1); });
