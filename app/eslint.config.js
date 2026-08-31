import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';

export default tseslint.config(
  { ignores: ['**/dist/**', '**/node_modules/**', 'vite.config.ts'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
  {
    files: ['src/server/**/*.ts', 'src/shared/**/*.ts'],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
  {
    files: ['scripts/**/*.mjs'],
    languageOptions: {
      globals: { ...globals.node, ...globals.browser },
    },
  },
  {
    files: ['tests/**/*.ts'],
    languageOptions: {
      globals: { ...globals.node },
    },
    rules: {
      // Test doubles intentionally implement only the Express surface under test.
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
  {
    files: ['src/frontend/**/*.tsx', 'src/frontend/**/*.ts'],
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
    },
    languageOptions: {
      globals: { ...globals.browser },
    },
  },
);
