class Validators {
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&???*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$',
  );
  static final RegExp _phoneRegExp = RegExp(
    // put international phone (not only Id) regex that match firebase phone authentication
    r'(0(\d{9,14}))|(\+62(\d{8,13}))',
  );
  static final RegExp _smsCodeRegExp = RegExp(r'(\d{6})');
  static final RegExp _passwordRegExp = RegExp(
    r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$',
  );
  static final RegExp _vidRegExp = RegExp(r'(\d{12})');
  static final RegExp _pinRegExp = RegExp(r'(\d{6})');

  static bool isValidEmail(String email) {
    return _emailRegExp.hasMatch(email);
  }

  static bool isValidPhone(String phone) {
    return _phoneRegExp.hasMatch(phone);
  }

  static bool isValidSmsCode(String smsCode) {
    return _smsCodeRegExp.hasMatch(smsCode);
  }

  static bool isValidPassword(String password) {
    return _passwordRegExp.hasMatch(password);
  }

  static bool isValidVid(String vid) {
    return _vidRegExp.hasMatch(vid);
  }

  static bool isValidPin(String vid) {
    return _pinRegExp.hasMatch(vid);
  }
}

// test indonesia phone # regex in
// https://regex101.com/r/mSP6kY/5
