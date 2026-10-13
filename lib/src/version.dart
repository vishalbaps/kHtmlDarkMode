/// The package version, stamped onto every converted document as
/// `data-kdm-version` so a rendering can always be traced to the engine that
/// produced it.
///
/// Kept equal to `pubspec.yaml` by a test. Bump the minor on any change to a
/// mapped colour (the golden vectors change), the patch on a fix that leaves
/// every mapped colour identical.
const String kdmVersion = '1.0.0';
