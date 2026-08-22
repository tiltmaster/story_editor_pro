import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// Resolves mixed English/Arabic editor content independently from chrome
/// direction. This keeps Arabic alignment natural without mirroring numbers.
TextDirection editorTextDirection(String text) =>
    Bidi.detectRtlDirectionality(text) ? TextDirection.rtl : TextDirection.ltr;
