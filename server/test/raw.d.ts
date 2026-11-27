// vite's ?raw imports (a file's text), for the migration tests
declare module '*.sql?raw' { const text: string; export default text; }
