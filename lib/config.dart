/// Base URL for balance-academy.com's API. Change this if pointing the
/// app at a different teacher's platform (the same /api/assistant/* surface
/// exists identically on every LearnQuad-lineage platform on this account).
const String apiBaseUrl = 'https://balance-academy.com/api';

/// Prefix every generated student QR code starts with (see
/// resources/views/student/dashboard.blade.php on the web platform:
/// QrCode::generate('MK-' . auth()->user()->student_number)). Note this
/// differs from mostafa-solaiman/amirsalama's 'LQ-' prefix with zero-padding
/// - balance-academy uses 'MK-' with no padding. The parsing logic below
/// (roster_screen.dart) only does int.tryParse() on whatever follows the
/// prefix, so padding doesn't matter either way - only the prefix itself
/// needs to match per-platform.
const String qrCodePrefix = 'MK-';

/// Rotating QR shown by the Balance Academy student app:
/// `MSQ1:{student_no}:{counter}:{mac as 18 hex}`. It can only be verified by the
/// server (the secret never leaves the student's phone), via /assistant/attendance/bulk.
const String rotatingQrPrefix = 'MSQ1:';
