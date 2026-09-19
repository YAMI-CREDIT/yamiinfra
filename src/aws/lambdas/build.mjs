import { build } from "esbuild";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();

// Discover every <dir>/index.ts as a Lambda entry point.
const dirs = await readdir(root);
const entries = [];
for (const dir of dirs) {
    const entry = path.join(dir, "index.ts");
    try {
        const s = await stat(path.join(root, entry));
        if (s.isFile()) {
            entries.push({ entry, outfile: `dist/${dir}/index.js` });
        }
    } catch {
        // not a directory or no index.ts — skip
    }
}

if (entries.length === 0) {
    console.error("No Lambda entry points found (expected <dir>/index.ts)");
    process.exit(1);
}

await Promise.all(
    entries.map((e) =>
        build({
            entryPoints: [e.entry],
            bundle: true,
            platform: "node",
            target: "node20",
            outfile: e.outfile,
        })
    )
);

console.log(
    `Built ${entries.length} Lambda(s): ${entries.map((e) => e.outfile).join(", ")}`
);
