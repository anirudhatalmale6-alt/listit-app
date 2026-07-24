import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/country.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/flag_badge.dart';

/// Verify the signed-in account's email and phone number. Both are needed
/// before a member can post their first ad (the backend enforces it). Email
/// uses an emailed code; phone uses an SMS code, and the phone entry carries a
/// flag picker so an Isle of Man (07624) seller is told apart from a mainland
/// UK one — both share +44, so the flag is the only signal.
class VerifyScreen extends StatefulWidget {
  final AuthService auth;
  final ApiService api;

  /// Optional line explaining why they landed here, e.g. "to publish your ad".
  final String? reason;

  const VerifyScreen({super.key, required this.auth, required this.api, this.reason});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

enum _Stage { idle, sent, done }

class _VerifyScreenState extends State<VerifyScreen> {
  // Email
  _Stage _email = _Stage.idle;
  final _emailOtp = TextEditingController();
  bool _emailBusy = false;
  String? _emailErr;

  // Phone
  _Stage _phone = _Stage.idle;
  PhoneCountry _country = kDefaultCountry;
  final _phoneCtrl = TextEditingController();
  final _phoneOtp = TextEditingController();
  bool _phoneBusy = false;
  String? _phoneErr;
  String _sentNumber = ''; // national digits actually sent (reused on confirm)

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    if (u?.emailVerified ?? false) _email = _Stage.done;
    if (u?.phoneVerified ?? false) _phone = _Stage.done;
    _country = countryFor(iso: u?.countryCode, dial: u?.flag);
    if ((u?.phone ?? '').isNotEmpty) _phoneCtrl.text = u!.phone!;
  }

  @override
  void dispose() {
    _emailOtp.dispose();
    _phoneCtrl.dispose();
    _phoneOtp.dispose();
    super.dispose();
  }

  int get _userId => widget.auth.user!.id;

  // --- Email ---------------------------------------------------------------

  Future<void> _sendEmail() async {
    setState(() {
      _emailBusy = true;
      _emailErr = null;
    });
    try {
      await widget.api.sendVerificationCode(type: 1, userId: _userId);
      if (!mounted) return;
      setState(() => _email = _Stage.sent);
    } on ApiException catch (e) {
      if (mounted) setState(() => _emailErr = e.message);
    } catch (_) {
      if (mounted) setState(() => _emailErr = 'Could not send the code. Try again.');
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _confirmEmail() async {
    final code = _emailOtp.text.trim();
    if (code.length < 4) {
      setState(() => _emailErr = 'Enter the code from your email');
      return;
    }
    setState(() {
      _emailBusy = true;
      _emailErr = null;
    });
    try {
      await widget.api.verifyCode(type: 1, otp: code, userId: _userId);
      await widget.auth.markVerified(email: true);
      if (!mounted) return;
      setState(() => _email = _Stage.done);
      _celebrateIfComplete();
    } on ApiException catch (e) {
      if (mounted) setState(() => _emailErr = e.message);
    } catch (_) {
      if (mounted) setState(() => _emailErr = 'Could not verify the code. Try again.');
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  // --- Phone ---------------------------------------------------------------

  /// National significant number (digits only, no trunk 0) to store as `number`.
  String _nsn() {
    var d = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0')) d = d.substring(1);
    return d;
  }

  Future<void> _sendPhone() async {
    final n = _nsn();
    if (n.length < 6) {
      setState(() => _phoneErr = 'Enter a valid phone number');
      return;
    }
    setState(() {
      _phoneBusy = true;
      _phoneErr = null;
    });
    try {
      await widget.api.sendVerificationCode(
        type: 2,
        userId: _userId,
        number: n,
        flag: _country.dial,
        countryCode: _country.iso,
      );
      if (!mounted) return;
      setState(() {
        _sentNumber = n;
        _phone = _Stage.sent;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _phoneErr = e.message);
    } catch (_) {
      if (mounted) setState(() => _phoneErr = 'Could not send the code. Try again.');
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  Future<void> _confirmPhone() async {
    final code = _phoneOtp.text.trim();
    if (code.length < 4) {
      setState(() => _phoneErr = 'Enter the code from the text message');
      return;
    }
    setState(() {
      _phoneBusy = true;
      _phoneErr = null;
    });
    try {
      await widget.api.verifyCode(
        type: 2,
        otp: code,
        userId: _userId,
        number: _sentNumber,
        flag: _country.dial,
        countryCode: _country.iso,
      );
      await widget.auth.markVerified(
        phone: true,
        number: _sentNumber,
        flag: _country.dial,
        countryCode: _country.iso,
      );
      if (!mounted) return;
      setState(() => _phone = _Stage.done);
      _celebrateIfComplete();
    } on ApiException catch (e) {
      if (mounted) setState(() => _phoneErr = e.message);
    } catch (_) {
      if (mounted) setState(() => _phoneErr = 'Could not verify the code. Try again.');
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  void _celebrateIfComplete() {
    if (_email == _Stage.done && _phone == _Stage.done) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("You're verified — you can post ads now 🎉"),
          backgroundColor: AppColors.success,
        ));
    }
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final u = widget.auth.user;
    final allDone = _email == _Stage.done && _phone == _Stage.done;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Verify your account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            widget.reason != null
                ? 'Verify your email and phone ${widget.reason} — it keeps List it safe for everyone.'
                : 'Verify your email and phone to unlock posting ads and to keep List it safe for everyone.',
            style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.slate),
          ),
          const SizedBox(height: 18),
          _emailCard(u?.email ?? ''),
          const SizedBox(height: 14),
          _phoneCard(),
          if (allDone) ...[
            const SizedBox(height: 22),
            Row(
              children: const [
                Icon(Icons.verified_rounded, color: AppColors.success),
                SizedBox(width: 8),
                Expanded(
                  child: Text("All set — your account is fully verified.",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Done'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Widget _header(IconData icon, String title, bool done) => Row(
        children: [
          Icon(done ? Icons.check_circle_rounded : icon,
              color: done ? AppColors.success : AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const Spacer(),
          if (done)
            const Text('Verified',
                style: TextStyle(
                    color: AppColors.success, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _emailCard(String email) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(Icons.mark_email_read_outlined, 'Email address', _email == _Stage.done),
          const SizedBox(height: 8),
          Text(email,
              style: const TextStyle(fontSize: 14, color: AppColors.slate)),
          if (_email == _Stage.idle) ...[
            const SizedBox(height: 14),
            _primary('Send code to my email', _emailBusy, _sendEmail),
          ],
          if (_email == _Stage.sent) ...[
            const SizedBox(height: 14),
            _otpField(_emailOtp, 'Enter the 6-digit code'),
            if (_emailErr != null) _errorText(_emailErr!),
            const SizedBox(height: 12),
            _primary('Confirm email', _emailBusy, _confirmEmail),
            _resend(_emailBusy, _sendEmail),
          ] else if (_emailErr != null && _email == _Stage.idle)
            _errorText(_emailErr!),
        ],
      ),
    );
  }

  Widget _phoneCard() {
    final done = _phone == _Stage.done;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(Icons.smartphone_outlined, 'Phone number', done),
          const SizedBox(height: 12),
          if (done)
            Text('${_country.name} · ${toDisplay()}',
                style: const TextStyle(fontSize: 14, color: AppColors.slate))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _countryPicker(),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    enabled: _phone == _Stage.idle,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                    ],
                    decoration: _dec(_country.hint),
                  ),
                ),
              ],
            ),
            if (_phone == _Stage.sent) ...[
              const SizedBox(height: 14),
              _otpField(_phoneOtp, 'Enter the 6-digit code'),
              if (_phoneErr != null) _errorText(_phoneErr!),
              const SizedBox(height: 12),
              _primary('Confirm phone', _phoneBusy, _confirmPhone),
              Row(
                children: [
                  _resend(_phoneBusy, _sendPhone),
                  const Spacer(),
                  TextButton(
                    onPressed: _phoneBusy
                        ? null
                        : () => setState(() {
                              _phone = _Stage.idle;
                              _phoneOtp.clear();
                              _phoneErr = null;
                            }),
                    child: const Text('Change number'),
                  ),
                ],
              ),
            ] else ...[
              if (_phoneErr != null) _errorText(_phoneErr!),
              const SizedBox(height: 14),
              _primary('Text me a code', _phoneBusy, _sendPhone),
            ],
          ],
        ],
      ),
    );
  }

  String toDisplay() {
    final n = _sentNumber.isNotEmpty ? _sentNumber : (widget.auth.user?.phone ?? '');
    return '+${_country.dial} $n';
  }

  Widget _countryPicker() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _phone == _Stage.idle ? _pickCountry : null,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            FlagBadge(iso: _country.iso),
            const SizedBox(width: 6),
            Text('+${_country.dial}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            const Icon(Icons.arrow_drop_down, color: AppColors.slate),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Country',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            for (final c in kPhoneCountries)
              ListTile(
                leading: FlagBadge(iso: c.iso, width: 30, height: 21),
                title: Text(c.name),
                trailing: Text('+${c.dial}',
                    style: const TextStyle(color: AppColors.slate)),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _country = picked);
  }

  // --- Small shared bits ---------------------------------------------------

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _otpField(TextEditingController c, String hint) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w700),
        decoration: _dec(hint).copyWith(counterText: ''),
      );

  Widget _primary(String label, bool busy, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: busy ? null : onTap,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label),
        ),
      );

  Widget _resend(bool busy, VoidCallback onTap) => TextButton(
        onPressed: busy ? null : onTap,
        child: const Text('Resend code'),
      );

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(msg, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
      );
}
