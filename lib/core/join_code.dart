import 'dart:math';

/// Join codes double as encryption secret (see GroupCrypto), so they must be
/// long enough to resist brute force: 10 chars from 29 symbols ≈ 48 bit,
/// further hardened by slow key derivation.
/// The alphabet omits look-alikes (0/O, 1/I/L, U/V).
abstract final class JoinCode {
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTWXYZ';
  static const length = 10;

  static String generate({Random? random}) {
    final r = random ?? Random.secure();
    final raw = List.generate(
      length,
      (_) => alphabet[r.nextInt(alphabet.length)],
    ).join();
    return format(raw);
  }

  /// `ABCDE12345` → `ABCDE-12345`.
  static String format(String raw) =>
      '${raw.substring(0, length ~/ 2)}-${raw.substring(length ~/ 2)}';

  /// Normalizes user input (case, spaces, dashes). Returns null if invalid.
  static String? normalize(String input) {
    final raw = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (raw.length != length) return null;
    if (raw.split('').any((c) => !alphabet.contains(c))) return null;
    return format(raw);
  }
}
