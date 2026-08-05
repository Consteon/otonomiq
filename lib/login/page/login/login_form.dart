// from https://medium.com/flutter-community/firebase-login-with-flutter-bloc-47455e6047b0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart' show openInWebView;
import '../../../global.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/bloc_authentication/bloc.dart';
import '../../../login/page/login/login.dart';

class LoginForm extends StatefulWidget {
  final UserRepository _userRepository;
  final String? tosText;
  final String? tosRoute;
  final BuildContext? parentContext;
  final dynamic component;
  final dynamic route;

  const LoginForm({
    required Key key,
    required this._userRepository,
    this.tosText,
    this.tosRoute,
    this.parentContext,
    this.component,
    this.route,
  }) : assert(component != null),
       super(key: key);

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  final TextEditingController _vidController = TextEditingController();
  final TextEditingController _invController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();

  LoginBloc? _loginBloc;
  bool _tosOk = false;
  // Stable keys: created once, not per-build, so rebuilds don't throw the
  // social buttons' elements away.
  final GlobalKey _appleBtnKey = GlobalKey();
  final GlobalKey _googleBtnKey = GlobalKey();
  // Drives the full-screen processing overlay. OverlayPortal renders the dim +
  // spinner into the root Overlay, so it covers the WHOLE screen (not just this
  // form's card bounds) while staying tied to this widget's lifecycle — it is
  // torn down with LoginForm on the login→home swap, so it can never strand
  // over the home page the way the old root-navigator showDialog did.
  final OverlayPortalController _spinnerOverlay = OverlayPortalController();
  String tText = 'a';
  UserRepository get _userRepository => widget._userRepository;

  bool get isPopulated =>
      //      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;
      _phoneController.text.isNotEmpty;

  bool isLoginButtonEnabled(LoginState state) {
    return state.isFormValid &&
        _smsCodeController.text.isNotEmpty &&
        state.isWaitingSmsCode &&
        state.isSmsCodeValid;
  }

  bool isSmsButtonEnabled(LoginState state) {
    return state.isFormValid &&
        _phoneController.text.isNotEmpty &&
        !state.isWaitingSmsCode &&
        state.isTosOK;
  }

  bool isOtherProviderEnabled(LoginState state) {
    return state.isTosOK;
  }

  bool isInvNeeded(LoginState state) {
    return state.loginUid != '';
  }

  @override
  void initState() {
    super.initState();
    _loginBloc = BlocProvider.of<LoginBloc>(context);
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);
    _phoneController.addListener(_onPhoneChanged);
    _smsCodeController.addListener(_onSmsCodeChanged);
    _vidController.addListener(_onVidChanged);
    _invController.addListener(_onInvChanged);
    _countryController.addListener(_onCountryChanged);
    _countryController.text = "Indonesia";
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener(
      bloc: _loginBloc,
      listener: (BuildContext context, LoginState state) {
        // The blocking spinner is rendered declaratively in the BlocBuilder
        // below (keyed on loginSpinnerVisible(state)); nothing to show/dismiss
        // imperatively here.
        //
        // Dismiss the soft keyboard the moment login starts processing. The old
        // showDialog pushed a modal route that stole focus (hiding the keyboard
        // as a side effect); the declarative overlay does not, so without this
        // the numeric keypad stays up and the overlay floats above it, leaving a
        // grey gap. Unfocusing lets the body — and the full-screen overlay —
        // reclaim the keyboard's space.
        if (loginSpinnerVisible(state)) {
          FocusScope.of(context).unfocus();
          if (!_spinnerOverlay.isShowing) _spinnerOverlay.show();
        } else {
          if (_spinnerOverlay.isShowing) _spinnerOverlay.hide();
        }

        if (state.isFailure) {
          _userRepository.systemSignOut();
          if (state.loginStatus == 2) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['AnotherUserLogin']),
                  content: Text(
                    textList['AnotherUserLoginMessage'],
                  ), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 3) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['PhoneNotMatch']),
                  content: Text(textList['PhoneNotMatchMessage']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 7) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['PhoneUsed']),
                  content: Text(textList['PhoneUsedMessage']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 1) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Full']),
                  content: Text(textList['FullMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 4) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['SignInError']),
                  content: Text(textList['SignInErrorMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 5) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['SignInError']),
                  content: Text(textList['SignInErrorGoogle']),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 802) {
            // got text from guest | VM>JSON
            // read from Firestore
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Error802']),
                  content: Column(
                    mainAxisSize: MainAxisSize
                        .min, // Column length = sum of children length
                    children: [
                      Text(textList['Error802Message']),
                      Container(height: 10),
                      Text(textList["802"]),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else if (state.loginStatus == 809) {
            // got text from guest | VM>JSON
            // read from Firestore
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['Error809']),
                  content: Column(
                    mainAxisSize: MainAxisSize
                        .min, // Column length = sum of children length
                    children: [
                      Text(textList['Error809Message']),
                      Container(height: 10),
                      Text(textList['NoAccount']),
                      Container(height: 10),
                      Text(textList['AdminRegisterAccount']),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          } else {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(textList['LoginFail']),
                  content: Text(textList['LoginFailMessage']), // show dialog
                  actions: <Widget>[
                    TextButton(
                      child: Text(textList["OK"]),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            );
          }
        } else if (state.isSuccess) {
          BlocProvider.of<AuthenticationBloc>(context).add(LoggedIn());
        } else if (state.loginUid != '') {
          gotoRoute(
            widget.route ?? '_Invitation',
          ); // delete this line, change it with new user getter.
        }
      },
      child: BlocBuilder(
        bloc: _loginBloc,
        builder: (BuildContext context, LoginState state) {
          final primary = Theme.of(context).primaryColor;
          final darkPrimary = HSLColor.fromColor(
            primary,
          ).withLightness(0.15).withSaturation(0.6).toColor();
          final accentColor = HSLColor.fromColor(
            primary,
          ).withLightness(0.45).withSaturation(0.7).toColor();

          return OverlayPortal(
            controller: _spinnerOverlay,
            overlayChildBuilder: _buildSpinnerOverlay,
            // Light layout on the page's own background: the form used to
            // paint a dark gradient inside its bounds, which clashed with the
            // light logo strip the page JSON renders above it. maxWidth keeps
            // the card phone-sized on tablets/landscape.
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Form(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),

                          Text(
                            widget.component['subtitle'] ??
                                'Masuk ke akun Anda',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              color: darkPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.component['subtitle2'] ??
                                'Gunakan nomor ponsel terdaftar Anda',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Login card — one entrance motion for the whole
                          // card (fade + rise), everything else stays still.
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, child) => Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(0, 16 * (1 - t)),
                                child: child,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.05),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Invitation / phone input
                                  TextField(
                                    controller: _invController,
                                    keyboardType: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
                                    ],
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp('[0-9]+'),
                                      ),
                                    ],
                                    style: const TextStyle(
                                      fontSize: 16,
                                      letterSpacing: 0.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: widget.component['text3'],
                                      hintText: widget.component['text4'],
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      prefixIcon: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 10,
                                          right: 8,
                                        ),
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              11,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.phone_android_rounded,
                                            size: 20,
                                            color: accentColor,
                                          ),
                                        ),
                                      ),
                                      // minHeight 0: with a min-height the
                                      // decorator stretches the 38px tile to
                                      // fill the whole field height.
                                      prefixIconConstraints:
                                          const BoxConstraints(minWidth: 56),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: accentColor,
                                          width: 1.8,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 18,
                                            horizontal: 16,
                                          ),
                                    ),
                                  ),

                                  // TOS checkbox below input
                                  if (!state.isWaitingSmsCode) ...[
                                    const SizedBox(height: 16),
                                    GestureDetector(
                                      onTap: _onTosOKTabbed,
                                      behavior: HitTestBehavior.opaque,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        curve: Curves.easeOut,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _tosOk
                                              ? accentColor.withValues(
                                                  alpha: 0.08,
                                                )
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: _tosOk
                                                ? accentColor.withValues(
                                                    alpha: 0.35,
                                                  )
                                                : Colors.grey.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: _tosOk
                                                    ? accentColor
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                border: Border.all(
                                                  color: _tosOk
                                                      ? accentColor
                                                      : Colors.grey.shade400,
                                                  width: 2,
                                                ),
                                              ),
                                              child: _tosOk
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 17,
                                                      color: Colors.white,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Flexible(
                                              child: GestureDetector(
                                                onTap: () {
                                                  // ponytail: single-language ToS
                                                  // — skip the 1-item _Legal menu
                                                  // and open the regulation URL
                                                  // directly. Auto-reverts to the
                                                  // menu if _Legal ever holds >1
                                                  // item (e.g. multi-language).
                                                  final route =
                                                      widget.tosRoute!;
                                                  final kids =
                                                      screenUIComponent[route]?['children'];
                                                  if (kids is List &&
                                                      kids.length == 1 &&
                                                      kids[0] is Map &&
                                                      kids[0]['route']
                                                          is String &&
                                                      (kids[0]['route']
                                                              as String)
                                                          .toLowerCase()
                                                          .startsWith('http')) {
                                                    final rawTitle =
                                                        kids[0]['title'];
                                                    openInWebView(
                                                      context,
                                                      kids[0]['route'],
                                                      // "Peraturan Layanan
                                                      // (Bahasa Indonesia)" ->
                                                      // "Peraturan Layanan"
                                                      rawTitle is String
                                                          ? rawTitle
                                                                .split('(')
                                                                .first
                                                                .trim()
                                                          : widget.tosText,
                                                    );
                                                  } else {
                                                    gotoRoute(route);
                                                  }
                                                },
                                                child: Text(
                                                  widget.tosText!,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey.shade700,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 20),

                                  // Divider
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          widget.component['divider'] ??
                                              'Masuk dengan',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Social buttons — enabled only when TOS checked & phone filled
                                  AbsorbPointer(
                                    absorbing: !_isLoginReady(),
                                    child: AnimatedOpacity(
                                      opacity: _isLoginReady() ? 1.0 : 0.45,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (sinner) ...[
                                            AppleLoginButton(
                                              key: _appleBtnKey,
                                              component: widget.component,
                                              country: _countryController.text,
                                              inv: _invController.text,
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          GoogleLoginButton(
                                            key: _googleBtnKey,
                                            component: widget.component,
                                            country: _countryController.text,
                                            inv: _invController.text,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Footer
                          Text(
                            widget.component['footer'] ??
                                '© ${DateTime.now().year} $thisAppName',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Full-screen processing overlay, shown via OverlayPortal into the root
  // Overlay. Because the overlay child is laid out inside the Overlay's own
  // Stack, Positioned.fill covers the ENTIRE screen (incl. the app bar) — the
  // dim the user asked for — instead of being clipped to this form's card.
  Widget _buildSpinnerOverlay(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final accent = HSLColor.fromColor(
      primary,
    ).withLightness(0.45).withSaturation(0.7).toColor();
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 60),
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.component['loading'] ?? 'Memproses...',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _vidController.dispose();
    _invController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    _loginBloc!.add(EmailChanged(email: _emailController.text));
  }

  void _onPasswordChanged() {
    _loginBloc!.add(PasswordChanged(password: _passwordController.text));
  }

  void _onSmsCodeChanged() {
    _loginBloc!.add(SmsCodeChanged(smsCode: _smsCodeController.text));
  }

  void _onPhoneChanged() {
    _loginBloc!.add(PhoneChanged(phone: _phoneController.text));
  }

  void _onVidChanged() {
    _loginBloc!.add(VidChanged(vid: _vidController.text));
  }

  void _onInvChanged() {
    _loginBloc!.add(InvChanged(inv: _invController.text));
  }

  void _onCountryChanged() {
    _loginBloc!.add(CountryChanged(country: _countryController.text));
  }

  void _onTosOKTabbed() {
    _tosOk = !_tosOk;
    _loginBloc!.add(TosOKTabbed(tosOk: _tosOk));
  }

  bool _isLoginReady() {
    return _tosOk && _invController.text.isNotEmpty;
  }

  String phoneInternationalize(String phone) {
    String result = phone;
    String one = phone.substring(0, 1);
    if (one == '0') {
      result = '+62${phone.substring(1, phone.length)}';
    }
    return result;
  }

  //  void _onSmsSendPressed() {
  //    String intlPhone = phoneInternationalize(_phoneController.text);
  //    _loginBloc.add(
  //      SendSmsPressed(
  //        phone: intlPhone,
  //      ),
  //    );
  //  }

  //  void _onPhoneLoginPressed() {
  //    _loginBloc.add(
  //      LoginWithPhonePressed(
  //        smsCode: _smsCodeController.text,
  //      ),
  //    );
  //  }
}
