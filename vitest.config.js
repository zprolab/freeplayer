import { defineConfig } from 'vitest/config';
import viteConfig from './vite.config.js';

export default defineConfig({
  test: {
    globals: true,
    setupFiles: ['./tests/setup.js'],
  },
  resolve: {
    alias: viteConfig.resolve.alias,
  },
});
