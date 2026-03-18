String onlyDigits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

String normalizeArPhone(String input) {
  final d = onlyDigits(input);
  if (d.isEmpty) return '';
  if (d.startsWith('549') && d.length >= 13) return d.substring(d.length - 10);
  if (d.startsWith('54') && d.length >= 12) return d.substring(d.length - 10);
  if (d.length == 11 && d.startsWith('0')) return d.substring(1);
  if (d.length == 11 && d.startsWith('9')) return d.substring(1);
  if (d.length > 10) return d.substring(d.length - 10);
  return d;
}

String formatE164Ar(String phoneDigits10) => '+549$phoneDigits10';
