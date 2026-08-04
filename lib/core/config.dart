class WorkspaceConfig {
  final int capacity;
  final double retentionSeconds;
  WorkspaceConfig({this.capacity = 32, this.retentionSeconds = 30.0});
}

class WorkingMemoryConfig {
  final int capacity;
  final double retentionSeconds;
  WorkingMemoryConfig({this.capacity = 64, this.retentionSeconds = 120.0});
}

class EpisodicMemoryConfig {
  final int capacity;
  final double recencyHalfLifeSeconds;
  final int sessionIdleThresholdMinutes;

  EpisodicMemoryConfig({
    this.capacity = 10000, 
    this.recencyHalfLifeSeconds = 86400.0,
    this.sessionIdleThresholdMinutes = 30,
  });
}

class SensoryMemoryConfig {
  final int capacity;
  final double retentionSeconds;
  final double salienceThreshold;
  SensoryMemoryConfig({
    this.capacity = 128, 
    this.retentionSeconds = 2.0, 
    this.salienceThreshold = 0.35
  });
}

class SemanticMemoryConfig {
  final int capacity;
  final int minimumEvidence;
  SemanticMemoryConfig({this.capacity = 5000, this.minimumEvidence = 2});
}

class HomeostasisConfig {
  final int queuePressureThreshold;
  final double energyRecoveryPerSecond;
  final double energyDrainPerSecond;
  final double protectiveEnergyThreshold;

  HomeostasisConfig({
    this.queuePressureThreshold = 32,
    this.energyRecoveryPerSecond = 0.08,
    this.energyDrainPerSecond = 0.16,
    this.protectiveEnergyThreshold = 0.25,
  });
}

class CognitiveSystemConfig {
  final WorkspaceConfig workspace = WorkspaceConfig();
  final WorkingMemoryConfig workingMemory = WorkingMemoryConfig();
  final EpisodicMemoryConfig episodicMemory = EpisodicMemoryConfig();
  final SensoryMemoryConfig sensoryMemory = SensoryMemoryConfig();
  final SemanticMemoryConfig semanticMemory = SemanticMemoryConfig();
  final HomeostasisConfig homeostasis = HomeostasisConfig();
}
