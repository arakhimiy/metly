import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { expect } from 'vitest';
import { parse } from 'yaml';

// Responses are checked against docs/api/openapi.yaml — the contract the iOS app is built on.
const spec = parse(readFileSync(join(__dirname, '../../docs/api/openapi.yaml'), 'utf8')) as Record<string, unknown>;
const ajv = new Ajv2020({ strict: false, allErrors: true });
addFormats(ajv);
ajv.addSchema({ ...spec, $id: 'openapi' });

/** Asserts `value` matches `components.schemas[name]`. */
export function expectSchema(name: string, value: unknown) {
  const validate = ajv.getSchema(`openapi#/components/schemas/${name}`);
  if (!validate) throw new Error(`No schema ${name}`);
  const ok = validate(value);
  expect(ok, `${name}: ${ajv.errorsText(validate.errors, { separator: '\n' })}\n${JSON.stringify(value, null, 2).slice(0, 2000)}`).toBe(true);
}
