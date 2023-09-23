package edu.uchicago.cs.systems.wasabi;

import java.util.Random;

abstract class InjectionPolicy {

  public abstract boolean shouldInject(int injectionCount, double injectionProbability);
}

class NoInjection extends InjectionPolicy {
  @Override
  public boolean shouldInject(int injectionCount, double injectionProbability) {
    return false;
  }
}

class InjectForever extends InjectionPolicy {
  @Override
  public boolean shouldInject(int injectionCount, double injectionProbability) {
    return true;
  }
}

class InjectForeverWithProbability extends InjectionPolicy {
  private static final Random randomGenerator = new Random();

  @Override
  public boolean shouldInject(int injectionCount, double injectionProbability) {
    if (randomGenerator.nextDouble() < injectionProbability) {
      return true;
    }
    return false;
  }
}

class InjectUpToMaxCount extends InjectionPolicy {
  private int maxInjectionCount = 0;

  InjectUpToMaxCount(int maxInjectionCount) {
    this.maxInjectionCount = maxInjectionCount;
  }

  @Override
  public boolean shouldInject(int injectionCount, double injectionProbability) {
    if (injectionCount < this.maxInjectionCount) {
      return true;
    }
    return false;
  }
}

class InjectUpToMaxCountWithProbability extends InjectionPolicy {
  private static final Random randomGenerator = new Random();
  private int maxInjectionCount = 0;

  InjectUpToMaxCountWithProbability(int maxInjectionCount) {
    this.maxInjectionCount = maxInjectionCount;
  }
 
  @Override
  public boolean shouldInject(int injectionCount, double injectionProbability) {
    if (randomGenerator.nextDouble() < injectionProbability && injectionCount < this.maxInjectionCount) {
      return true;
    }
    return false;
  }
}
