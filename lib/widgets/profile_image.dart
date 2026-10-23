import 'dart:convert';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? profileImageProvider(String source) {
  if (source.startsWith('data:')) {
    final match = RegExp(
      r'^data:(image/(?:jpeg|png|webp));base64,([A-Za-z0-9+/]*={0,2})$',
    ).firstMatch(source);
    if (match == null) return null;
    try {
      return MemoryImage(base64Decode(match.group(2)!));
    } on FormatException {
      return null;
    }
  }
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return NetworkImage(uri.toString());
}
