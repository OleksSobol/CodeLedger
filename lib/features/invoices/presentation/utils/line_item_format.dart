final RegExp _datePattern = RegExp(r'^[A-Za-z]+ \d+, \d{4}$');

class LineItemDescription {
  final String? date;
  final String description;

  const LineItemDescription({this.date, required this.description});
}

LineItemDescription splitLineItemDescription(String raw) {
  final parts = raw.split(' | ');
  if (parts.length > 1 && _datePattern.hasMatch(parts.first.trim())) {
    return LineItemDescription(
      date: parts.first.trim(),
      description: parts.skip(1).join(' | '),
    );
  }
  return LineItemDescription(description: raw);
}

String joinLineItemDescription(String? date, String description) {
  final trimmedDesc = description.trim();
  if (date != null && date.trim().isNotEmpty) {
    return '${date.trim()} | $trimmedDesc';
  }
  return trimmedDesc;
}
