// ESLint flat config.
//
// The repo carried five `// eslint-disable-line react-hooks/exhaustive-deps`
// comments with no ESLint installed, no config and no lint script — so those
// comments asserted "this dependency array was reviewed" while nothing ever
// checked them. This is the missing gate.
//
// Scope: src/ and tests/ only. The build scripts and the design-system tokens
// are covered by tests instead (tests/uiTokens, tests/uiImports).
import js from '@eslint/js';
import globals from 'globals';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  { ignores: ['dist/**', 'node_modules/**', 'shell/**', 'docs/**', '.codereview/**'] },

  js.configs.recommended,

  {
    files: ['src/**/*.{js,jsx}', 'tests/**/*.{js,jsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser, ...globals.node },
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    settings: { react: { version: 'detect' } },
    plugins: { react, 'react-hooks': reactHooks },
    rules: {
      ...react.configs.flat.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      // The app sets these up on the native side; there is no React Native here.
      'react/prop-types': 'off',
      // vite's automatic JSX runtime means React is not referenced directly.
      'react/react-in-jsx-scope': 'off',
      // Two deliberate patterns in this codebase:
      //   - a `console.error` in every bridge catch (the error is also surfaced
      //     to the user where it matters), and
      //   - empty `catch {}` around best-effort cleanup (disconnect/removeItem).
      'no-empty': ['error', { allowEmptyCatch: true }],
    },
  },

  {
    // Build tooling runs in Node (Buffer, process, __dirname-less ESM).
    files: ['scripts/**/*.mjs', 'vite.config.js', 'vitest.config.js', 'eslint.config.mjs'],
    languageOptions: { globals: { ...globals.node } },
  },

  {
    // __APP_VERSION__ is injected by vite's `define` (vite.config.js:28).
    files: ['src/**/*.{js,jsx}'],
    languageOptions: { globals: { __APP_VERSION__: 'readonly' } },
  },

  {
    // Tests drive hooks through a hand-rolled harness and stub the bridge, so
    // they legitimately poke at window.freeplayer and friends.
    files: ['tests/**/*.{js,jsx}'],
    languageOptions: { globals: { ...globals.browser, ...globals.node, vi: 'readonly' } },
    rules: {
      'react-hooks/rules-of-hooks': 'off',
    },
  },
];
