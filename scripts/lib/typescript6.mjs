// openapi-typescript builds its output with the JavaScript API of TypeScript, which TypeScript 7 does not have.
// This Node hook gives it @typescript/typescript6, the API package of TypeScript 6, and the rest of the repo stays on TypeScript 7.
// biome-ignore lint/correctness/noNodejsModules: scripts/gen-openapi.sh loads this file into Node, never into a browser
import { registerHooks } from "node:module";

registerHooks({
  resolve(specifier, context, nextResolve) {
    return nextResolve(specifier === "typescript" ? "@typescript/typescript6" : specifier, context);
  },
});
