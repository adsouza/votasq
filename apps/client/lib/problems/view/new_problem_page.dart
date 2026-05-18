import 'dart:async';
import 'dart:developer';

import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/widgets/geoscope_picker.dart';
import 'package:client/problems/widgets/geoscope_widgets.dart';
import 'package:client/problems/widgets/problem_text_utils.dart';
import 'package:client/services/firestore_repository.dart'
    show FirestoreRepository, LanguageMismatchException;
import 'package:client/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

class NewProblemPage extends StatefulWidget {
  const NewProblemPage({super.key});

  @override
  State<NewProblemPage> createState() => _NewProblemPageState();
}

class _NewProblemPageState extends State<NewProblemPage> {
  final _controller = TextEditingController();
  final _goalController = TextEditingController();
  String? _geoscope;
  bool _signInTriggered = false;
  bool _pickerTriggered = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // initState runs before the first build, so context.read of bloc state is
    // safe but showing a modal sheet is not. Defer side effects by one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeTriggerSignIn();
      _maybeShowPicker();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _goalController.dispose();
    super.dispose();
  }

  void _maybeTriggerSignIn() {
    if (_signInTriggered) return;
    final authState = context.read<AuthCubit>().state;
    if (authState.status != AuthStatus.unauthenticated) return;
    _signInTriggered = true;
    unawaited(_triggerSignIn());
  }

  Future<void> _triggerSignIn() async {
    final authCubit = context.read<AuthCubit>();
    final router = GoRouter.of(context);
    // Subscribe before calling signIn so we don't miss the authenticated
    // emission if it lands while signIn() is still in flight — the Future
    // returned by signIn resolves separately from the auth stream.
    final authenticated = authCubit.stream.firstWhere(
      (s) => s.status == AuthStatus.authenticated,
    );
    await authCubit.signIn();
    if (!mounted) return;
    if (authCubit.state.status == AuthStatus.authenticated) return;
    // signIn() returned without authenticating: either the auth-stream
    // emission is racing us (success case) or the user cancelled / it
    // failed. Cap the wait so a cancellation doesn't strand the page.
    try {
      await authenticated.timeout(const Duration(seconds: 1));
    } on Object {
      // Timeout or stream error — fall through to redirect.
    }
    if (!mounted) return;
    if (authCubit.state.status != AuthStatus.authenticated) {
      router.go('/');
    }
  }

  void _maybeShowPicker() {
    if (_pickerTriggered) return;
    final authState = context.read<AuthCubit>().state;
    if (authState.status != AuthStatus.authenticated) return;
    final geoCubit = context.read<GeoscopeCubit>();
    final geoState = geoCubit.state;
    if (geoState.status != GeoscopeStatus.success) return;
    if (!geoState.needsSelection) return;
    _pickerTriggered = true;
    geoCubit.acknowledgeSelectionPrompt();
    unawaited(showGeoscopePicker(context));
  }

  Future<void> _save() async {
    if (_submitting || !hasEnoughWords(_controller.text)) return;
    final userId = context.read<AuthCubit>().state.userId;
    if (userId == null) return;
    final l10n = context.l10n;
    final repo = context.read<FirestoreRepository>();
    final router = GoRouter.of(context);
    final userLang = Localizations.localeOf(context).languageCode;
    final selectedGeoscope = context
        .read<GeoscopeCubit>()
        .state
        .selectedGeoscope;
    final geoscope = _geoscope ?? selectedGeoscope;

    setState(() => _submitting = true);
    try {
      await repo.addProblem(
        description: _controller.text.trim(),
        goal: _goalController.text.trim(),
        ownerId: userId,
        geoscope: geoscope,
        userLanguage: userLang,
      );
    } on LanguageMismatchException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(l10n.languageMismatchError(e.descriptionLang, e.goalLang));
      return;
    } on Exception catch (e) {
      log('Failed to create problem: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(l10n.saveProblemError);
      return;
    }
    if (!mounted) return;
    router.go('/');
  }

  Widget _buildForm() {
    final l10n = context.l10n;
    final selectedGeoscope = context
        .watch<GeoscopeCubit>()
        .state
        .selectedGeoscope;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              return TextField(
                controller: _controller,
                readOnly: _submitting,
                maxLength: maxProblemTextLength,
                decoration: InputDecoration(hintText: l10n.addProblemHint),
                onSubmitted: hasEnoughWords(value.text) && !_submitting
                    ? (_) => _save()
                    : null,
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              return TextField(
                controller: _goalController,
                readOnly: _submitting,
                maxLength: maxProblemTextLength,
                decoration: InputDecoration(hintText: l10n.addGoalHint),
                onSubmitted: hasEnoughWords(value.text) && !_submitting
                    ? (_) => _save()
                    : null,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(l10n.geoscopeLabel),
              ...buildGeoscopeDropdown(
                context,
                geoscope: selectedGeoscope,
                currentValue: _geoscope ?? selectedGeoscope,
                compact: false,
                onChanged: (value) => setState(() => _geoscope = value),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final hasWords = hasEnoughWords(_controller.text);
              return Row(
                children: [
                  FilledButton(
                    onPressed: hasWords && !_submitting ? _save : null,
                    child: Text(l10n.problemDetailSaveButton),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _submitting ? null : () => context.go('/'),
                    child: Text(l10n.problemDetailBackButton),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthCubit, AuthState>(
          listenWhen: (prev, curr) => prev.status != curr.status,
          listener: (_, _) {
            _maybeTriggerSignIn();
            _maybeShowPicker();
          },
        ),
        BlocListener<GeoscopeCubit, GeoscopeState>(
          listenWhen: (prev, curr) =>
              prev.status != curr.status ||
              prev.needsSelection != curr.needsSelection,
          listener: (_, _) => _maybeShowPicker(),
        ),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              context.go('/'),
        },
        child: Focus(
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.newProblemPageTitle)),
            body: BlocBuilder<AuthCubit, AuthState>(
              builder: (context, authState) {
                if (authState.status != AuthStatus.authenticated) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildForm();
              },
            ),
          ),
        ),
      ),
    );
  }
}
