#!/usr/bin/env node
// Sync ARB files from apps/client/lib/l10n/arb/ into functions/l10n/.
//
// The Cloud Functions runtime renders notification text server-side (for
// FCM push) using the same ARB files the client uses, keyed by the
// recipient's locale. Rather than maintaining two copies, this script
// copies them at build time. Hooked as the `prebuild` npm script so
// `npm run build` and the Firebase predeploy step both refresh l10n/.

import {readdirSync, mkdirSync, copyFileSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, '..', '..', 'apps', 'client', 'lib', 'l10n', 'arb');
const dst = join(here, '..', 'l10n');

mkdirSync(dst, {recursive: true});

const files = readdirSync(src).filter(
  (f) => f.startsWith('app_') && f.endsWith('.arb'),
);
for (const file of files) {
  copyFileSync(join(src, file), join(dst, file));
}

console.log(`sync-arbs: copied ${files.length} ARB files to functions/l10n/`);
