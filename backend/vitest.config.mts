import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

// SWC so decorator metadata (Nest dependency injection) survives in tests.
const plugins = [swc.vite({ module: { type: 'es6' } })];

export default defineConfig({
  test: {
    projects: [
      { plugins, test: { name: 'unit', include: ['src/**/*.spec.ts'], environment: 'node' } },
      {
        plugins,
        test: {
          name: 'e2e',
          include: ['test/**/*.e2e.ts'],
          environment: 'node',
          globalSetup: ['test/global-setup.ts'],
          setupFiles: ['test/setup-env.ts'],
          fileParallelism: false,
          testTimeout: 30_000,
          hookTimeout: 120_000,
        },
      },
    ],
  },
});
