import 'package:flutter/services.dart';

import 'persian.dart';

/// ارقام لاتین تایپ شده را همان لحظه فارسی می کند تا کاربر در همه فیلدها
/// (شماره موبایل، کد تایید، مبلغ و ...) عدد فارسی ببیند.
class PersianDigitsFormatter extends TextInputFormatter {
  const PersianDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String converted = Fa.num(newValue.text);
    if (converted == newValue.text) {
      return newValue;
    }
    if (converted.length == newValue.text.length &&
        newValue.selection.isValid) {
      final int base =
          newValue.selection.baseOffset.clamp(0, converted.length);
      final int extent =
          newValue.selection.extentOffset.clamp(0, converted.length);
      return TextEditingValue(
        text: converted,
        selection: TextSelection(baseOffset: base, extentOffset: extent),
      );
    }
    return TextEditingValue(
      text: converted,
      selection: TextSelection.collapsed(offset: converted.length),
    );
  }
}
