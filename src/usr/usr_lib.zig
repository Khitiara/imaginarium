//! This module contains the implementation of imaginarium's usermode kernel services; it exposes no `pub` members
//! and should not be imported by user code directly - see `usr.zig`. This library `export`s a number of symbols
//! which `usr.zig` provides `extern` function definitions for.