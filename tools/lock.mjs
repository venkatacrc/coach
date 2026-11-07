#!/usr/bin/env node
/**
 * Keeps the coach's personal content out of the public repo and site in plain text.
 *
 *   node tools/lock.mjs seal   content/ → content.vault, web/content.json → web/content.enc
 *   node tools/lock.mjs open   content.vault → content/   (after a fresh clone)
 *
 * The passcode comes from $COACH_PASSCODE, else from .passcode (git-ignored).
 * File format: "CCH1" (4) | salt (16) | iv (12) | AES-GCM ciphertext.
 * Key: PBKDF2-HMAC-SHA256, 250,000 iterations, 256-bit. web/app.js decrypts the same format.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { webcrypto } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENT = join(ROOT, 'content');
const VAULT = join(ROOT, 'content.vault');
const PLAIN = join(ROOT, 'web', 'content.json');
const SEALED = join(ROOT, 'web', 'content.enc');
const MAGIC = new TextEncoder().encode('CCH1');
const ITER = 250_000;
const subtle = webcrypto.subtle;

function passcode() {
    if (process.env.COACH_PASSCODE) return process.env.COACH_PASSCODE;
    const file = join(ROOT, '.passcode');
    if (existsSync(file)) {
        const p = readFileSync(file, 'utf8').trim();
        if (p) return p;
    }
    console.error('No passcode: put it in .passcode (git-ignored) or set COACH_PASSCODE.');
    process.exit(1);
}

async function key(pass, salt) {
    const base = await subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
    return subtle.deriveKey({ name: 'PBKDF2', salt, iterations: ITER, hash: 'SHA-256' }, base,
        { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

async function encrypt(plain, pass) {
    const salt = webcrypto.getRandomValues(new Uint8Array(16));
    const iv = webcrypto.getRandomValues(new Uint8Array(12));
    const cipher = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv }, await key(pass, salt), plain));
    return Buffer.concat([MAGIC, salt, iv, cipher]);
}

async function decrypt(buf, pass) {
    if (!MAGIC.every((b, i) => buf[i] === b)) throw new Error('not a sealed coach file');
    const salt = buf.subarray(4, 20), iv = buf.subarray(20, 32);
    return Buffer.from(await subtle.decrypt({ name: 'AES-GCM', iv }, await key(pass, salt), buf.subarray(32)));
}

/** Writes only when the plain text changed, so rebuilding doesn't churn the sealed files. */
async function sealFile(plain, dest, pass) {
    if (existsSync(dest)) {
        try {
            if ((await decrypt(readFileSync(dest), pass)).equals(plain)) return false;
        } catch { /* new passcode or damaged file: rewrite */ }
    }
    writeFileSync(dest, await encrypt(plain, pass));
    return true;
}

function walk(dir) {
    return readdirSync(dir).sort().flatMap((name) => {
        const p = join(dir, name);
        if (name.startsWith('.')) return [];
        return statSync(p).isDirectory() ? walk(p) : [p];
    });
}

const command = process.argv[2];
const pass = passcode();

if (command === 'seal') {
    if (!existsSync(CONTENT)) { console.error('content/ is missing; run `node tools/lock.mjs open` first.'); process.exit(1); }
    if (!existsSync(PLAIN)) { console.error('web/content.json is missing; run `python3 tools/build_content.py` first.'); process.exit(1); }
    const files = Object.fromEntries(walk(CONTENT).map((p) => [relative(CONTENT, p), readFileSync(p, 'utf8')]));
    const vault = Buffer.from(JSON.stringify({ files }, null, 1));
    const a = await sealFile(vault, VAULT, pass);
    const b = await sealFile(readFileSync(PLAIN), SEALED, pass);
    console.log(`content.vault ${a ? 'updated' : 'unchanged'} (${Object.keys(files).length} files) · web/content.enc ${b ? 'updated' : 'unchanged'}`);
} else if (command === 'open') {
    if (!existsSync(VAULT)) { console.error('content.vault is missing.'); process.exit(1); }
    let vault;
    try {
        vault = JSON.parse((await decrypt(readFileSync(VAULT), pass)).toString('utf8'));
    } catch {
        console.error('Could not open content.vault: wrong passcode?');
        process.exit(1);
    }
    for (const [rel, text] of Object.entries(vault.files)) {
        const dest = join(CONTENT, rel);
        mkdirSync(dirname(dest), { recursive: true });
        writeFileSync(dest, text);
    }
    console.log(`Opened ${Object.keys(vault.files).length} files into content/`);
} else {
    console.error('Usage: node tools/lock.mjs seal | open');
    process.exit(1);
}
