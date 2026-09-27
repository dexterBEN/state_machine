abstract class FsmEvent {}

class ConnectRequested extends FsmEvent {}

class DisconnectRequested extends FsmEvent {}

class StartPressed extends FsmEvent {}

class ResetPressed extends FsmEvent {}
