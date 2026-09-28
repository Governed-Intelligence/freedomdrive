import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [react()],
    server: {
      host: true,
      allowedHosts: true,
      port: 5173,
      proxy: {
        '/v1': { target: env.API_PROXY_TARGET || env.VITE_API_URL || 'http://localhost:8080', changeOrigin: true },
      },
    },
    build: { outDir: 'dist', sourcemap: true },
  };
});
