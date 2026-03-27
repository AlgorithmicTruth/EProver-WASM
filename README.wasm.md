E Prover -- WebAssembly Build
=============================

This documents how to compile E Prover to WebAssembly and run the
browser-based theorem-proving webapp locally.


Prerequisites
-------------

* **Emscripten SDK (emsdk)** -- install once:

  ```sh
  git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
  cd ~/emsdk
  ./emsdk install latest
  ./emsdk activate latest
  ```

* **Git** (the build script stamps the commit ID into the binary)


Building
--------

```sh
source ~/emsdk/emsdk_env.sh
./build_wasm.sh
```

This takes about 60 seconds and produces two files in `webapps/eprover/`:

| File           | Size  | Description                          |
|----------------|-------|--------------------------------------|
| `eprover.js`   | ~60K  | Emscripten glue (module loader)      |
| `eprover.wasm` | ~2.4M | Compiled E Prover binary             |

The build uses `-O2` optimisation and enables higher-order logic
(`-DENABLE_LFHO`), tagged pointers, and all standard E features.


Serving the webapp
------------------

Any static HTTP server will work.  The simplest option:

```sh
cd webapps/eprover
python3 -m http.server 8787
```

Then open http://localhost:8787 in a browser.

The webapp requires a server because browsers block `fetch()` and
`Worker` from `file://` URLs.  Any of these alternatives also work:

```sh
# Node.js
npx serve webapps/eprover

# Ruby
cd webapps/eprover && ruby -run -ehttpd . -p8787

# PHP
cd webapps/eprover && php -S localhost:8787
```


Using the webapp
----------------

The interface mirrors the Prover9+Mace4 webapp at
https://prover9.org/webapps/combo/ and follows the same conventions:

1. Enter TPTP (or LADR) formulas in the **Input** pane.
2. Click **Run** (or press Ctrl+Enter).
3. The prover runs in a Web Worker -- output streams live to the
   **Output** pane.
4. Click **Stop** to terminate a running search.

The prover runs with `--auto --tstp-format --proof-object` by default,
so it will auto-select a strategy and produce a detailed proof if one
is found.

Example problems are available in the **Examples** dropdown and are
served from `webapps/eprover/examples/`.


Testing with Node.js
--------------------

The WASM module can also be used directly from Node.js (without a
browser):

```js
const EProverModule = require('./webapps/eprover/eprover.js');

EProverModule({
  noInitialRun: true,
  print: function(text) { console.log(text); },
  printErr: function(text) { console.error(text); }
}).then(function(Module) {
  Module.FS.writeFile('/input.p', [
    'fof(a, axiom, ![X]: mult(X, e) = X).',
    'fof(b, axiom, ![X]: mult(X, inv(X)) = e).',
    'fof(c, axiom, ![X,Y,Z]: mult(mult(X,Y),Z) = mult(X,mult(Y,Z))).',
    'fof(goal, conjecture, ![X]: mult(e, X) = X).'
  ].join('\n'));

  try {
    var code = Module.callMain(['--auto', '--tstp-format', '/input.p']);
    console.log('Exit code:', code);
  } catch(err) {
    console.log('Exit code:', err.status);
  }
});
```

Run with the emsdk-provided Node.js or any Node.js >= 18:

```sh
node test_eprover.js
```


Worker API
----------

The webapp uses a Web Worker (`eprover-worker.js`) that speaks the
same protocol as the Prover9 webapp workers:

**Main thread -> Worker:**

```js
worker.postMessage({
  type: "run",
  input: "fof(...)",        // problem text
  filename: "/input.p",     // virtual filesystem path
  args: ["--auto", "--tstp-format", "/input.p"]
});
```

**Worker -> Main thread:**

```js
{ type: "ready" }                          // WASM loaded
{ type: "stdout", line: "..." }            // stdout line
{ type: "stderr", line: "..." }            // stderr line
{ type: "done", exitCode: 0 }             // finished
{ type: "error", message: "..." }          // fatal error
```

To stop a running search, terminate and respawn the worker.


Source modifications
--------------------

All changes to the E source use `#ifdef __EMSCRIPTEN__` guards so the
native build is unaffected.  The main adaptations:

* **No fork/signal/rlimit** -- process management is stubbed; the
  prover runs single-threaded in a single strategy pass (auto-mode
  still works by selecting a strategy, it just cannot fork multiple
  strategy processes in parallel).
* **Integer clamping** -- 64-bit `LONG_MAX` constants in strategy
  parameter strings are clamped to 32-bit `LONG_MAX` on WASM instead
  of raising a parse error.
* **No networking** -- socket functions are stubbed (server/client
  modes are not available in WASM).

The native build (`./configure && make`) is not affected by any of
these changes.


Exit codes
----------

| Code | Meaning                        |
|------|--------------------------------|
| 0    | Proof found (Theorem)          |
| 1    | No proof (search exhausted)    |
| 2    | Resource limit exceeded        |
| 3    | Satisfiable                    |
| 6    | No proof (incomplete strategy) |
