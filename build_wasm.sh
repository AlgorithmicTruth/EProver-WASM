#!/bin/bash
# Build E Prover as a WebAssembly module using Emscripten
# Usage: source emsdk_env.sh && ./build_wasm.sh

set -e

# Check for emcc
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc not found. Run: source /path/to/emsdk/emsdk_env.sh"
    exit 1
fi

echo "=== Building E Prover for WebAssembly ==="

# Compiler settings
CC="emcc"
AR="emar rcs"
OPTFLAGS="-O2"
WFLAGS="-Wall -Wno-unused-variable -Wno-unused-function -Wno-parentheses"

BUILDFLAGS="\
    -DENABLE_LFHO \
    -DSTACK_SIZE=32768 \
    -DCLAUSE_PERM_IDENT \
    -DMEMORY_RESERVE_PARANOID \
    -DPRINT_SOMEERRORS_STDOUT \
    -DPRINT_TSTP_STATUS \
    -DTAGGED_POINTERS \
    -DNDEBUG -DFAST_EXIT"

CFLAGS="$OPTFLAGS $WFLAGS $BUILDFLAGS -std=gnu99 -I./include"

OUTDIR="wasm_build"
mkdir -p "$OUTDIR"

# Step 1: Create header symlinks (same as make links)
echo "--- Creating header symlinks ---"
rm -rf include lib
mkdir -p include lib

for hdr in $(find . -not -path './include/*' -not -path './wasm_build/*' -name '[^.]*.h'); do
    ln -sf "../$hdr" "include/$(basename $hdr)" 2>/dev/null || true
done

# Step 2: Build CONTRIB (picosat)
echo "--- Building CONTRIB (picosat) ---"
PICODIR="CONTRIB/picosat-965"
PICO_VERSION=$(cat "$PICODIR/VERSION" 2>/dev/null || echo "965")
cat > "$PICODIR/config.h" <<PICOEOF
#define PICOSAT_VERSION "$PICO_VERSION"
#define PICOSAT_CC "emcc"
#define PICOSAT_CFLAGS "$OPTFLAGS"
PICOEOF
PICO_OBJS=""
for src in picosat.c version.c; do
    obj="$OUTDIR/pico_$(basename $src .c).o"
    $CC $OPTFLAGS -DNDEBUG -DTRACE -std=gnu99 -I"$PICODIR" -c "$PICODIR/$src" -o "$obj"
    PICO_OBJS="$PICO_OBJS $obj"
done
$AR "$OUTDIR/CONTRIB.a" $PICO_OBJS

# Step 3: Build each library
LIBS="BASICS INOUT TERMS ORDERINGS CLAUSES PROPOSITIONAL LEARN PCL2 HEURISTICS CONTROL"

for libdir in $LIBS; do
    echo "--- Building $libdir ---"
    OBJS=""
    for src in $libdir/*.c; do
        obj="$OUTDIR/$(basename $src .c).o"
        $CC $CFLAGS -c "$src" -o "$obj" 2>&1
        OBJS="$OBJS $obj"
    done
    $AR "$OUTDIR/$libdir.a" $OBJS
done

# Step 4: Build the main eprover.c
echo "--- Building eprover.o ---"
# Generate a git commit ID header
echo '#define ECOMMITID "'$(git rev-parse HEAD 2>/dev/null || echo "unknown")'"' > PROVER/e_gitcommit.h
$CC $CFLAGS -c PROVER/eprover.c -o "$OUTDIR/eprover.o"

# Step 5: Link into WASM
echo "--- Linking eprover.js + eprover.wasm ---"
LINK_LIBS="$OUTDIR/eprover.o"
for libdir in CONTROL HEURISTICS LEARN CLAUSES ORDERINGS TERMS INOUT BASICS CONTRIB; do
    LINK_LIBS="$LINK_LIBS $OUTDIR/$libdir.a"
done
# Also link PCL2 and PROPOSITIONAL (needed by some modules)
LINK_LIBS="$LINK_LIBS $OUTDIR/PCL2.a $OUTDIR/PROPOSITIONAL.a"

WEBAPP_DIR="webapps/eprover"
mkdir -p "$WEBAPP_DIR"

$CC $OPTFLAGS \
    $LINK_LIBS \
    -lm \
    -sALLOW_MEMORY_GROWTH=1 \
    -sSTACK_SIZE=8388608 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME='EProverModule' \
    -sINVOKE_RUN=0 \
    -sEXIT_RUNTIME=0 \
    -sFORCE_FILESYSTEM=1 \
    -sEXPORTED_RUNTIME_METHODS='["callMain","FS"]' \
    -sENVIRONMENT='worker,node' \
    -sMIN_SAFARI_VERSION=120200 \
    -sLEGACY_VM_SUPPORT=1 \
    -o "$WEBAPP_DIR/eprover.js"

echo ""
echo "=== Build complete ==="
echo "Output: $WEBAPP_DIR/eprover.js + $WEBAPP_DIR/eprover.wasm"
ls -lh "$WEBAPP_DIR/eprover.js" "$WEBAPP_DIR/eprover.wasm"
