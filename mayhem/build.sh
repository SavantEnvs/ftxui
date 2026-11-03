#!/usr/bin/env bash
#
# mayhem/build.sh — builds the sanitized FTXUI libraries, the six in-tree libFuzzer harnesses
# (+ their -standalone reproducers), and the project's own GoogleTest suite (normal flags).
# Runs inside the commit image as `mayhem` in /mayhem; re-runnable and offline (GoogleTest comes
# from the apt libgtest-dev package, nothing is fetched).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESSES="canvas_fuzzer color_fuzzer component_fuzzer dom_layout_fuzzer terminal_input_parser_test_fuzzer utf8_fuzzer"

# 1) Sanitized + DWARF-3 + SanCov-instrumented project libraries (static: screen, dom, component).
#    -fsanitize=fuzzer-no-link is unconditional so the fuzzed code has coverage even with no sanitizers.
#    No CMAKE_BUILD_TYPE: a build type would append its own `-g` (DWARF-5) after our -gdwarf-3.
cmake -S . -B build-fuzz -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_CXX_FLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" \
  -DBUILD_SHARED_LIBS=OFF -DFTXUI_ENABLE_INSTALL=OFF -DFTXUI_ENABLE_CCACHE=OFF \
  -DFTXUI_BUILD_EXAMPLES=OFF -DFTXUI_BUILD_TESTS=OFF -DFTXUI_BUILD_DOCS=OFF
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target screen dom component

LIBS="build-fuzz/libftxui-component.a build-fuzz/libftxui-dom.a build-fuzz/libftxui-screen.a"
for l in $LIBS; do [ -f "$l" ] || { echo "missing $l" >&2; exit 1; }; done

# 2) Harnesses: libFuzzer binary + standalone run-once reproducer. Upstream's own harness sources are
#    compiled unmodified. The driver is compiled as C so its LLVMFuzzerTestOneInput ref is unmangled.
HFLAGS="-std=c++17 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -I$SRC/src -I$SRC/include"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o build-fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build-fuzz/standalone_main.o
for h in $HARNESSES; do
  src="$SRC/src/ftxui/component/$h.cpp"
  $CXX $HFLAGS $LIB_FUZZING_ENGINE "$src" build-fuzz/lsan_off.o $LIBS -pthread -o "/mayhem/ftxui-$h"
  $CXX $HFLAGS "$src" build-fuzz/standalone_main.o build-fuzz/lsan_off.o $LIBS -pthread -o "/mayhem/ftxui-$h-standalone"
done

# 3) The project's own GoogleTest suite with NORMAL flags (no sanitizers, no coverage unless asked).
cmake -S . -B build-tests -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DBUILD_SHARED_LIBS=OFF -DFTXUI_ENABLE_INSTALL=OFF -DFTXUI_ENABLE_CCACHE=OFF \
  -DFTXUI_BUILD_EXAMPLES=OFF -DFTXUI_BUILD_TESTS=ON -DFTXUI_BUILD_DOCS=OFF
cmake --build build-tests -j"$MAYHEM_JOBS" --target ftxui-tests
