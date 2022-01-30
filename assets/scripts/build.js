const fs = require("fs");
const path = require("path");
const { sassPlugin } = require("esbuild-sass-plugin");
const esbuild = require("esbuild");

const ENTRY_FILE = "app.js";
const OUTPUT_DIR = path.resolve(__dirname, "../../priv/static/assets");
const OUTPUT_FILE = "app.js";
const MODE = process.env["NODE_ENV"] || "production";
const TARGET = "es2016";

const isDevMode = MODE === "development";

const build_opts = {
  entryPoints: [path.join(__dirname, "..", "js", ENTRY_FILE)],
  outfile: `${OUTPUT_DIR}/${OUTPUT_FILE}`,
  minify: !isDevMode,
  watch: isDevMode && {
    onRebuild(error, result) {
      if (error) console.error("[-] Esbuild failed:", error);
      else console.log(`[+] Esbuild succeeded`);
    },
  },
  bundle: true,
  target: TARGET,
  logLevel: "silent",
  loader: {
    ".png": "dataurl",
    ".ttf": "file",
    ".otf": "file",
    ".svg": "file",
    ".eot": "file",
    ".woff": "file",
    ".woff2": "file",
  },
  plugins: [sassPlugin()],
  define: {
    "process.env.NODE_ENV": isDevMode ? '"development"' : '"production"',
    global: "window",
  },
  sourcemap: isDevMode,
};

async function build() {
  try {
    console.log(`[+] Starting static assets build with esbuild (${MODE})...`);
    result = await esbuild.build(build_opts);
    console.log(`[+] Esbuild ${ENTRY_FILE} to ${OUTPUT_DIR} succeeded.`);

    if (!!build_opts.watch) {
      process.stdin.pipe(process.stdout);
      process.stdin.on("end", () => result.stop());
    }
  } catch (e) {
    console.error("[-] Error building:", e.message);
    process.exit(1);
  }
}

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR);

build();
