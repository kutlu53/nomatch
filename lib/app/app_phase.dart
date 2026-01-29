enum AppPhase { 
  splash, 
  pairing, 
  playing, 
  gameResult,      // ✅ NEW: Success/fail animation after game ends
  share,           // ✅ Info sharing: player1 shares, waiting for player2
  shareResults,    // ✅ NEW: Display both players' info after share complete
}

// ✅ Result type for game end
enum GameResultType { success, failure }

enum ShareKind { phone, social }

