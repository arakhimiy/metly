import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { APPLE_ROOT_CERTIFICATES, appleRootCertificates } from './apple-roots';

describe('Apple root certificates', () => {
  it('embeds exactly the vendored .cer files', () => {
    for (const [file, b64] of Object.entries(APPLE_ROOT_CERTIFICATES)) {
      expect(readFileSync(join(__dirname, 'certs', file)).toString('base64'), file).toBe(b64);
    }
  });

  it('are Apple self-signed roots', () => {
    const certs = appleRootCertificates().map((der) => new X509Certificate(der));
    expect(certs.map((c) => c.subject.match(/CN=([^\n]+)/)?.[1]).sort()).toEqual(['Apple Root CA', 'Apple Root CA - G2', 'Apple Root CA - G3']);
    for (const cert of certs) {
      expect(cert.ca).toBe(true);
      expect(cert.verify(cert.publicKey)).toBe(true);
    }
    const g3 = certs.find((c) => c.subject.includes('G3'))!;
    expect(g3.fingerprint256.replace(/:/g, '')).toBe('63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179');
  });
});
