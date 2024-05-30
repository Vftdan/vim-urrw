# Vim universal resource read-write
Modular Netrw replacement

## TODO
 - [v] url utilities
 - [ ] security (prevent loading of arbitrary urls from untrusted sources)
 - [ ] buffered read/write autocommand
 - [ ] read/write functions
  + whole file
  + range (download to `$TMP` when not supported)
  + ability to use process stdin & stdout to implement read & write (e. g. `curl`, `openssl s_client`)
 - [ ] redirect handling (e. g. http 3xx and file:// to non-url paths)
 - [ ] url scheme registration api
 - [ ] netrw suppressor
 - [ ] ? directory-like ui ftplugin (do nerdtree & similar plugins provide api for this?)
  + list modes (by default remap modification keys, e. g. `gh` for mark mode, `cw` to rename file, `cm` to chmod)
  + copy urls
 - [ ] ? mime-aware clipboard handling
  + use `text/uri-list` for directory-like buffers
 - modules
  + [ ] http, https, other curl-compatible protocols
  + [ ] gemini protocol
  + [ ] zip & other archives url scheme
  + [ ] ssh/scp/rsync protocol (ssh-agent integration? (parse `ssh-agent` output and send `$SSH_AUTH_SOCK` and `$SSH_AGENT_PID`))
  + [ ] `gf` key family handling (netgf urrw port)

