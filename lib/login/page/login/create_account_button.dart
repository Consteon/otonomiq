import 'package:flutter/material.dart';
import '../../../login/api/user_repository.dart';
import '../../../login/page/register/register.dart';

class CreateAccountButton extends StatelessWidget {
  final UserRepository _userRepository;

  const CreateAccountButton({required Key key, required UserRepository userRepository})
      : _userRepository = userRepository,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      child: const Text(
        'Create an Account',
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) {
            return RegisterScreen(userRepository: _userRepository);
          }),
        );
      },
    );
  }
}
