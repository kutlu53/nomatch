import '../app/pairing_logic.dart';
import '../features/game/game_state.dart';

/// Minimal app state
class AppViewState {
  final PairingState pairingState;
  final GameState? gameState;
  final String? errorMessage;

  // Pairing data
  final String? peerId;
  final String? sessionId;
  final bool isLeader;
  final double? ourHeading;
  final double? peerHeading;
  final bool isPhoneFlat; // ✅ NEW: Phone flat status

  const AppViewState({
    required this.pairingState,
    this.gameState,
    this.errorMessage,
    this.peerId,
    this.sessionId,
    this.isLeader = false,
    this.ourHeading,
    this.peerHeading,
    this.isPhoneFlat = false, // ✅ NEW
  });

  AppViewState copyWith({
    PairingState? pairingState,
    GameState? gameState,
    bool clearGameState = false,
    String? errorMessage,
    bool clearError = false,
    String? peerId,
    String? sessionId,
    bool? isLeader,
    double? ourHeading,
    double? peerHeading,
    bool? isPhoneFlat, // ✅ NEW
  }) {
    return AppViewState(
      pairingState: pairingState ?? this.pairingState,
      gameState: clearGameState ? null : (gameState ?? this.gameState),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      peerId: peerId ?? this.peerId,
      sessionId: sessionId ?? this.sessionId,
      isLeader: isLeader ?? this.isLeader,
      ourHeading: ourHeading ?? this.ourHeading,
      peerHeading: peerHeading ?? this.peerHeading,
      isPhoneFlat: isPhoneFlat ?? this.isPhoneFlat, // ✅ NEW
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppViewState &&
          runtimeType == other.runtimeType &&
          pairingState == other.pairingState &&
          gameState == other.gameState &&
          errorMessage == other.errorMessage &&
          peerId == other.peerId &&
          sessionId == other.sessionId &&
          isLeader == other.isLeader &&
          ourHeading == other.ourHeading &&
          peerHeading == other.peerHeading &&
          isPhoneFlat == other.isPhoneFlat; // ✅ NEW

  @override
  int get hashCode =>
      pairingState.hashCode ^
      gameState.hashCode ^
      errorMessage.hashCode ^
      peerId.hashCode ^
      sessionId.hashCode ^
      isLeader.hashCode ^
      ourHeading.hashCode ^
      peerHeading.hashCode ^
      isPhoneFlat.hashCode; // ✅ NEW
}
