///|
// Keep derived protocol methods available through the type-method syntax.
pub extend ResolvedFlag with Eq::{not_equal, equal}

///|
pub extend ResolvedFlag with @debug.Debug::{to_repr}

///|
pub extend FlagResult with Eq::{not_equal, equal}

///|
pub extend FlagResult with @debug.Debug::{to_repr}

///|
pub extend Package with Eq::{not_equal, equal}

///|
pub extend Package with @debug.Debug::{to_repr}

///|
pub extend Resolution with Eq::{not_equal, equal}

///|
pub extend Resolution with @debug.Debug::{to_repr}

///|
pub extend Location with Eq::{not_equal, equal}

///|
pub extend Location with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{not_equal, equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend EntryKind with Eq::{not_equal, equal}

///|
pub extend EntryKind with @debug.Debug::{to_repr}

///|
pub extend Entry with Eq::{not_equal, equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{not_equal, equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend VersionOp with Eq::{not_equal, equal}

///|
pub extend VersionOp with @debug.Debug::{to_repr}

///|
pub extend Requirement with Eq::{not_equal, equal}

///|
pub extend Requirement with @debug.Debug::{to_repr}
