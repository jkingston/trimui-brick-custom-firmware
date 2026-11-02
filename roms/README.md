# Demo ROMs

`make demo-roms` downloads publicly distributed homebrew games from pinned author
releases or source revisions and verifies their hashes. ROM files are local
test data and are ignored by Git.

- **Falling** by Jesse Williams: MIT, source revision
  `52dcb8a951200562e696dfc2aba5d4d14edd0078` at
  <https://github.com/xram64/falling-nes>.
- **Minekart Madness** by Matt Hughson: MIT, release `v1.0` at
  <https://github.com/mhughson/mbh-cart/releases/tag/v1.0>.
- **Adjustris** by tbsp: CC0-1.0, release `v1.1` at
  <https://github.com/tbsp/Adjustris/releases/tag/v1.1>.
- **@rkanoid** by Ben Orozco: MIT modern rebuild at source revision
  `b61cb1e8d6646789c833522a7d3d64adda27581a` in
  <https://github.com/benoror/gbadev>.
- **Willow's Dream** by Marcellodash: LGPL-3.0 source, pinned at revision
  `9ff80c7ef5f7b31e178b57fd4542f8ceee27eca4` in
  <https://github.com/marcellodash/willows-dream>.

Copy the contents of this directory's `FC`, `GB`, `GBA` and `MD` folders into
matching folders under `Roms/` on the content partition. ROM binaries are not
included in firmware images.
