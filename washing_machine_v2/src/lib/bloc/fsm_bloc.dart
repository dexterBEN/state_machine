import 'dart:async';

import 'package:bloc/bloc.dart';

import '../repository/washer_repository.dart';
import 'fsm_state.dart';
import 'fsm_event.dart';

class FsmBloc extends Bloc<FsmEvent, FsmState> {
  final WasherRepository _repository;
  late final StreamSubscription<WasherUpdate> _repositorySubscription;
  Future<void>? _closeFuture;
  bool _isClosing = false;

  /// Owns this repository and closes it when the BLoC is closed.
  FsmBloc({required WasherRepository repository})
      : _repository = repository,
        super(FsmState.initial) {
    on<ConnectRequested>(
        (event, emit) => _connectionOperation(_repository.connect, emit));
    on<DisconnectRequested>(
        (event, emit) => _connectionOperation(_repository.disconnect, emit));
    on<StartPressed>((event, emit) => _command(_repository.start, emit));
    on<ResetPressed>((event, emit) => _command(_repository.reset, emit));
    on<_RepositoryUpdated>(_onRepositoryUpdate);

    _repositorySubscription = _repository.updates.listen((update) {
      if (!_isClosing) add(_RepositoryUpdated(update));
    });
  }

  Future<void> _connectionOperation(
    Future<void> Function() operation,
    Emitter<FsmState> emit,
  ) async {
    if (_isClosing) return;
    try {
      await operation();
    } catch (error) {
      if (!_isClosing) {
        emit(state.copyWith(connected: false, lastError: error.toString()));
      }
    }
  }

  void _command(void Function() command, Emitter<FsmState> emit) {
    if (_isClosing || !state.connected) return;
    try {
      command();
    } catch (error) {
      emit(state.copyWith(lastError: error.toString()));
    }
  }

  void _onRepositoryUpdate(_RepositoryUpdated event, Emitter<FsmState> emit) {
    if (_isClosing) return;
    switch (event.update) {
      case WasherConnectionChanged(:final connected, :final error):
        emit(state.copyWith(connected: connected, lastError: error));
      case WasherStateReceived(:final state):
        emit(this.state.copyWith(washState: state));
      case WasherFailure(:final message):
        emit(state.copyWith(lastError: message));
    }
  }

  Future<void> _dispose() async {
    try {
      await _repositorySubscription.cancel();
    } finally {
      await _repository.close();
    }
  }

  @override
  Future<void> close() {
    _isClosing = true;
    return _closeFuture ??= _dispose().whenComplete(() => super.close());
  }
}

final class _RepositoryUpdated extends FsmEvent {
  final WasherUpdate update;
  _RepositoryUpdated(this.update);
}
