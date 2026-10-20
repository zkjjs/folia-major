import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { traditionalLocalePlugin } from '../../dev/i18n/traditionalLocalePlugin.mjs';
// A single script and stylesheet can be embedded offline in WKWebView.
export default defineConfig({
    plugins: [react(), traditionalLocalePlugin()],
    define: {
        'process.env.NODE_ENV': JSON.stringify('production'),
        __COMMIT_HASH__: JSON.stringify('ios'),
        __GIT_BRANCH__: JSON.stringify('codex/folia-ios'),
        __BUILD_REPO__: JSON.stringify('zkjjs/folia-major'),
        __BUILD_COMMIT__: JSON.stringify('ios'),
        __BUILD_KIND__: JSON.stringify('development'),
        __BUILD_HOST__: JSON.stringify('ios'),
        __APP_VERSION__: JSON.stringify('0.1.0'),
        __APP_VERSION_LABEL__: JSON.stringify('Folia iOS'),
        __APP_RELEASE_CHANNEL__: JSON.stringify('development'),
        __DOCKER_STACK_VERSION__: JSON.stringify(''),
    },
    build: {
        outDir: fileURLToPath(new URL('../web-dist', import.meta.url)),
        emptyOutDir: true,
        target: 'safari18',
        cssCodeSplit: false,
        lib: {
            entry: fileURLToPath(new URL('./entry.tsx', import.meta.url)),
            name: 'FoliaLyrics',
            formats: ['iife'],
            fileName: () => 'lyrics.js',
        },
        rollupOptions: { output: { inlineDynamicImports: true } },
    },
});
