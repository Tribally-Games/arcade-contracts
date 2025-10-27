#!/usr/bin/env bun

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const LCOV_FILE = join(process.cwd(), 'lcov.info');
const EXCLUDE_PATHS = ['src/mocks/', 'src/generated/', 'test/'];

function filterLcovFile() {
  const content = readFileSync(LCOV_FILE, 'utf-8');
  const lines = content.split('\n');

  const filteredLines: string[] = [];
  let skipCurrentRecord = false;

  for (const line of lines) {
    if (line.startsWith('SF:')) {
      const filePath = line.substring(3);
      skipCurrentRecord = EXCLUDE_PATHS.some(excludePath => filePath.includes(excludePath));

      if (!skipCurrentRecord) {
        filteredLines.push(line);
      }
    } else if (line === 'end_of_record') {
      if (!skipCurrentRecord) {
        filteredLines.push(line);
      }
      skipCurrentRecord = false;
    } else if (!skipCurrentRecord) {
      filteredLines.push(line);
    }
  }

  writeFileSync(LCOV_FILE, filteredLines.join('\n'));
  console.log('✓ Coverage report filtered successfully');
  console.log(`  Excluded paths: ${EXCLUDE_PATHS.join(', ')}`);
}

filterLcovFile();
