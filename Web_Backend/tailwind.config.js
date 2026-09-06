/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./Views/**/*.cshtml', './Areas/**/*.cshtml'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // Stock Tailwind slate-50/100/400/500 read as near-white-on-white in
        // light mode — every card border, muted label, and secondary text
        // color in the admin views uses these, so low contrast shows up
        // everywhere at once. Re-tuning the scale here (rather than editing
        // every view) darkens/saturates just the light-mode-relevant shades;
        // dark mode already uses 700/800/900/950 and is untouched.
        slate: {
          50: '#eef1f6',
          100: '#e2e7f0',
          200: '#cbd3e1',
          400: '#64748b',
          500: '#475569',
        },
      },
    },
  },
  plugins: [],
}
