# Architecture

Pkgutils has no package scripts or solver. A separate adapter checks declared native requirements, invokes native commands, and reconciles even after a native failure. Publication stays atomic while native files are not rolled back. Native configuration rules apply; removal deletes owned edits. CRUX ports retain Nix artifact references and native footprint metadata. prt-get uses supported addcommand/removecommand selection; foreign roots are rejected before host activation. No invented removal script or watcher is claimed.
