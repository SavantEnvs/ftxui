# CSI numeric argument: signed integer overflow (UBSan)

`TerminalInputParser::ParseCSI` accumulates decimal CSI arguments with `argument = argument * 10 + digit`
on an `int` (`src/ftxui/component/terminal_input_parser.cpp`, ~line 431). A sequence with more than ~10
digits (e.g. `ESC [ 2 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ;`) overflows it, which UBSan reports as
`signed integer overflow: 240000000 * 10 cannot be represented in type 'int'`.

Reproduce: `./ftxui-terminal_input_parser_test_fuzzer-standalone crash-input`.

Impact: undefined behaviour reachable from untrusted terminal input (benign on most targets, but a
sanitizer-halting crash here). Fix: saturate/clamp the argument (or reject the sequence) once it exceeds
a sane bound instead of multiplying unconditionally.

Kept out of `testsuite/` so it is not replayed as a seed.
