import yauzl from 'yauzl';

/** Entries of a ZIP: name → bytes. */
export function unzip(buffer: Buffer): Promise<Map<string, Buffer>> {
  return new Promise((resolve, reject) => {
    yauzl.fromBuffer(buffer, { lazyEntries: true }, (error, file) => {
      if (error || !file) return reject(error ?? new Error('no zip'));
      const entries = new Map<string, Buffer>();
      file.on('entry', (entry: yauzl.Entry) => {
        file.openReadStream(entry, (streamError, stream) => {
          if (streamError || !stream) return reject(streamError ?? new Error('no stream'));
          const chunks: Buffer[] = [];
          stream.on('data', (c: Buffer) => chunks.push(c));
          stream.on('end', () => {
            entries.set(entry.fileName, Buffer.concat(chunks));
            file.readEntry();
          });
        });
      });
      file.on('end', () => resolve(entries));
      file.on('error', reject);
      file.readEntry();
    });
  });
}
