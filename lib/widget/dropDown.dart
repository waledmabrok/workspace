import 'package:flutter/material.dart';
import '../utils/colors.dart';

class CustomDropdownFormField<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;

  const CustomDropdownFormField({
    super.key,
    required this.hint,
    required this.value,
    required this.items,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      dropdownColor: AppColorsDark.bgCardColor, // نفس خلفية الفورم
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppColorsDark.bgColor.withOpacity(
          0.1,
        ), // خلفية الفورم زي CustomFormField
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColorsDark.strokColor, // ✅ نفس اللون من الفورم
            width: 1.5,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(
            color: AppColorsDark.mainColor, // ✅ نفس اللون من الفورم
            width: 2,
          ),
        ),
      ),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
    );
  }
}
