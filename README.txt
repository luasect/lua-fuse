Lua Fuse

A very simple Lua program designed to compact all Lua files into 1 without
touching any of the source code.

NOTE 1: The require system gets adjusted to only load modules in the lua file
and libraries like it does normally.

This means:
- It can not load modules outside of the file (with libraries being an
exception)
- Dynamic require systems will break.

NOTE 2: If require is called with a variable input, it will be ignored. This
system only captures patterns like require("string").

Developer note: The code is pretty hastily written and probably has few
unnoticed bugs, if you encounter any such bugs. Please open an issue.