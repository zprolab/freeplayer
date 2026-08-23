import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { execSync } from 'child_process';

// Build version — same rule as scripts/bundle.sh / build-ipad.sh:
// <pkg.version> on an exact git tag, otherwise <pkg.version>-<git-short-hash>.
// Injected as __APP_VERSION__ so the About page matches the native bundles.
function buildVersion() {
  const pkg = require('./package.json');
  try {
    execSync('git describe --tags --exact-match', { stdio: 'ignore' });
    return pkg.version; // tagged build
  } catch {
    /* not on a tag */
  }
  try {
    const hash = execSync('git rev-parse --short HEAD').toString().trim();
    return hash ? `${pkg.version}-${hash}` : pkg.version;
  } catch {
    return pkg.version; // no git (e.g. CI source tarball)
  }
}

export default defineConfig({
  plugins: [react()],
  define: {
    __APP_VERSION__: JSON.stringify(buildVersion()),
  },
  base: './',
  root: '.',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'esnext',
    minify: 'terser',
    terserOptions: {
      compress: { passes: 2, drop_console: false },
      mangle: true,
    },
    cssMinify: 'lightningcss',
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/react') || id.includes('node_modules/scheduler')) {
            return 'react';
          }
        },
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
