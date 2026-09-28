/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        cream: { 50: '#fefefd', 100: '#faf8f5', 200: '#f4f1ea' },
        burgundy: { 50: '#fdf3f3', 100: '#fbe5e5', 200: '#f7c5c5', 300: '#f09a9a', 400: '#e06060', 500: '#a82a2a', 600: '#8b1e1e', 700: '#6e1616', 800: '#571212' },
        gold: { 50: '#fdf9ee', 100: '#faf0cf', 400: '#d4a84b', 500: '#b8912f', 600: '#9a7621' },
        navy: { 50: '#f1f4f8', 100: '#dbe3ee', 500: '#476889', 700: '#2c4a6b', 800: '#1e3a5f' },
      },
      fontFamily: {
        display: ['"Cormorant Garamond"', 'Georgia', 'serif'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 3px rgba(0,0,0,0.04), 0 4px 12px rgba(0,0,0,0.06)',
        lux: '0 2px 6px rgba(139,30,30,0.08), 0 12px 32px rgba(30,58,95,0.08)',
      },
    },
  },
  plugins: [],
};
