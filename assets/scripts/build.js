const fs = require("fs");
const path = require("path");
const { sassPlugin } = require("esbuild-sass-plugin");
const esbuild = require("esbuild");

const ENTRY_FILE = "app.js";
const OUTPUT_DIR = path.resolve(__dirname, "../../priv/static/assets");
const OUTPUT_FILE = "app.js";
const MODE = process.env["NODE_ENV"] || "production";
const TARGET = "es2017";

const isDevMode = MODE === "development";

const buildLogger = {
  name: "build-logger",
  setup(build) {
    let count = 0;
    build.onEnd(({ errors, warnings }) => {
      if (errors.length > 0) console.error("[-] Esbuild failed:", errors);
      else if (warnings.length > 0) console.warn("[-] Esbuild finished with warnings:", warnings);
      else console.log(`[+] Esbuild succeeded`);
    });
  },
};

const build_opts = {
  entryPoints: [path.join(__dirname, "..", "js", ENTRY_FILE)],
  outfile: `${OUTPUT_DIR}/${OUTPUT_FILE}`,
  minify: !isDevMode,
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
  plugins: [sassPlugin(), buildLogger],
  define: {
    "process.env.NODE_ENV": isDevMode ? '"development"' : '"production"',
    global: "window",
  },
  sourcemap: isDevMode,
};

async function build() {
  try {
    console.log(`[+] Starting static assets build with esbuild (${MODE})...`);
    ctx = await esbuild.context(build_opts);

    if (isDevMode) {
      ctx.watch();
      process.stdin.pipe(process.stdout);
      process.stdin.on("end", () => ctx.dispose());
    } else {
      ctx.rebuild();
      ctx.dispose();
    }
  } catch (e) {
    console.error("[-] Error building:", e.message);
    process.exit(1);
  }
}

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR);

build();
