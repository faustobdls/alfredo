import 'package:alfredo_cli/src/package/package.dart';
import 'package:mason_logger/mason_logger.dart';

/// Builds the resolver `setup` and `package install` use for locally modified
/// managed files. With [force] every modified file is overwritten; otherwise
/// the user is asked per file and a declined prompt keeps the local copy.
ManagedFileConflictResolver managedFileConflictResolver({
  required Logger logger,
  required bool force,
}) {
  return (path) async {
    if (force) return ManagedFileConflict.overwrite;
    final overwrite = logger.confirm('Overwrite locally modified $path?');
    return overwrite ? ManagedFileConflict.overwrite : ManagedFileConflict.skip;
  };
}

/// Warns about managed files an install left untouched because they were
/// modified locally and the user chose to keep them.
void reportSkippedManagedFiles(Logger logger, List<String> skipped) {
  if (skipped.isEmpty) return;
  logger.warn(
    'Kept ${skipped.length} locally modified file(s); re-run with --force to '
    'overwrite:',
  );
  for (final path in skipped) {
    logger.warn('  $path');
  }
}
