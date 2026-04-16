/// Enum to represent the validation status of a scanned code.
enum ValidationStatus {
  valid,
  invalidFormat,
  notFoundInRef, // Not found in the main reference table
  notInPositiveRef, // Not found in the positive validation table
  foundInNegativeRef, // Found in the negative validation table
  duplicate,
  rejected // Manually rejected by user
}

/// Helper class to hold a scanned code, its validation status, and associated reference data.
class ScannedCode {
  final String code;
  final ValidationStatus status;
  final List<dynamic>? refDataRow;

  ScannedCode(this.code, this.status, {this.refDataRow});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ScannedCode &&
              runtimeType == other.runtimeType &&
              code == other.code;

  @override
  int get hashCode => code.hashCode;
}